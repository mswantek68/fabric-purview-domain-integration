<#
.SYNOPSIS
  Create bronze/silver/gold lakehouses in a Fabric workspace.
#>

[CmdletBinding()]
param(
  [string]$LakehouseNames = $env:LAKEHOUSE_NAMES,
  [string]$WorkspaceName = $env:FABRIC_WORKSPACE_NAME,
  [string]$WorkspaceId = $env:WORKSPACE_ID
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[fabric-lakehouses] $m" }
function Warn([string]$m){ Write-Warning "[fabric-lakehouses] $m" }

if (-not $LakehouseNames) { $LakehouseNames = 'bronze,silver,gold' }

# Resolve workspace id if needed
if (-not $WorkspaceId -and $WorkspaceName) {
  try {
    $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
    $apiRoot = 'https://api.fabric.microsoft.com/v1'
    $groups = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups?%24top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    $match = $groups.value | Where-Object { $_.name -eq $WorkspaceName }
    if ($match) { $WorkspaceId = $match.id }
  } catch { Warn 'Unable to resolve workspace id' }
}

if (-not $WorkspaceId) { Warn "No workspace id; skipping lakehouse creation."; exit 0 }

# Acquire token
try { $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv } catch { $accessToken = $null }
if (-not $accessToken) { Fail 'Cannot acquire Fabric API token; ensure az login' }

$apiRoot = 'https://api.fabric.microsoft.com/v1'

$names = $LakehouseNames -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$created=0; $skipped=0; $failed=0
foreach ($name in $names) {
  # Check existence
  try {
    $existing = Invoke-RestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/items?type=Lakehouse&%24top=200" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    $match = $existing.value | Where-Object { $_.displayName -eq $name -or $_.name -eq $name }
    if ($match) { Log "Lakehouse exists: $name ($($match.id))"; $skipped++; continue }
  } catch { }

  Log "Creating lakehouse: $name"
  $payload = @{ displayName = $name; type = 'Lakehouse' } | ConvertTo-Json -Depth 6
  try {
    $resp = Invoke-WebRequest -Uri "$apiRoot/workspaces/$WorkspaceId/items" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body $payload -UseBasicParsing -ErrorAction Stop
    $content = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    Log "Created lakehouse $name ($($content.id))"
    $created++
  } catch {
    Warn "Failed to create $name: $_"; $failed++
  }
  Start-Sleep -Seconds 1
}

Log "Lakehouse creation summary: created=$created skipped=$skipped failed=$failed"
exit 0
