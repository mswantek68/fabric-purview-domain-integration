// ============================================================================
// Deployment Script Storage Account Module (Secure - Managed Identity)
// ============================================================================
// This module creates a dedicated storage account for deployment scripts
// using Azure Verified Modules (AVM) with WAF-compliant security settings.
//
// Security Features:
// - Shared key access DISABLED (follows WAF best practices)
// - Managed identity authentication ONLY
// - RBAC-based access control
//
// All deployment scripts share this single storage account to minimize
// costs and simplify management.
//
// Cost: ~$0.02/month (Standard LRS)
// ============================================================================

@description('Name of the storage account')
param storageAccountName string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Tags to apply to resources')
param tags object = {}

@description('Principal ID of the managed identity that will access this storage account')
param managedIdentityPrincipalId string

// Storage File Data Privileged Contributor role ID
// Required for deployment scripts to write files to the storage account
var storageFileDataPrivilegedContributorRoleId = '69566ab7-960f-475b-8e7c-b3118f30c6bd'

// Deploy storage account using Azure Verified Module (AVM)
// WAF-compliant: allowSharedKeyAccess defaults to false for security
module storageAccount 'br/public:avm/res/storage/storage-account:0.27.1' = {
  name: 'deploymentScriptStorage'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    // allowSharedKeyAccess: false (AVM default - WAF compliant)
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    blobServices: {
      containers: [
        {
          name: 'deployment-scripts'
          publicAccess: 'None'
        }
      ]
    }
    // RBAC: Grant managed identity access to write deployment script files
    roleAssignments: [
      {
        principalId: managedIdentityPrincipalId
        roleDefinitionIdOrName: storageFileDataPrivilegedContributorRoleId
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.outputs.resourceId

@description('The name of the storage account')
output storageAccountName string = storageAccount.outputs.name

@description('The primary blob endpoint')
output blobEndpoint string = storageAccount.outputs.primaryBlobEndpoint
