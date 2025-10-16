@description('Triggers a Purview scan for a Fabric workspace using deployment script')
param purviewAccountName string
param datasourceName string
param workspaceId string
param workspaceName string
param collectionId string = ''
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

@description('Managed Identity for deployment script execution')
param userAssignedIdentityId string



// Generate unique names for deployment script resources
var deploymentScriptName = 'trigger-purview-scan-${uniqueString(resourceGroup().id, workspaceId)}'

// Deployment script to trigger Purview scan
resource triggerPurviewScanDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: deploymentScriptName
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    forceUpdateTag: utcValue
    retentionInterval: 'P1D'
    timeout: 'PT1H'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'PURVIEW_ACCOUNT_NAME'
        value: purviewAccountName
      }
      {
        name: 'DATASOURCE_NAME'
        value: datasourceName
      }
      {
        name: 'WORKSPACE_ID'
        value: workspaceId
      }
      {
        name: 'WORKSPACE_NAME'
        value: workspaceName
      }
      {
        name: 'COLLECTION_ID'
        value: collectionId
      }
    ]
    scriptContent: '''
# Trigger Purview Scan for Fabric Workspace
param(
  [string]$PurviewAccountName = $env:PURVIEW_ACCOUNT_NAME,
  [string]$DatasourceName = $env:DATASOURCE_NAME,
  [string]$WorkspaceId = $env:WORKSPACE_ID,
  [string]$WorkspaceName = $env:WORKSPACE_NAME,
  [string]$CollectionId = $env:COLLECTION_ID
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { 
  Write-Host "[purview-scan] $m" 
  Write-Output "[purview-scan] $m"
}

function Warn([string]$m) { 
  Write-Warning "[purview-scan] $m"
  Write-Output "[WARNING] $m"
}

function Fail([string]$m) { 
  Write-Error "[purview-scan] $m"
  throw $m
}

if (-not $PurviewAccountName) { Fail 'PURVIEW_ACCOUNT_NAME is required' }
if (-not $DatasourceName) { 
  Log "No Purview datasource registered. Skipping scan creation and run."
  $DeploymentScriptOutputs = @{
    scanCreated = $false
    scanTriggered = $false
    message = 'No datasource registered'
  }
  return
}
if (-not $WorkspaceId) { Fail 'WORKSPACE_ID is required' }

$endpoint = "https://$PurviewAccountName.purview.azure.com"

# Acquire Purview token
try {
  $purviewToken = & az account get-access-token --resource https://purview.azure.net --query accessToken -o tsv 2>$null
  if (-not $purviewToken) {
    $purviewToken = & az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv 2>$null
  }
  if (-not $purviewToken) { throw "No Purview token returned" }
} catch {
  Fail "Failed to acquire Purview access token"
}

$scanName = "scan-workspace-$WorkspaceId"

Log "Creating/Updating scan '$scanName' for datasource '$DatasourceName' targeting workspace '$WorkspaceId'"
if ($CollectionId) { Log "Assigning scan to collection: $CollectionId" }

# Build payload for workspace-scoped scan
$payload = [PSCustomObject]@{
  properties = [PSCustomObject]@{
    includePersonalWorkspaces = $false
    scanScope = [PSCustomObject]@{
      type = 'PowerBIScanScope'
      workspaces = @(
        [PSCustomObject]@{ 
          id = $WorkspaceId
        }
      )
    }
  }
  kind = 'PowerBIMsi'
}

# Add collection assignment if available
if ($CollectionId) {
  $payload.properties | Add-Member -MemberType NoteProperty -Name 'collection' -Value ([PSCustomObject]@{
    referenceName = $CollectionId
    type = 'CollectionReference'
  })
}

$bodyJson = $payload | ConvertTo-Json -Depth 10

# Create or update scan
$createUrl = "$endpoint/scan/datasources/$DatasourceName/scans/${scanName}?api-version=2022-07-01-preview"

try {
  $resp = Invoke-WebRequest -Uri $createUrl -Method Put -Headers @{ Authorization = "Bearer $purviewToken"; 'Content-Type' = 'application/json' } -Body $bodyJson -UseBasicParsing -ErrorAction Stop
  $code = $resp.StatusCode
} catch {
  if ($_.Exception.Response) {
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    $respBody = $reader.ReadToEnd()
    $code = $_.Exception.Response.StatusCode
    Fail "Scan create/update failed (HTTP $code): $respBody"
  } else {
    Fail "Scan create/update failed: $_"
  }
}

if ($code -ge 200 -and $code -lt 300) { 
  Log "Scan definition created/updated (HTTP $code)" 
} else { 
  Fail "Scan create/update failed (HTTP $code)"
}

# Trigger a run
$runUrl = "$endpoint/scan/datasources/$DatasourceName/scans/$scanName/run?api-version=2022-07-01-preview"

try {
  $runResp = Invoke-WebRequest -Uri $runUrl -Method Post -Headers @{ Authorization = "Bearer $purviewToken"; 'Content-Type' = 'application/json' } -Body '{}' -UseBasicParsing -ErrorAction Stop
  $runBody = $runResp.Content
  $runCode = $runResp.StatusCode
} catch {
  if ($_.Exception.Response) {
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    $runBody = $reader.ReadToEnd()
    $runCode = $_.Exception.Response.StatusCode
  } else {
    Fail "Scan run request failed: $_"
  }
}

if ($runCode -ne 200 -and $runCode -ne 202) {
  # Check if it's just an active run already existing
  if ($runBody -match "ScanHistory_ActiveRunExist" -or $runBody -match "already.*running") {
    Log "A scan is already running for this datasource. Skipping new scan trigger."
    $DeploymentScriptOutputs = @{
      scanCreated = $true
      scanTriggered = $false
      message = 'Scan already running'
    }
    return
  }
  Fail "Scan run request failed (HTTP $runCode): $runBody"
}

# Try to extract run id
try { 
  $runJson = $runBody | ConvertFrom-Json -ErrorAction SilentlyContinue 
} catch { 
  $runJson = $null 
}

$runId = $null
if ($runJson) {
  if ($runJson.PSObject.Properties.Name -contains 'runId') { 
    $runId = $runJson.runId 
  } elseif ($runJson.PSObject.Properties.Name -contains 'id') { 
    $runId = $runJson.id 
  }
}

if (-not $runId) {
  Log "Scan run invoked but no run id returned."
  $DeploymentScriptOutputs = @{
    scanCreated = $true
    scanTriggered = $true
    runId = ''
    status = 'Queued'
  }
  return
}

Log "Scan run started: $runId - polling status..."

$maxPolls = 60
$pollCount = 0

while ($pollCount -lt $maxPolls) {
  Start-Sleep -Seconds 10
  $pollCount++
  
  $statusUrl = "$endpoint/scan/datasources/$DatasourceName/scans/${scanName}/runs/${runId}?api-version=2022-07-01-preview"
  
  try {
    $sjson = Invoke-RestMethod -Uri $statusUrl -Headers @{ Authorization = "Bearer $purviewToken" } -Method Get -ErrorAction Stop
  } catch {
    Warn "Failed to poll run status: $_"
    continue
  }
  
  $status = $null
  if ($null -ne $sjson) {
    if ($sjson.PSObject.Properties.Name -contains 'status') { 
      $status = $sjson.status 
    } elseif ($sjson.PSObject.Properties.Name -contains 'runStatus') { 
      $status = $sjson.runStatus 
    }
  }
  
  Log "Status: $status (poll $pollCount/$maxPolls)"
  
  if ($status -in @('Succeeded','Failed','Cancelled')) {
    Log "Scan finished with status: $status"
    $DeploymentScriptOutputs = @{
      scanCreated = $true
      scanTriggered = $true
      runId = $runId
      status = $status
    }
    return
  }
}

Log "Scan still running after $maxPolls polls. Continuing..."
$DeploymentScriptOutputs = @{
  scanCreated = $true
  scanTriggered = $true
  runId = $runId
  status = 'Running'
}
    '''
  }
}

// Outputs
output scanCreated bool = triggerPurviewScanDeploymentScript.properties.outputs.scanCreated
output scanTriggered bool = triggerPurviewScanDeploymentScript.properties.outputs.scanTriggered
output runId string = triggerPurviewScanDeploymentScript.properties.outputs.?runId ?? ''
output status string = triggerPurviewScanDeploymentScript.properties.outputs.?status ?? 'Unknown'
