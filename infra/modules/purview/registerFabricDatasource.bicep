@description('Registers Fabric/PowerBI as a datasource in Purview using deployment script')
param purviewAccountName string
param collectionName string
param workspaceId string
param workspaceName string
param tenantId string = subscription().tenantId
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

@description('Managed Identity for deployment script execution')
param userAssignedIdentityId string

@description('Name of the shared storage account for deployment scripts')
param storageAccountName string

// Generate unique names for deployment script resources
var deploymentScriptName = 'register-fabric-datasource-${uniqueString(resourceGroup().id, workspaceId)}'

// Deployment script to register Fabric datasource
resource registerFabricDatasourceDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
        name: 'PURVIEW_ACCOUNT_NAME'
        value: purviewAccountName
      }
      {
        name: 'COLLECTION_NAME'
        value: collectionName
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
        name: 'TENANT_ID'
        value: tenantId
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'SUBSCRIPTION_ID'
        value: subscription().subscriptionId
      }
    ]
    scriptContent: '''
# Register Fabric Datasource in Purview
param(
  [string]$PurviewAccountName = $env:PURVIEW_ACCOUNT_NAME,
  [string]$CollectionName = $env:COLLECTION_NAME,
  [string]$WorkspaceId = $env:WORKSPACE_ID,
  [string]$WorkspaceName = $env:WORKSPACE_NAME,
  [string]$TenantId = $env:TENANT_ID,
  [string]$ResourceGroup = $env:RESOURCE_GROUP,
  [string]$SubscriptionId = $env:SUBSCRIPTION_ID
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { 
  Write-Host "[register-datasource] $m" 
  Write-Output "[register-datasource] $m"
}

function Warn([string]$m) { 
  Write-Warning "[register-datasource] $m"
  Write-Output "[WARNING] $m"
}

function Fail([string]$m) { 
  Write-Error "[register-datasource] $m"
  throw $m
}

if (-not $PurviewAccountName) { Fail 'PURVIEW_ACCOUNT_NAME is required' }
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
  Fail "Failed to acquire Purview access token: $($_.Exception.Message)"
}

Log "Checking for existing Fabric (PowerBI) datasources..."

try {
  $existing = Invoke-RestMethod -Uri "$endpoint/scan/datasources?api-version=2022-07-01-preview" -Headers @{ Authorization = "Bearer $purviewToken" } -Method Get -ErrorAction Stop
} catch { 
  $existing = @{ value = @() } 
}

# Look for workspace-specific datasource first
$workspaceSpecificDatasourceName = "Fabric-Workspace-$WorkspaceId"
$fabricDatasourceName = $null

# Check if we already have a workspace-specific datasource
if ($existing.value) {
  $workspaceSpecific = $existing.value | Where-Object { $_.name -eq $workspaceSpecificDatasourceName }
  if ($workspaceSpecific) {
    $fabricDatasourceName = $workspaceSpecificDatasourceName
    Log "Found existing workspace-specific Fabric datasource: $fabricDatasourceName"
  } else {
    # Look for any PowerBI datasource as fallback
    foreach ($ds in $existing.value) {
      if ($ds.kind -eq 'PowerBI') {
        $isRootLevel = (-not $ds.properties.collection) -or 
                       ($null -eq $ds.properties.collection) -or 
                       ($ds.properties.collection.referenceName -eq $PurviewAccountName)
        if ($isRootLevel) { 
          $fabricDatasourceName = $ds.name
          Log "Found existing Fabric datasource at root level: $fabricDatasourceName"
          break 
        }
      }
    }
  }
}

if ($fabricDatasourceName) {
  Log "Found existing Fabric datasource: $fabricDatasourceName"
} else {
  # No suitable datasource found, create a workspace-specific one
  Log "No existing workspace-specific datasource found - creating new workspace-specific Fabric datasource"
  $fabricDatasourceName = $workspaceSpecificDatasourceName
  
  $datasourceBody = @{
    name = $fabricDatasourceName
    kind = "PowerBI"
    properties = @{
      tenant = $TenantId
      collection = @{
        referenceName = $CollectionName
        type = "CollectionReference"
      }
      resourceGroup = $ResourceGroup
      subscriptionId = $SubscriptionId
      workspace = @{
        id = $WorkspaceId
        name = $WorkspaceName
      }
    }
  } | ConvertTo-Json -Depth 10

  try {
    $resp = Invoke-WebRequest -Uri "$endpoint/scan/datasources/${fabricDatasourceName}?api-version=2022-07-01-preview" -Headers @{ Authorization = "Bearer $purviewToken"; 'Content-Type' = 'application/json' } -Method Put -Body $datasourceBody -UseBasicParsing -ErrorAction Stop
    
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
      Log "Workspace-specific Fabric datasource '$fabricDatasourceName' registered successfully (HTTP $($resp.StatusCode))"
    } else {
      Warn "Unexpected HTTP status: $($resp.StatusCode)"
      throw "HTTP $($resp.StatusCode)"
    }
  } catch {
    # Fallback: try creating simplified workspace-specific datasource
    Log "Failed to create enhanced workspace datasource, trying simplified approach..."
    $simpleDatasourceBody = @{
      name = $fabricDatasourceName
      kind = "PowerBI"
      properties = @{
        tenant = $TenantId
        collection = @{
          referenceName = $CollectionName
          type = "CollectionReference"  
        }
      }
    } | ConvertTo-Json -Depth 5
    
    try {
      $resp = Invoke-WebRequest -Uri "$endpoint/scan/datasources/${fabricDatasourceName}?api-version=2022-07-01-preview" -Headers @{ Authorization = "Bearer $purviewToken"; 'Content-Type' = 'application/json' } -Method Put -Body $simpleDatasourceBody -UseBasicParsing -ErrorAction Stop
      
      if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
        Log "Simplified workspace Fabric datasource '$fabricDatasourceName' registered successfully (HTTP $($resp.StatusCode))"
      } else {
        Fail "Failed to register workspace-specific Fabric datasource: HTTP $($resp.StatusCode)"
      }
    } catch {
      Fail "Failed to register workspace-specific Fabric datasource: $_"
    }
  }
}

Log "Fabric datasource registration completed: $fabricDatasourceName"
Log "Collection: $CollectionName"

# Set outputs for Bicep
$DeploymentScriptOutputs = @{
  datasourceName = $fabricDatasourceName
  collectionId = $CollectionName
}
    '''
  }
}

// Outputs
output datasourceName string = registerFabricDatasourceDeploymentScript.properties.outputs.datasourceName
output collectionId string = registerFabricDatasourceDeploymentScript.properties.outputs.collectionId
