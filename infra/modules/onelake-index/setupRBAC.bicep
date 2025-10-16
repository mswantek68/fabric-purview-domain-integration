// ==========================================
// OneLake AI Search RBAC Setup Module
// ==========================================
// Sets up managed identity permissions for OneLake indexing
// This module configures RBAC roles for AI Search to access OneLake and AI Foundry

@description('Name of the AI Search service')
param aiSearchName string

@description('Resource group containing the AI Search service')
param aiSearchResourceGroup string

@description('Subscription ID containing the AI Search service')
param aiSearchSubscriptionId string

@description('Name of the AI Foundry workspace')
param aiFoundryName string

@description('Name of the Fabric workspace')
param fabricWorkspaceName string

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

// Deployment script to configure RBAC permissions
resource setupRBACScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'setupOneLakeRBACScript'
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
        name: 'AI_SEARCH_NAME'
        value: aiSearchName
      }
      {
        name: 'AI_SEARCH_RESOURCE_GROUP'
        value: aiSearchResourceGroup
      }
      {
        name: 'AI_SEARCH_SUBSCRIPTION_ID'
        value: aiSearchSubscriptionId
      }
      {
        name: 'AI_FOUNDRY_NAME'
        value: aiFoundryName
      }
      {
        name: 'FABRIC_WORKSPACE_NAME'
        value: fabricWorkspaceName
      }
    ]
    scriptContent: loadTextContent('../../../scripts/OneLakeIndex/01_setup_rbac.ps1')
    cleanupPreference: 'OnSuccess'
  }
}

@description('Result of the RBAC setup')
output setupResult object = setupRBACScript.properties.outputs

@description('Principal ID configured with RBAC permissions')
output principalId string = setupRBACScript.properties.outputs.principalId
