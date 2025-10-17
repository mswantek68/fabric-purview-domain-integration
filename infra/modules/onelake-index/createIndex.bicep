// ==========================================
// Create OneLake AI Search Index Module
// ==========================================
// Creates the search index with schema for OneLake documents
// The index defines the structure of searchable document fields

@description('Name of the AI Search service')
param aiSearchName string

@description('Resource group containing the AI Search service')
param aiSearchResourceGroup string

@description('Subscription ID containing the AI Search service')
param aiSearchSubscriptionId string

@description('Name of the search index to create')
param indexName string = 'onelake-documents-index'

@description('Name of the Fabric workspace (for deriving index name)')
param workspaceName string = ''

@description('Name of the Fabric domain (for deriving index name)')
param domainName string = ''



@description('User-assigned managed identity ID for authentication')
param managedIdentityId string

@description('Location for the deployment script')
param location string = resourceGroup().location

@description('Current timestamp for forcing re-execution')
param timestamp string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

// Deployment script to create AI Search index
resource createIndexScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'createOneLakeIndexScript'
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
        name: 'FABRIC_WORKSPACE_NAME'
        value: workspaceName
      }
      {
        name: 'FABRIC_DOMAIN_NAME'
        value: domainName
      }
    ]
    scriptContent: loadTextContent('../../../scripts/OneLakeIndex/03_create_onelake_index.ps1')
    cleanupPreference: 'OnSuccess'
  }
}

@description('Result of index creation')
output indexResult object = createIndexScript.properties.outputs

@description('Name of the created index')
output indexName string = createIndexScript.properties.outputs.indexName
