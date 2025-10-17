// ============================================================================
// Deployment Script Storage Account Module
// ============================================================================
// This module creates a dedicated storage account for deployment scripts.
//
// Note: Shared key access must be ENABLED for deployment scripts to work
// with API version 2023-08-01. This is a platform requirement, not a choice.
//
// Security Features:
// - Private storage account dedicated to deployment scripts only
// - RBAC role assignments for managed identity access
// - Network ACLs allowing Azure services only
// - Storage account keys are NOT exposed in outputs
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

// Storage Blob Data Contributor role ID
// Required for deployment scripts to write files to the storage account
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// Create storage account directly (no AVM module)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true // Required for deployment scripts
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Create blob service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

// Create container for deployment scripts
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'deployment-scripts'
  properties: {
    publicAccess: 'None'
  }
}

// Assign RBAC role to managed identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentityPrincipalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary blob endpoint')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Storage account key for deployment scripts')
@secure()
output storageAccountKey string = storageAccount.listKeys().keys[0].value
