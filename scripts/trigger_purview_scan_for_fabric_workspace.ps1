<#
.Purpose
  Create/Update a Purview scan for a Fabric datasource scoped to a Fabric workspace and trigger a run.
.Notes
  This is a PowerShell translation of the original bash script.
  - Requires Azure CLI (az) available on PATH and logged in.
  - Tokens are acquired via az; API calls use Invoke-RestMethod/Invoke-WebRequest.
  - Provide Purview account via $env:PURVIEW_ACCOUNT_NAME or azd env.
  - Pass workspace id as first parameter or set environment variable FABRIC_WORKSPACE_ID.
#>

[CmdletBinding()]
param(
  [Parameter(Position=0, Mandatory=$false)]
  [string]$WorkspaceId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[purview-scan] $m" }
function Warn([string]$m){ Write-Warning "[purview-scan] $m" }
function Fail([string]$m){ Write-Error "[purview-scan] $m"; exit 1 }

# Resolve Purview account name
$PurviewAccountName = $env:PURVIEW_ACCOUNT_NAME
if (-not $PurviewAccountName) {
  try {
    # Try azd env if available
    $azdOut = & azd env get-value purviewAccountName 2>$null
    if ($LASTEXITCODE -eq 0 -and $azdOut) { $PurviewAccountName = $azdOut.Trim() }
  } catch { }
}
if (-not $PurviewAccountName) { Fail "purviewAccountName not found in env or azd env. Set PURVIEW_ACCOUNT_NAME." }

# Determine workspace id
if (-not $WorkspaceId) { $WorkspaceId = $env:FABRIC_WORKSPACE_ID }
if (-not $WorkspaceId) {
  # Try to load /tmp/fabric_workspace.env if present
  if (Test-Path "/tmp/fabric_workspace.env") {
    Get-Content "/tmp/fabric_workspace.env" | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $WorkspaceId = $Matches[1].Trim() }
    }
  }
}
if (-not $WorkspaceId) { Fail "Fabric workspace id not provided as parameter and not found in /tmp/fabric_workspace.env." }

# Acquire Purview token
Log "Acquiring Purview access token..."
try {
  $purviewToken = & az account get-access-token --resource https://purview.azure.net --query accessToken -o tsv 2>$null
  if (-not $purviewToken) { $purviewToken = & az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv 2>$null }
} catch { $purviewToken = $null }
if (-not $purviewToken) { Fail "Failed to acquire Purview access token" }

$endpoint = "https://$PurviewAccountName.purview.azure.com"
$scanName = "scan-workspace-$WorkspaceId"

Log "Creating/Updating scan '$scanName' for datasource 'Fabric' targeting workspace '$WorkspaceId'"

# Build payload
$payload = [PSCustomObject]@{
  properties = [PSCustomObject]@{
    includePersonalWorkspaces = $false
    scanScope = [PSCustomObject]@{
      type = 'PowerBIScanScope'
      workspaces = @(
        [PSCustomObject]@{ id = $WorkspaceId }
      )
    }
  }
  kind = 'PowerBIMsi'
}

$bodyJson = $payload | ConvertTo-Json -Depth 10

# Create or update scan
$createUrl = "$endpoint/scan/datasources/Fabric/scans/$scanName?api-version=2022-07-01-preview"
try {
  $resp = Invoke-WebRequest -Uri $createUrl -Method Put -Headers @{ Authorization = "Bearer $purviewToken"; 'Content-Type' = 'application/json' } -Body $bodyJson -UseBasicParsing -ErrorAction Stop
  $code = $resp.StatusCode.Value__
  $respBody = $resp.Content
} catch [System.Net.WebException] {
  $resp = $_.Exception.Response
  if ($resp) {
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $respBody = $reader.ReadToEnd()
    $code = $resp.StatusCode.value__
  } else {
    Fail "Scan create/update failed: $_"
  }
}

if ($code -ge 200 -and $code -lt 300) { Log "Scan definition created/updated (HTTP $code)" } else { Warn "Scan create/update failed (HTTP $code): $respBody"; Fail "Could not create/update scan" }

# Trigger a run
$runUrl = "$endpoint/scan/datasources/Fabric/scans/$scanName/run?api-version=2022-07-01-preview"
try {
  $runResp = Invoke-WebRequest -Uri $runUrl -Method Post -Headers @{ Authorization = "Bearer $purviewToken"; 'Content-Type' = 'application/json' } -Body '{}' -UseBasicParsing -ErrorAction Stop
  $runBody = $runResp.Content
  $runCode = $runResp.StatusCode.Value__
} catch [System.Net.WebException] {
  $resp = $_.Exception.Response
  if ($resp) { $reader = New-Object System.IO.StreamReader($resp.GetResponseStream()); $runBody = $reader.ReadToEnd(); $runCode = $resp.StatusCode.value__ } else { Fail "Scan run request failed: $_" }
}

if ($runCode -ne 200 -and $runCode -ne 202) { Write-Output $runBody; Fail "Scan run request failed (HTTP $runCode)" }

# Try to extract run id
try { $runJson = $runBody | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $runJson = $null }
$runId = $null
if ($runJson) {
  if ($runJson.PSObject.Properties.Name -contains 'runId') { $runId = $runJson.runId }
  elseif ($runJson.PSObject.Properties.Name -contains 'id') { $runId = $runJson.id }
}

if (-not $runId) {
  Log "Scan run invoked but no run id returned. Monitor the run in Purview portal or inspect the response:" 
  Write-Output $runBody
  exit 0
}

Log "Scan run started: $runId — polling status..."

while ($true) {
  Start-Sleep -Seconds 5
  $statusUrl = "$endpoint/scan/datasources/Fabric/scans/$scanName/runs/$runId?api-version=2022-07-01-preview"
  try {
    $sjson = Invoke-RestMethod -Uri $statusUrl -Headers @{ Authorization = "Bearer $purviewToken" } -Method Get -ErrorAction Stop
  } catch {
    Warn "Failed to poll run status: $_"; continue
  }
  $status = $null
  if ($null -ne $sjson) {
    if ($sjson.PSObject.Properties.Name -contains 'status') { $status = $sjson.status }
    elseif ($sjson.PSObject.Properties.Name -contains 'runStatus') { $status = $sjson.runStatus }
  }
  Log "Status: $status"
  if ($status -in @('Succeeded','Failed','Cancelled')) {
    Log "Scan finished with status: $status"
    $sjson | ConvertTo-Json -Depth 10 | Out-File -FilePath "/tmp/scan_run_$runId.json" -Encoding UTF8
    break
  }
}

Log "Done. Run output saved to /tmp/scan_run_$runId.json"
exit 0
