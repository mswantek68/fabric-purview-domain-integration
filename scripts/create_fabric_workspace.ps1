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

if (-not $WorkspaceName) { Fail 'FABRIC_WORKSPACE_NAME unresolved (no outputs/env/bicep).' }

# Acquire tokens
try { $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv } catch { $accessToken = $null }
if (-not $accessToken) { Fail "Failed to obtain access token for Fabric API (az login with a Fabric admin)" }

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'

# Resolve capacity GUID if capacity ARM id given
$capacityGuid = $null
if ($CapacityId) {
  $capName = ($CapacityId -split '/')[ -1 ]
  try { $caps = Invoke-RestMethod -Uri "$apiRoot/admin/capacities" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop } catch { $caps = $null }
  if ($caps.value) { $match = $caps.value | Where-Object { ($_.displayName -eq $capName) -or ($_.name -eq $capName) }; if ($match) { $capacityGuid = $match.id } }
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
    } catch { Warn "Capacity reassign failed: $_" }
  }
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
        } catch { Warn "Failed to add $admin: $_" }
      } else { Log "Admin already present: $admin" }
    }
  }
  # export workspace env
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
} catch { Fail "Workspace creation failed: $_" }

# Assign to capacity
if ($capacityGuid) {
  try {
    $assignResp = Invoke-WebRequest -Uri "$apiRoot/groups/$workspaceId/AssignToCapacity" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body (@{ capacityId = $capacityGuid } | ConvertTo-Json) -UseBasicParsing -ErrorAction Stop
    Log "Capacity assignment response: $($assignResp.StatusCode)"
  } catch { Warn "Capacity assignment failed: $_" }
} else { Warn 'No capacity GUID resolved; skipping capacity assignment.' }

# Add admins
if ($AdminUPNs) {
  $admins = $AdminUPNs -split ',' | ForEach-Object { $_.Trim() }
  foreach ($admin in $admins) {
    if ([string]::IsNullOrWhiteSpace($admin)) { continue }
    try {
      Invoke-WebRequest -Uri "$apiRoot/groups/$workspaceId/users" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body (@{ identifier = $admin; groupUserAccessRight = 'Admin'; principalType = 'User' } | ConvertTo-Json) -UseBasicParsing -ErrorAction Stop
      Log "Added admin: $admin"
    } catch { Warn "Failed to add $admin: $_" }
  }
}

# Export
Set-Content -Path '/tmp/fabric_workspace.env' -Value "FABRIC_WORKSPACE_ID=$workspaceId`nFABRIC_WORKSPACE_NAME=$WorkspaceName"
Log 'Fabric workspace provisioning via REST complete.'
exit 0
