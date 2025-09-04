<#
.SYNOPSIS
  Create a placeholder file in a OneLake lakehouse folder to virtualize the folder for users.
.DESCRIPTION
  Attempts several Fabric REST API endpoints to create a small text file (README) inside the target OneLake folder.
  This helps make the folder visible in UIs and encourages users to upload documents there. The operation is
  best-effort and will log helpful hints if all attempts fail.
.PARAMETER WorkspaceId
  The Fabric workspace id
.PARAMETER LakehouseName
  The lakehouse name (e.g. bronze)
.PARAMETER FolderPath
  The folder path inside the lakehouse to virtualize (e.g. Files/documents/contracts)
.PARAMETER Content
  Optional content to upload (defaults to a short README)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$WorkspaceId,
  [Parameter(Mandatory=$true)][string]$LakehouseName,
  [Parameter(Mandatory=$true)][string]$FolderPath,
  [string]$Content
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[virtualize-onelake] $m" }
function Warn([string]$m){ Write-Warning "[virtualize-onelake] $m" }

if (-not $Content) {
  $Content = "This is a placeholder file to virtualize the folder: $FolderPath`nUpload documents to this folder to enable OneLake indexing.`n"
}

try {
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
  if (-not $accessToken) { throw "Could not acquire Fabric API access token" }
} catch {
  Fail "Failed to get Fabric API token: $_"
}

$apiRoot = 'https://api.fabric.microsoft.com/v1'
$uploadName = "_placeholder_README.txt"

$attempts = $null

# Candidate endpoints to try - best-effort
$encodedFolder = [System.Uri]::EscapeDataString($FolderPath.Trim('/'))
$candidates = @(
  "$apiRoot/workspaces/$WorkspaceId/lakehouses/$LakehouseName/files/$encodedFolder/$uploadName",
  "$apiRoot/workspaces/$WorkspaceId/files/$encodedFolder/$uploadName",
  "$apiRoot/workspaces/$WorkspaceId/lakehouses/$LakehouseName/items?path=$encodedFolder/$uploadName",
  "$apiRoot/workspaces/$WorkspaceId/items?path=$encodedFolder/$uploadName"
)

$success = $false
foreach ($candidate in $candidates) {
  try {
    Log "Attempting to upload placeholder to: $candidate"
    Invoke-RestMethod -Uri $candidate -Method Put -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'text/plain' } -Body $Content -ErrorAction Stop | Out-Null
    Log "Uploaded placeholder to: $candidate"
    $success = $true
    break
  } catch {
    Warn ("Attempt failed for $candidate: " + $_.Exception.Message)
  }
}

if (-not $success) {
  Warn "All automatic attempts failed. You can create a small file in the target folder using the Fabric UI or by uploading via the OneLake file picker."
  Log "Suggested manual steps:"
  Log "  1. Open the Fabric workspace UI and navigate to the '$LakehouseName' lakehouse"
  Log "  2. Create the folder path '$FolderPath' if not present"
  Log "  3. Upload a small text file (name it _placeholder_README.txt) into the folder"
  Log "  4. Re-run the indexer script to ensure files are picked up"
} else {
  Log "Virtualization attempt succeeded — folder should now be visible to users"
}

exit 0
