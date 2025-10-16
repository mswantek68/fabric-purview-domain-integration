@description('Connects a Fabric workspace to Azure Log Analytics (placeholder) using deployment script')
param workspaceName string
param workspaceId string
param logAnalyticsWorkspaceId string = ''
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

@description('Managed Identity for deployment script execution')
param userAssignedIdentityId string

@description('Name of the shared storage account for deployment scripts')
param storageAccountName string

// Generate unique names for deployment script resources
var deploymentScriptName = 'connect-log-analytics-${uniqueString(resourceGroup().id, workspaceId)}'

// Deployment script to connect Log Analytics
resource connectLogAnalyticsDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    storageAccountSettings: {
      storageAccountName: storageAccountName
    }
    environmentVariables: [
      {
        name: 'FABRIC_WORKSPACE_NAME'
        value: workspaceName
      }
      {
        name: 'WORKSPACE_ID'
        value: workspaceId
      }
      {
        name: 'LOG_ANALYTICS_WORKSPACE_ID'
        value: logAnalyticsWorkspaceId
      }
    ]
    scriptContent: '''
# Connect Fabric Workspace to Log Analytics (Placeholder)
param(
  [string]$WorkspaceName = $env:FABRIC_WORKSPACE_NAME,
  [string]$WorkspaceId = $env:WORKSPACE_ID,
  [string]$LogAnalyticsWorkspaceId = $env:LOG_ANALYTICS_WORKSPACE_ID
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { 
  Write-Host "[fabric-loganalytics] $m" 
  Write-Output "[fabric-loganalytics] $m"
}

function Warn([string]$m) { 
  Write-Warning "[fabric-loganalytics] $m"
  Write-Output "[WARNING] $m"
}

if (-not $WorkspaceName) {
  Warn 'No FABRIC_WORKSPACE_NAME determined; skipping Log Analytics linkage.'
  $DeploymentScriptOutputs = @{
    connected = $false
    message = 'No workspace name provided'
  }
  return
}

if (-not $LogAnalyticsWorkspaceId) {
  Warn "LOG_ANALYTICS_WORKSPACE_ID not provided; skipping."
  $DeploymentScriptOutputs = @{
    connected = $false
    message = 'No Log Analytics workspace ID provided'
  }
  return
}

# Acquire token
try { 
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
  if (-not $accessToken) { throw "No token returned" }
} catch { 
  Warn 'Cannot acquire token; skip LA linkage.'
  $DeploymentScriptOutputs = @{
    connected = $false
    message = 'Failed to acquire token'
  }
  return
}

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'

# Resolve workspace ID if not provided
if (-not $WorkspaceId) {
  try {
    $groups = Invoke-RestMethod -Uri "$apiRoot/groups?%24top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    $workspace = $groups.value | Where-Object { $_.name -eq $WorkspaceName }
    if ($workspace) { $WorkspaceId = $workspace.id }
  } catch {
    Warn "Unable to resolve workspace ID for '$WorkspaceName'; skipping."
    $DeploymentScriptOutputs = @{
      connected = $false
      message = 'Unable to resolve workspace ID'
    }
    return
  }
}

if (-not $WorkspaceId) {
  Warn "Unable to resolve workspace ID for '$WorkspaceName'; skipping."
  $DeploymentScriptOutputs = @{
    connected = $false
    message = 'Unable to resolve workspace ID'
  }
  return
}

Log "(PLACEHOLDER) Would link Fabric workspace $WorkspaceName ($WorkspaceId) to Log Analytics workspace $LogAnalyticsWorkspaceId"
Log "No public API yet; skipping actual connection."

# Set outputs for Bicep
$DeploymentScriptOutputs = @{
  connected = $false
  message = 'Placeholder - no public API available yet'
  workspaceId = $WorkspaceId
  logAnalyticsWorkspaceId = $LogAnalyticsWorkspaceId
}
    '''
  }
}

// Outputs
output connected bool = connectLogAnalyticsDeploymentScript.properties.outputs.connected
output message string = connectLogAnalyticsDeploymentScript.properties.outputs.message
