// ==========================================
// Create OneLake AI Search Skillsets Module
// ==========================================
// Creates the necessary skillsets for processing OneLake documents
// Skillsets define how documents are processed (text extraction, chunking, etc.)

@description('Name of the AI Search service')
param aiSearchName string

@description('Resource group containing the AI Search service')
param aiSearchResourceGroup string

@description('Subscription ID containing the AI Search service')
param aiSearchSubscriptionId string



@description('User-assigned managed identity ID for authentication')
param managedIdentityId string

@description('Location for the deployment script')
param location string = resourceGroup().location

@description('Current timestamp for forcing re-execution')
param timestamp string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

// Deployment script to create AI Search skillsets
resource createSkillsetsScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'createOneLakeSkillsetsScript'
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
    ]
    scriptContent: loadTextContent('../../../scripts/OneLakeIndex/02_create_onelake_skillsets.ps1')
    cleanupPreference: 'OnSuccess'
  }
}

@description('Result of skillset creation')
output skillsetResult object = createSkillsetsScript.properties.outputs

@description('Name of the created skillset')
output skillsetName string = 'onelake-textonly-skillset'
