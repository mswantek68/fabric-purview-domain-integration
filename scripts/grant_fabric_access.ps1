<#
.SYNOPSIS
  Grants Fabric workspace (and implicitly lakehouse) Viewer access to the AI Search managed identity so that, once the OneLake connector is enabled, the indexer identity can read data.

.DESCRIPTION
  Uses the Power BI / Fabric admin API to add the target principal (system-assigned or user-assigned managed identity / service principal) to the workspace with Viewer rights.
  Idempotent: skips if already present.

  Resolution order for principal Id:
    1. -SearchPrincipalId parameter
    2. $env:SEARCH_PRINCIPAL_ID
    3. Bicep outputs: executionManagedIdentityPrincipalId
    4. Bicep outputs: aiFoundryManagedIdentityPrincipalId (fallback if execution not found)

  Workspace resolution:
    1. /tmp/fabric_workspace.env
    2. Bicep outputs desiredFabricWorkspaceName then lookup via API

  Requires: az login (principal must have Fabric admin or workspace admin rights to add users).
#>

[CmdletBinding()]
param(
  [string]$SearchPrincipalId = $env:SEARCH_PRINCIPAL_ID,
  [string]$AccessRight = 'Viewer'  # Could be Member if broader rights needed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[grant-fabric-access] $m" }
function Warn([string]$m){ Write-Warning "[grant-fabric-access] $m" }
function Fail([string]$m){ Write-Error "[grant-fabric-access] $m"; exit 1 }

# Load azd / bicep outputs if available
$outputsJson = $null
if ($env:AZURE_OUTPUTS_JSON) { $outputsJson = $env:AZURE_OUTPUTS_JSON }
elseif (Test-Path '/tmp/azd-outputs.json') { try { $outputsJson = Get-Content '/tmp/azd-outputs.json' -Raw } catch {} }

# Early direct attempts via azd env / infra output (some environments don't expose AZURE_OUTPUTS_JSON)
if (-not $SearchPrincipalId) {
  try {
    $envVal = & azd env get-value executionManagedIdentityPrincipalId 2>$null
    if ($envVal -and $envVal -notmatch '^<.*>$') { $SearchPrincipalId = $envVal; Log "Resolved principal from azd env: $SearchPrincipalId" }
  } catch {}
}
if (-not $SearchPrincipalId) {
  try {
    $infraVal = & azd infra output executionManagedIdentityPrincipalId -o tsv 2>$null
    if ($infraVal -and $infraVal -notmatch '^<.*>$') { $SearchPrincipalId = $infraVal; Log "Resolved principal from azd infra output: $SearchPrincipalId" }
  } catch {}
}

if (-not $SearchPrincipalId -and $outputsJson) {
  try {
    $outs = $outputsJson | ConvertFrom-Json
    if ($outs.executionManagedIdentityPrincipalId.value) { $SearchPrincipalId = $outs.executionManagedIdentityPrincipalId.value }
    elseif ($outs.aiFoundryManagedIdentityPrincipalId.value) { $SearchPrincipalId = $outs.aiFoundryManagedIdentityPrincipalId.value }
  } catch { Warn 'Unable to parse outputs JSON for principal ids' }
}

if (-not $SearchPrincipalId -or ($SearchPrincipalId -match '^<.*>$')) {
  Warn 'Primary resolution for SearchPrincipalId failed. Attempting fallback discovery...'

  # 1. Try live infra outputs (azd infra output)
  if (-not $outputsJson) {
    try {
      $liveOutputs = & azd infra output -o json 2>$null
      if ($liveOutputs) { $outputsJson = $liveOutputs }
    } catch { Warn 'Could not retrieve live infra outputs via azd.' }
  }
  if (-not $SearchPrincipalId -and $outputsJson) {
    try {
      $outs2 = $outputsJson | ConvertFrom-Json
      if ($outs2.executionManagedIdentityPrincipalId.value) { $SearchPrincipalId = $outs2.executionManagedIdentityPrincipalId.value; Log "Resolved principal from live outputs: $SearchPrincipalId" }
      elseif ($outs2.aiFoundryManagedIdentityPrincipalId.value) { $SearchPrincipalId = $outs2.aiFoundryManagedIdentityPrincipalId.value; Log "Resolved principal (foundry) from live outputs: $SearchPrincipalId" }
    } catch { Warn 'Parsing live outputs failed.' }
  }

  # 2. If still missing, attempt to derive from Search service system-assigned identity
  if (-not $SearchPrincipalId) {
    # Need AI Search name and resource group
    $aiSearchName = $null; $aiSearchRg = $null; $aiSearchSub = $null
    # From outputs JSON if present
    if ($outputsJson) {
      try {
        $outs3 = $outputsJson | ConvertFrom-Json
        if ($outs3.aiSearchName.value) { $aiSearchName = $outs3.aiSearchName.value }
        if ($outs3.aiSearchResourceGroup.value) { $aiSearchRg = $outs3.aiSearchResourceGroup.value }
        if ($outs3.aiSearchSubscriptionId.value) { $aiSearchSub = $outs3.aiSearchSubscriptionId.value }
      } catch {}
    }
    if (-not $aiSearchName -and $env:aiSearchName) { $aiSearchName = $env:aiSearchName }
    if (-not $aiSearchRg -and $env:aiSearchResourceGroup) { $aiSearchRg = $env:aiSearchResourceGroup }
    if (-not $aiSearchSub -and $env:aiSearchSubscriptionId) { $aiSearchSub = $env:aiSearchSubscriptionId }

    if ($aiSearchName -and $aiSearchRg) {
      Log "Attempting to read system-assigned identity from AI Search service '$aiSearchName'..."
      try {
        $cmd = @('search','service','show','-n', $aiSearchName,'-g',$aiSearchRg,'-o','json')
        if ($aiSearchSub) { $cmd += @('--subscription', $aiSearchSub) }
        $searchJson = & az @cmd 2>$null
        if ($searchJson) {
          try { $searchObj = $searchJson | ConvertFrom-Json } catch { $searchObj = $null }
          if ($searchObj -and $searchObj.identity -and $searchObj.identity.principalId) {
            $SearchPrincipalId = $searchObj.identity.principalId
            Log "Derived principal from Search service identity: $SearchPrincipalId"
          } else { Warn 'Search service identity not present or principalId missing (system-assigned identity may be disabled).' }
        }
      } catch { Warn "Failed to query AI Search service for identity: $($_.Exception.Message)" }
    } else {
      Warn 'Insufficient data (aiSearchName/resourceGroup) to query Search service identity.'
    }
  }

  # 3. Optional: enumerate resource list if still unresolved
  if (-not $SearchPrincipalId -and $aiSearchName) {
    try {
      $resList = & az resource list --name $aiSearchName --resource-type Microsoft.Search/searchServices -o json 2>$null
      if ($resList) {
        $resObjs = $resList | ConvertFrom-Json
        if ($resObjs -and $resObjs.Count -gt 0) {
          $first = $resObjs[0]
          if ($first.identity -and $first.identity.principalId) {
            $SearchPrincipalId = $first.identity.principalId
            Log "Resolved principal from generic resource list: $SearchPrincipalId"
          }
        }
      }
    } catch { Warn 'Generic resource list lookup failed.' }
  }

  # Final check
  if (-not $SearchPrincipalId -or ($SearchPrincipalId -match '^<.*>$')) {
    Fail 'Unable to resolve a valid principal id for workspace access grant after all fallbacks.'
  }
}

# Resolve workspace id & name
$workspaceId = $null; $workspaceName = $null
if (Test-Path '/tmp/fabric_workspace.env') {
  Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
  if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $workspaceId = $Matches[1].Trim(); $null = $workspaceId }
  if ($_ -match '^FABRIC_WORKSPACE_NAME=(.+)$') { $workspaceName = $Matches[1].Trim(); $null = $workspaceName }
  }
  if ($workspaceId -or $workspaceName) { Log "Resolved workspace env: id=$workspaceId name=$workspaceName" }
}

if (-not $workspaceName -and $outputsJson) {
  try {
    $outs = $outputsJson | ConvertFrom-Json
    if ($outs.desiredFabricWorkspaceName.value) { $workspaceName = $outs.desiredFabricWorkspaceName.value }
  } catch {}
}

# Acquire Fabric token (Power BI API resource)
try { $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv } catch { $accessToken = $null }
if (-not $accessToken) { Fail 'Failed to acquire Fabric API token (az login as Fabric admin required).' }

$pbApi = 'https://api.powerbi.com/v1.0/myorg'

if (-not $workspaceId -and $workspaceName) {
  try {
    $groups = Invoke-RestMethod -Uri "$pbApi/groups?%24top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    $g = $groups.value | Where-Object { $_.name -eq $workspaceName }
    if ($g) { $workspaceId = $g.id }
  } catch { Warn 'Unable to lookup workspace by name.' }
}

if (-not $workspaceId) { Fail 'Workspace id unresolved (ensure create_fabric_workspace.ps1 ran successfully).' }

Log "Target workspace id: $workspaceId ($workspaceName)"
Log "Target principal (Search MI) object/principal id: $SearchPrincipalId"
Log "Requested access right: $AccessRight"

# Check existing users
$existing = $null
try { $existing = Invoke-RestMethod -Uri "$pbApi/groups/$workspaceId/users" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop } catch { Warn 'Failed to enumerate current workspace users.' }

$already = $false
if ($existing -and $existing.value) {
  $already = ($null -ne ($existing.value | Where-Object { $_.identifier -eq $SearchPrincipalId }))
}

if ($already) { Log 'Principal already has workspace access; skipping add.'; exit 0 }

Log "Adding principal as $AccessRight..."
$body = @{ identifier = $SearchPrincipalId; groupUserAccessRight = $AccessRight; principalType = 'App' } | ConvertTo-Json -Depth 4
try {
  $resp = Invoke-WebRequest -Uri "$pbApi/groups/$workspaceId/users" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body $body -UseBasicParsing -ErrorAction Stop
  Log "Add user response: $($resp.StatusCode)"
} catch {
  $msg = $_.Exception.Message
  # Try to read response body for more detail
  $detail = $null
  try { $detail = $_.ErrorDetails.Message } catch {}
  if (-not $detail) {
    try { $respStream = $_.Exception.Response.GetResponseStream(); $sr = New-Object System.IO.StreamReader($respStream); $detail = $sr.ReadToEnd() } catch {}
  }
  Fail "Failed adding principal to workspace: $msg :: $detail"
}

Log 'Workspace access grant complete.'
exit 0
