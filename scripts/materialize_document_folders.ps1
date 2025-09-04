<#!
.SYNOPSIS
  Create (materialize) document folders in a Fabric Lakehouse OneLake Files area.
.DESCRIPTION
  OneLake folders appear when a file or directory is created at that path. This script calls the OneLake DFS API
  to explicitly create the directories so they are visible before any files are uploaded.
.PARAMETER WorkspaceId
  Fabric workspace ID (GUID).
.PARAMETER LakehouseName
  Lakehouse display name (e.g., 'bronze'). If a GUID is provided, it's treated as the Lakehouse item ID.
.PARAMETER Folders
  Relative OneLake folders to materialize under the Lakehouse (default set includes Files/documents/*).
#>
[CmdletBinding()]
param(
  [string]$WorkspaceId,
  [string]$LakehouseName,
  [string[]]$Folders = @(
    'Files/documents',
    'Files/documents/contracts',
    'Files/documents/reports',
    'Files/documents/policies',
    'Files/documents/manuals'
  )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[onelake-folders] $m" }
function Warn([string]$m){ Write-Warning "[onelake-folders] $m" }
function Fail([string]$m){ Write-Error "[onelake-folders] $m"; exit 1 }

# Fallbacks for workspace and lakehouse
if (-not $WorkspaceId -or -not $LakehouseName) {
  if (Test-Path '/tmp/fabric_workspace.env') {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
      if (-not $WorkspaceId -and ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$')) { $WorkspaceId = $Matches[1].Trim() }
      if (-not $LakehouseName -and ($_ -match '^DOCUMENT_LAKEHOUSE_NAME=(.+)$')) { $LakehouseName = $Matches[1].Trim() }
    }
  }
}
if (-not $LakehouseName) {
  # Try azd outputs for document lakehouse name
  if (Test-Path '/tmp/azd-outputs.json') {
    try {
      $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
      if ($outputs.documentLakehouseName.value) { $LakehouseName = $outputs.documentLakehouseName.value }
    } catch { }
  }
}
if (-not $LakehouseName) { $LakehouseName = 'bronze' }
if (-not $WorkspaceId) { Fail 'WorkspaceId is required (not found in environment).'}

# Resolve Lakehouse ID when a name is provided
$lakehouseId = $LakehouseName
if ($LakehouseName -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
  try {
    $fabricToken = & az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
    if (-not $fabricToken) { Fail 'Could not retrieve Fabric API access token' }
    $fabricHeaders = @{ 'Authorization' = "Bearer $fabricToken"; 'Content-Type' = 'application/json' }
    $resp = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/lakehouses" -Headers $fabricHeaders -Method Get
    $item = $resp.value | Where-Object { $_.displayName -ieq $LakehouseName } | Select-Object -First 1
    if (-not $item) { Fail "Lakehouse '$LakehouseName' not found in workspace $WorkspaceId" }
    $lakehouseId = $item.id
  } catch {
    Fail "Failed to resolve lakehouse id: $($_.Exception.Message)"
  }
}

# Acquire token for OneLake DFS (Data Lake Gen2) API
try { $dfsToken = & az account get-access-token --resource https://storage.azure.com --query accessToken -o tsv } catch { $dfsToken = $null }
if (-not $dfsToken) { Fail 'Cannot acquire token for OneLake DFS API (resource https://storage.azure.com)' }

$base = "https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$lakehouseId"
$commonHeaders = @{ 
  'Authorization' = "Bearer $dfsToken"
  'x-ms-version' = '2023-11-03'
  'x-ms-date' = (Get-Date -Format r)
}

$created=0; $exists=0; $failed=0
foreach ($folder in $Folders) {
  $uri = "$base/$folder" + "`?resource=directory"
  # Refresh date header per request
  $headers = $commonHeaders.Clone()
  $headers['x-ms-date'] = (Get-Date -Format r)
  $headers['Content-Length'] = '0'
  Log "Creating directory: $folder"
  try {
    $resp = Invoke-WebRequest -Uri $uri -Method Put -Headers $headers -UseBasicParsing -ErrorAction Stop
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) { $created++; Log "Created: $folder" }
    else { Warn "Unexpected status $($resp.StatusCode) for $folder" }
  } catch {
    # Try to detect if already exists (409)
    $status = $null
    try { $status = $_.Exception.Response.StatusCode.value__ } catch {}
    if ($status -eq 409) { $exists++; Log "Exists: $folder" }
    else { $failed++; Warn "Failed: $folder - $($_.Exception.Message)" }
  }
}

Log "Summary: created=$created exists=$exists failed=$failed"
