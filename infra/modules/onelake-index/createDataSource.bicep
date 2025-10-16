// ==========================================
// Create OneLake AI Search Data Source Module
// ==========================================
// Creates the OneLake data source for AI Search indexing
// This configures the connection to the Fabric lakehouse

@description('Name of the AI Search service')
param aiSearchName string

@description('Resource group containing the AI Search service')
param aiSearchResourceGroup string

@description('Subscription ID containing the AI Search service')
param aiSearchSubscriptionId string

@description('Fabric workspace ID')
param workspaceId string

@description('Fabric lakehouse ID')
param lakehouseId string

@description('Name of the data source to create')
param dataSourceName string = 'onelake-reports-datasource'

@description('Name of the Fabric workspace (for deriving datasource name)')
param workspaceName string = ''

@description('Query path within the lakehouse')
param queryPath string = 'Files/documents/reports'

@description('Name of the shared storage account for deployment scripts')
param storageAccountName string


@description('User-assigned managed identity ID for authentication')
param managedIdentityId string

@description('Location for the deployment script')
param location string = resourceGroup().location

@description('Current timestamp for forcing re-execution')
param timestamp string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

// Deployment script to create OneLake data source
resource createDataSourceScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'createOneLakeDataSourceScript'
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    retentionInterval: 'P1D'
    timeout: 'PT30M'
    forceUpdateTag: timestamp
    storageAccountSettings: {
      storageAccountKey: null
      storageAccountName: storageAccountName
    }
    environmentVariables: [
      {
        name: 'aiSearchName'
        value: aiSearchName
      }
      {
        name: 'aiSearchResourceGroup'
        value: aiSearchResourceGroup
      }
      {
        name: 'aiSearchSubscriptionId'
        value: aiSearchSubscriptionId
      }
      {
        name: 'FABRIC_WORKSPACE_ID'
        value: workspaceId
      }
      {
        name: 'FABRIC_LAKEHOUSE_ID'
        value: lakehouseId
      }
      {
        name: 'dataSourceName'
        value: dataSourceName
      }
      {
        name: 'FABRIC_WORKSPACE_NAME'
        value: workspaceName
      }
      {
        name: 'queryPath'
        value: queryPath
      }
    ]
    scriptContent: loadTextContent('../../../scripts/OneLakeIndex/04_create_onelake_datasource.ps1')
    cleanupPreference: 'OnSuccess'
  }
}

@description('Result of data source creation')
output dataSourceResult object = createDataSourceScript.properties.outputs

@description('Name of the created data source')
output dataSourceName string = createDataSourceScript.properties.outputs.dataSourceName
