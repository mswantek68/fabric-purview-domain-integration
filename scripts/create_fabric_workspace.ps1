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

function Log([string]$m){ Write-Host "[fabric-workspace] $m" }
function Warn([string]$m){ Write-Warning "[fabric-workspace] $m" }
function Fail([string]$m){ Write-Error "[fabric-workspace] $m"; exit 1 }

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
        if ($_ -match '^FABRIC_WORKSPACE_NAME=(.+)$') { $WorkspaceName = $Matches[1].Trim("'", '"') }
        if ($_ -match '^fabricCapacityId=(.+)$') { $CapacityId = $Matches[1].Trim("'", '"') }
      }
    }
  }
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

# Acquire tokens
try { $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv } catch { $accessToken = $null }
if (-not $accessToken) { Fail "Failed to obtain access token for Fabric API (az login with a Fabric admin)" }

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'

# Resolve capacity GUID if capacity ARM id given
$capacityGuid = $null
Log "CapacityId parameter: '$CapacityId'"
if ($CapacityId) {
  $capName = ($CapacityId -split '/')[ -1 ]
  Log "Deriving Fabric capacity GUID for name: $capName"
  
  try { 
    $caps = Invoke-RestMethod -Uri "$apiRoot/admin/capacities" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
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
    Fail "Failed to query capacities: $($_.Exception.Message)"
  }
  
  if ($capacityGuid) {
    Log "Resolved capacity GUID: $capacityGuid"
    # Save capacity GUID for subsequent scripts
    "$capacityGuid" | Out-File -FilePath '/tmp/fabric_capacity_guid.txt' -Encoding UTF8
  } else {
    Fail "Could not resolve capacity GUID for '$capName'"
  }
}

# Check if workspace exists
$workspaceId = $null
try {
  $groups = Invoke-RestMethod -Uri "$apiRoot/groups?%24top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  $g = $groups.value | Where-Object { $_.name -eq $WorkspaceName }
  if ($g) { $workspaceId = $g.id }
} catch { }

if ($workspaceId) {
  Log "Workspace '$WorkspaceName' already exists (id=$workspaceId). Ensuring capacity assignment & admins."
  if ($capacityGuid) {
    Log "Assigning workspace to capacity GUID $capacityGuid"
    try {
      $assignResp = Invoke-WebRequest -Uri "$apiRoot/groups/$workspaceId/AssignToCapacity" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body (@{ capacityId = $capacityGuid } | ConvertTo-Json) -UseBasicParsing -ErrorAction Stop
      Log "Capacity assignment response: $($assignResp.StatusCode)"
      
      # Verify assignment worked
      Start-Sleep -Seconds 3
      $workspace = Invoke-RestMethod -Uri "$apiRoot/groups/$workspaceId" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
      if ($workspace.capacityId) {
        Log "Workspace successfully assigned to capacity: $($workspace.capacityId)"
      } else {
        Fail "Workspace capacity assignment verification failed - workspace still has no capacity"
      }
    } catch { Fail "Capacity reassign failed: $($_.Exception.Message)" }
  } else { Fail 'No capacity GUID resolved; cannot proceed without capacity assignment.' }
  # assign admins
  if ($AdminUPNs) {
    $admins = $AdminUPNs -split ',' | ForEach-Object { $_.Trim() }
    try { $currentUsers = Invoke-RestMethod -Uri "$apiRoot/groups/$workspaceId/users" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop } catch { $currentUsers = $null }
    foreach ($admin in $admins) {
      if ([string]::IsNullOrWhiteSpace($admin)) { continue }
      $hasAdmin = $false
      if ($currentUsers -and $currentUsers.value) { $hasAdmin = ($currentUsers.value | Where-Object { $_.identifier -eq $admin -and $_.groupUserAccessRight -eq 'Admin' }) }
      if (-not $hasAdmin) {
        Log "Adding admin: $admin"
        try {
          Invoke-WebRequest -Uri "$apiRoot/groups/$workspaceId/users" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body (@{ identifier = $admin; groupUserAccessRight = 'Admin'; principalType = 'User' } | ConvertTo-Json) -UseBasicParsing -ErrorAction Stop
        } catch { Warn "Failed to add $($admin): $($_)" }
      } else { Log "Admin already present: $admin" }
    }
  }
  # Export workspace id/name for downstream scripts
  Set-Content -Path '/tmp/fabric_workspace.env' -Value "FABRIC_WORKSPACE_ID=$workspaceId`nFABRIC_WORKSPACE_NAME=$WorkspaceName"
  exit 0
}

# Create workspace
Log "Creating Fabric workspace '$WorkspaceName'..."
$createPayload = @{ name = $WorkspaceName; type = 'Workspace' } | ConvertTo-Json -Depth 4
try {
  $resp = Invoke-WebRequest -Uri "$apiRoot/groups?workspaceV2=true" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body $createPayload -UseBasicParsing -ErrorAction Stop
  $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
  $workspaceId = $body.id
  Log "Created workspace id: $workspaceId"
} catch { Fail "Workspace creation failed: $($_.Exception.Message)" }

# Assign to capacity
if ($capacityGuid) {
  try {
    Log "Assigning workspace to capacity GUID: $capacityGuid"
    $assignResp = Invoke-WebRequest -Uri "$apiRoot/groups/$workspaceId/AssignToCapacity" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body (@{ capacityId = $capacityGuid } | ConvertTo-Json) -UseBasicParsing -ErrorAction Stop
    Log "Capacity assignment response: $($assignResp.StatusCode)"
    
    # Verify assignment worked
    Start-Sleep -Seconds 3
    $workspace = Invoke-RestMethod -Uri "$apiRoot/groups/$workspaceId" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    if ($workspace.capacityId) {
      Log "Workspace successfully assigned to capacity: $($workspace.capacityId)"
    } else {
      Fail "Workspace capacity assignment verification failed - workspace still has no capacity"
    }
  } catch { Fail "Capacity assignment failed: $($_.Exception.Message)" }
} else { Fail 'No capacity GUID resolved; cannot create workspace without capacity assignment.' }

# Add admins
if ($AdminUPNs) {
  $admins = $AdminUPNs -split ',' | ForEach-Object { $_.Trim() }
  foreach ($admin in $admins) {
    if ([string]::IsNullOrWhiteSpace($admin)) { continue }
    try {
      Invoke-WebRequest -Uri "$apiRoot/groups/$workspaceId/users" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body (@{ identifier = $admin; groupUserAccessRight = 'Admin'; principalType = 'User' } | ConvertTo-Json) -UseBasicParsing -ErrorAction Stop
      Log "Added admin: $admin"
    } catch { Warn "Failed to add $($admin): $($_)" }
  }
}

# Export
Set-Content -Path '/tmp/fabric_workspace.env' -Value "FABRIC_WORKSPACE_ID=$workspaceId`nFABRIC_WORKSPACE_NAME=$WorkspaceName"
Log 'Fabric workspace provisioning via REST complete.'
exit 0
