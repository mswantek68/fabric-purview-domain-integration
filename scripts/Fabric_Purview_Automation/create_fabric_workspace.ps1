<#
.SYNOPSIS
  Create a Fabric workspace and assign to a capacity; add admins; associate to domain.
#>

[CmdletBinding()]
param(
  [string]$WorkspaceName = $env:FABRIC_WORKSPACE_NAME,
  [string]$CapacityId = $env:FABRIC_CAPACITY_ID,
  [string]$AdminUPNs = $env:FABRIC_ADMIN_UPNS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import security module
$SecurityModulePath = Join-Path $PSScriptRoot "../SecurityModule.ps1"
. $SecurityModulePath

function Log([string]$m){ Write-Host "[fabric-workspace] $m" }
function Warn([string]$m){ Write-Warning "[fabric-workspace] $m" }
function Fail([string]$m){ Write-Error "[fabric-workspace] $m"; Clear-SensitiveVariables -VariableNames @('accessToken','fabricAccessToken'); exit 1 }

function Wait-FabricOperationResult {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$OperationUrl,
    [int]$RetryAfterSeconds = 5
  )

  if (-not $OperationUrl) { return $null }
  $wait = if ($RetryAfterSeconds -gt 0) { $RetryAfterSeconds } else { 5 }

  while ($true) {
    Start-Sleep -Seconds $wait
    try {
      $opState = Invoke-SecureRestMethod -Uri $OperationUrl -Headers $fabricHeaders -Method Get -Description "Fabric operation status"
    } catch {
      Fail "Unable to poll Fabric operation status: $($_.Exception.Message)"
    }

    if ($opState.status -eq 'Succeeded') {
      try {
        return Invoke-SecureRestMethod -Uri "$OperationUrl/result" -Headers $fabricHeaders -Method Get -Description "Fabric operation result"
      } catch {
        return $null
      }
    }

    if ($opState.status -in @('Failed','Canceled','Cancelled')) {
      Fail "Fabric operation at $OperationUrl ended with status '$($opState.status)'"
    }

    $wait = if ($opState.retryAfterSeconds -and [int]$opState.retryAfterSeconds -gt 0) { [int]$opState.retryAfterSeconds } else { 5 }
  }
}

# Calls Fabric Workspaces - Provision Identity API to guarantee the managed identity exists
# https://learn.microsoft.com/en-us/rest/api/fabric/core/workspaces/provision-identity
function Confirm-FabricWorkspaceIdentity {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$WorkspaceId,
    [Parameter(Mandatory = $true)][string]$WorkspaceName
  )

  Log "Ensuring workspace identity for '$WorkspaceName'..."
  try {
    $workspace = Invoke-SecureRestMethod -Uri "$fabricApiRoot/workspaces/$WorkspaceId" -Headers $fabricHeaders -Method Get -Description "Fabric workspace lookup"
  } catch {
    Fail "Failed to retrieve workspace from Fabric API: $($_.Exception.Message)"
  }

  if ($workspace.workspaceIdentity -and $workspace.workspaceIdentity.applicationId) {
    Log "Workspace identity already exists (AppId=$($workspace.workspaceIdentity.applicationId))."
    return $workspace.workspaceIdentity
  }

  Log "Workspace identity missing; provisioning via Fabric API..."
  try {
    $identityResponse = Invoke-SecureWebRequest -Uri "$fabricApiRoot/workspaces/$WorkspaceId/provisionIdentity" -Headers $fabricHeaders -Method Post -Description "Fabric workspace identity provisioning"
  } catch {
    Fail "Workspace identity provisioning failed: $($_.Exception.Message)"
  }

  $identity = $null
  if ($identityResponse.StatusCode -eq 200) {
    $identity = $identityResponse.Content | ConvertFrom-Json
  } elseif ($identityResponse.StatusCode -eq 202) {
    $operationUrl = $identityResponse.Headers['Location']
    $retryAfter = 5
    if ($identityResponse.Headers['Retry-After']) {
      [int]$retryAfter = $identityResponse.Headers['Retry-After']
    }
    $identity = Wait-FabricOperationResult -OperationUrl $operationUrl -RetryAfterSeconds $retryAfter

    if (-not $identity) {
      Start-Sleep -Seconds 5
      try {
        $workspace = Invoke-SecureRestMethod -Uri "$fabricApiRoot/workspaces/$WorkspaceId" -Headers $fabricHeaders -Method Get -Description "Fabric workspace lookup"
        $identity = $workspace.workspaceIdentity
      } catch {
        Fail "Fabric operation completed but identity details are unavailable: $($_.Exception.Message)"
      }
    }
  } else {
    Fail "Unexpected Fabric API status code $($identityResponse.StatusCode) while provisioning workspace identity."
  }

  if (-not $identity -or -not $identity.applicationId) {
    Fail 'Workspace identity provisioning returned no identity details.'
  }

  Log "Workspace identity ready (ServicePrincipalId=$($identity.servicePrincipalId))."
  Log "Grant this identity Azure AI Search or private link permissions by referencing the Service Principal ID above."
  return $identity
}

function Write-WorkspaceEnvironmentFile {
  param(
    [string]$WorkspaceId,
    [string]$WorkspaceName,
    [object]$WorkspaceIdentity
  )

  $lines = @(
    "FABRIC_WORKSPACE_ID=$WorkspaceId",
    "FABRIC_WORKSPACE_NAME=$WorkspaceName"
  )

  if ($WorkspaceIdentity) {
    if ($WorkspaceIdentity.servicePrincipalId) {
      $lines += "FABRIC_WORKSPACE_IDENTITY_OBJECT_ID=$($WorkspaceIdentity.servicePrincipalId)"
    }
    if ($WorkspaceIdentity.applicationId) {
      $lines += "FABRIC_WORKSPACE_IDENTITY_APP_ID=$($WorkspaceIdentity.applicationId)"
    }
  }

  Set-Content -Path '/tmp/fabric_workspace.env' -Value ($lines -join "`n")
}

# Resolve from AZURE_OUTPUTS_JSON if present
if (-not $WorkspaceName -and $env:AZURE_OUTPUTS_JSON) {
  try { $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json; $WorkspaceName = $out.desiredFabricWorkspaceName.value } catch {}
}
if (-not $CapacityId -and $env:AZURE_OUTPUTS_JSON) {
  try { $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json; $CapacityId = $out.fabricCapacityId.value } catch {}
}

# Fallbacks: try .azure/<env>/.env and infra/main.bicep before failing
if (-not $WorkspaceName) {
  # Try .azure env file
  $azureEnvName = $env:AZURE_ENV_NAME
  if (-not $azureEnvName -and (Test-Path '.azure')) {
    $dirs = Get-ChildItem -Path '.azure' -Name -ErrorAction SilentlyContinue
    if ($dirs) { $azureEnvName = $dirs[0] }
  }
  if ($azureEnvName) {
    $envFile = Join-Path -Path '.azure' -ChildPath "$azureEnvName/.env"
    if (Test-Path $envFile) {
      Get-Content $envFile | ForEach-Object {
        if ($_ -match '^FABRIC_WORKSPACE_NAME=(.+)$') { Set-Variable -Name WorkspaceName -Value ($Matches[1].Trim("'", '"')) -Scope Script }
        if ($_ -match '^fabricCapacityId=(.+)$') { Set-Variable -Name CapacityId -Value ($Matches[1].Trim("'", '"')) -Scope Script }
      }
    }
  }
}

if (-not $WorkspaceName -and (Test-Path 'infra/main.bicepparam')) {
  try {
    $bicepparam = Get-Content 'infra/main.bicepparam' -Raw
    $m = [regex]::Match($bicepparam, "param\s+fabricWorkspaceName\s*=\s*'(?<val>[^']+)'")
    if ($m.Success) {
      $val = $m.Groups['val'].Value
      if ($val -and -not ($val -match '^<.*>$')) { $WorkspaceName = $val }
    }
  } catch {}
}

if (-not $WorkspaceName -and (Test-Path 'infra/main.bicep')) {
  try {
    $bicep = Get-Content 'infra/main.bicep' -Raw
    $m = [regex]::Match($bicep, "param\s+fabricWorkspaceName\s+string\s*=\s*'(?<val>[^']+)'")
    if ($m.Success) {
      $val = $m.Groups['val'].Value
      if ($val -and -not ($val -match '^<.*>$')) { $WorkspaceName = $val }
    }
  } catch {}
}

if (-not $WorkspaceName) { Fail 'FABRIC_WORKSPACE_NAME unresolved (no outputs/env/bicep).' }

# Acquire tokens securely
try {
  Log "Acquiring Power BI API token..."
  $accessToken = Get-SecureApiToken -Resource $SecureApiResources.PowerBI -Description "Power BI"
  Log "Acquiring Fabric API token..."
  $fabricAccessToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric"
} catch {
  Fail "Authentication failed: $($_.Exception.Message)"
}

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'
$fabricApiRoot = 'https://api.fabric.microsoft.com/v1'

# Create secure headers
$powerBIHeaders = New-SecureHeaders -Token $accessToken
$fabricHeaders = New-SecureHeaders -Token $fabricAccessToken

# Resolve capacity GUID if capacity ARM id given
$capacityGuid = $null
Log "CapacityId parameter: '$CapacityId'"
if ($CapacityId) {
  $capName = ($CapacityId -split '/')[ -1 ]
  Log "Deriving Fabric capacity GUID for name: $capName"
  
  try { 
    $caps = Invoke-SecureRestMethod -Uri "$apiRoot/admin/capacities" -Headers $powerBIHeaders -Method Get
    if ($caps.value) { 
      Log "Searching through $($caps.value.Count) capacities for: '$capName'"
      
      # Use a simple foreach loop instead of Where-Object to debug comparison issues
      foreach ($cap in $caps.value) {
        $capDisplayName = if ($cap.PSObject.Properties['displayName']) { $cap.displayName } else { '' }
        $capName2 = if ($cap.PSObject.Properties['name']) { $cap.name } else { '' }
        
        Log "  Checking capacity: displayName='$capDisplayName' name='$capName2' id='$($cap.id)'"
        
        # Direct string comparison
        if ($capDisplayName -eq $capName -or $capName2 -eq $capName) {
          $capacityGuid = $cap.id
          Log "EXACT MATCH FOUND: Using capacity '$capDisplayName' with GUID: $capacityGuid"
          break
        }
        
        # Case-insensitive fallback
        if ($capDisplayName.ToLower() -eq $capName.ToLower() -or $capName2.ToLower() -eq $capName.ToLower()) {
          $capacityGuid = $cap.id
          Log "CASE-INSENSITIVE MATCH FOUND: Using capacity '$capDisplayName' with GUID: $capacityGuid"
          break
        }
      }
      
      if (-not $capacityGuid) {
        Log "NO MATCH FOUND. Available capacities:"
        foreach ($cap in $caps.value) {
          Log "  - displayName='$($cap.displayName)' name='$($cap.name)' id='$($cap.id)'"
        }
        Fail "Could not find capacity named '$capName'"
      }
    } else {
      Fail "No capacities returned from API"
    }
  } catch { 
    Fail "Failed to query capacities: $_"
  }
  
  if ($capacityGuid) {
    Log "Resolved capacity GUID: $capacityGuid"
  } else {
    Fail "Could not resolve capacity GUID for '$capName'"
  }
}

# Check if workspace exists
$workspaceId = $null
try {
  $groups = Invoke-SecureRestMethod -Uri "$apiRoot/groups?%24top=5000" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
  $g = $groups.value | Where-Object { $_.name -eq $WorkspaceName }
  if ($g) { $workspaceId = $g.id }
} catch { }

if ($workspaceId) {
  Log "Workspace '$WorkspaceName' already exists (id=$workspaceId). Ensuring capacity assignment & admins."
  if ($capacityGuid) {
    Log "Assigning workspace to capacity GUID $capacityGuid"
    try {
      $assignResp = Invoke-SecureWebRequest -Uri "$apiRoot/groups/$workspaceId/AssignToCapacity" -Method Post -Headers ($powerBIHeaders) -Body (@{ capacityId = $capacityGuid } | ConvertTo-Json) -ErrorAction Stop
      Log "Capacity assignment response: $($assignResp.StatusCode)"
      
      # Verify assignment worked
      Start-Sleep -Seconds 3
      $workspace = Invoke-SecureRestMethod -Uri "$apiRoot/groups/$workspaceId" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
      if ($workspace.capacityId) {
        Log "Workspace successfully assigned to capacity: $($workspace.capacityId)"
      } else {
        Fail "Workspace capacity assignment verification failed - workspace still has no capacity"
      }
    } catch { Fail "Capacity reassign failed: $_" }
  } else { Fail 'No capacity GUID resolved; cannot proceed without capacity assignment.' }
  # assign admins
  if ($AdminUPNs) {
    $admins = $AdminUPNs -split ',' | ForEach-Object { $_.Trim() }
    try { $currentUsers = Invoke-SecureRestMethod -Uri "$apiRoot/groups/$workspaceId/users" -Headers $powerBIHeaders -Method Get -ErrorAction Stop } catch { $currentUsers = $null }
    foreach ($admin in $admins) {
      if ([string]::IsNullOrWhiteSpace($admin)) { continue }
      $hasAdmin = $false
      if ($currentUsers -and $currentUsers.value) { $hasAdmin = ($currentUsers.value | Where-Object { $_.identifier -eq $admin -and $_.groupUserAccessRight -eq 'Admin' }) }
      if (-not $hasAdmin) {
        Log "Adding admin: $admin"
        try {
          Invoke-SecureWebRequest -Uri "$apiRoot/groups/$workspaceId/users" -Method Post -Headers ($powerBIHeaders) -Body (@{ identifier = $admin; groupUserAccessRight = 'Admin'; principalType = 'User' } | ConvertTo-Json) -ErrorAction Stop
        } catch { Warn "Failed to add $($admin): $($_)" }
      } else { Log "Admin already present: $admin" }
    }
  }

  $workspaceIdentity = Confirm-FabricWorkspaceIdentity -WorkspaceId $workspaceId -WorkspaceName $WorkspaceName
  Write-WorkspaceEnvironmentFile -WorkspaceId $workspaceId -WorkspaceName $WorkspaceName -WorkspaceIdentity $workspaceIdentity
  exit 0
}

# Create workspace
Log "Creating Fabric workspace '$WorkspaceName'..."
$createPayload = @{ name = $WorkspaceName; type = 'Workspace' } | ConvertTo-Json -Depth 4
try {
  $resp = Invoke-SecureWebRequest -Uri "$apiRoot/groups?workspaceV2=true" -Method Post -Headers $powerBIHeaders -Body $createPayload -ErrorAction Stop
  $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
  $workspaceId = $body.id
  Log "Created workspace id: $workspaceId"
} catch { Fail "Workspace creation failed: $_" }

# Assign to capacity
if ($capacityGuid) {
  try {
    Log "Assigning workspace to capacity GUID: $capacityGuid"
    $assignResp = Invoke-SecureWebRequest -Uri "$apiRoot/groups/$workspaceId/AssignToCapacity" -Method Post -Headers ($powerBIHeaders) -Body (@{ capacityId = $capacityGuid } | ConvertTo-Json) -ErrorAction Stop
    Log "Capacity assignment response: $($assignResp.StatusCode)"
    
    # Verify assignment worked
    Start-Sleep -Seconds 3
    $workspace = Invoke-SecureRestMethod -Uri "$apiRoot/groups/$workspaceId" -Headers $powerBIHeaders -Method Get -ErrorAction Stop
    if ($workspace.capacityId) {
      Log "Workspace successfully assigned to capacity: $($workspace.capacityId)"
    } else {
      Fail "Workspace capacity assignment verification failed - workspace still has no capacity"
    }
  } catch { Fail "Capacity assignment failed: $_" }
} else { Fail 'No capacity GUID resolved; cannot create workspace without capacity assignment.' }

# Add admins
if ($AdminUPNs) {
  $admins = $AdminUPNs -split ',' | ForEach-Object { $_.Trim() }
  foreach ($admin in $admins) {
    if ([string]::IsNullOrWhiteSpace($admin)) { continue }
    try {
      Invoke-SecureWebRequest -Uri "$apiRoot/groups/$workspaceId/users" -Method Post -Headers ($powerBIHeaders) -Body (@{ identifier = $admin; groupUserAccessRight = 'Admin'; principalType = 'User' } | ConvertTo-Json) -ErrorAction Stop
      Log "Added admin: $admin"
    } catch { Warn "Failed to add $($admin): $($_)" }
  }
}

$workspaceIdentity = Confirm-FabricWorkspaceIdentity -WorkspaceId $workspaceId -WorkspaceName $WorkspaceName

# Export
Write-WorkspaceEnvironmentFile -WorkspaceId $workspaceId -WorkspaceName $WorkspaceName -WorkspaceIdentity $workspaceIdentity
Log 'Fabric workspace provisioning via REST complete.'

# Clean up sensitive variables
Clear-SensitiveVariables -VariableNames @('accessToken','fabricAccessToken')
exit 0
