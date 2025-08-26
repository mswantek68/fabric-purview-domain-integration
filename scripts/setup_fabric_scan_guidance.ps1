<#
.SYNOPSIS
  Provide guidance and configuration details to create a Purview scan for Fabric
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[fabric-scan-guide] $m" }
function Warn([string]$m){ Write-Warning "[fabric-scan-guide] $m" }

$purviewAccount = $null; $workspaceName = $null; $collectionName = $null
try { $purviewAccount = & azd env get-value purviewAccountName 2>$null } catch {}
try { $workspaceName = & azd env get-value desiredFabricWorkspaceName 2>$null } catch {}
try { $collectionName = & azd env get-value desiredFabricDomainName 2>$null } catch {}

# Load /tmp outputs if present
if (-not $collectionName -and (Test-Path '/tmp/purview_collection.env')) { Get-Content '/tmp/purview_collection.env' | ForEach-Object { if ($_ -match '^PURVIEW_COLLECTION_NAME=(.+)$') { $collectionName = $Matches[1] } } }
if (-not $purviewAccount -and (Test-Path '/tmp/fabric_datasource.env')) { Get-Content '/tmp/fabric_datasource.env' | ForEach-Object { if ($_ -match '^PURVIEW_COLLECTION_NAME=(.+)$') { $collectionName = $Matches[1] } } }

if (-not $purviewAccount -or -not $workspaceName) { Fail 'Missing required env values: purviewAccountName, desiredFabricWorkspaceName' }

Log "Providing Fabric scan setup guidance"
Log "  • Account: $purviewAccount"
Log "  • Datasource: Fabric (or see /tmp/fabric_datasource.env)"
Log "  • Collection: $collectionName"
Log "  • Target Workspace: $workspaceName"

# Attempt to discover workspace id
$workspaceId = $env:WORKSPACE_ID
try {
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
  $groups = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  $match = $groups.value | Where-Object { $_.name -eq $workspaceName }
  if ($match) { $workspaceId = $match.id }
} catch { }

$scanName = "${collectionName}-fabric-scan"

# Compose guidance
$guidance = [PSCustomObject]@{
  scanName = $scanName
  datasourceName = 'Fabric'
  collectionId = $collectionName
  targetWorkspace = $workspaceName
  workspaceId = $workspaceId
  purviewAccount = $purviewAccount
}

$guidance | ConvertTo-Json -Depth 5 | Out-File -FilePath '/tmp/fabric_scan_config.json' -Encoding UTF8
Log "Scan configuration exported to /tmp/fabric_scan_config.json"
Log "Follow the guidance printed above or use the exported JSON to create the scan in Purview." 
exit 0
