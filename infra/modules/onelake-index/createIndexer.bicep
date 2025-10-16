// ==========================================
// Create OneLake AI Search Indexer Module
// ==========================================
// Creates and runs the indexer that processes OneLake documents
// The indexer pulls data from the data source and populates the search index

@description('Name of the AI Search service')
param aiSearchName string

@description('Resource group containing the AI Search service')
param aiSearchResourceGroup string

@description('Subscription ID containing the AI Search service')
param aiSearchSubscriptionId string

@description('Name of the target search index')
param indexName string = 'onelake-documents-index'

@description('Name of the data source')
param dataSourceName string = 'onelake-reports-datasource'

@description('Name of the skillset (optional)')
param skillsetName string = 'onelake-textonly-skillset'

@description('Name of the indexer to create')
param indexerName string = 'onelake-reports-indexer'

@description('Name of the Fabric workspace (for deriving names)')
param workspaceName string = ''

@description('Folder path to index')
param folderPath string = ''

@description('Name of the Fabric domain (for deriving names)')
param domainName string = ''

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

// Deployment script to create and run OneLake indexer
resource createIndexerScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'createOneLakeIndexerScript'
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
        name: 'indexName'
        value: indexName
      }
      {
        name: 'dataSourceName'
        value: dataSourceName
      }
      {
        name: 'skillsetName'
        value: skillsetName
      }
      {
        name: 'indexerName'
        value: indexerName
      }
      {
        name: 'FABRIC_WORKSPACE_NAME'
        value: workspaceName
      }
      {
        name: 'folderPath'
        value: folderPath
      }
      {
        name: 'FABRIC_DOMAIN_NAME'
        value: domainName
      }
    ]
    scriptContent: loadTextContent('../../../scripts/OneLakeIndex/05_create_onelake_indexer.ps1')
    cleanupPreference: 'OnSuccess'
  }
}

@description('Result of indexer creation')
output indexerResult object = createIndexerScript.properties.outputs

@description('Name of the created indexer')
output indexerName string = createIndexerScript.properties.outputs.indexerName

@description('Number of documents processed')
output documentsProcessed int = createIndexerScript.properties.outputs.itemsProcessed
