// ==========================================
// Shared Deployment Script Storage Account
// ==========================================
// This module deploys a single storage account that is shared
// by all deployment scripts in the infrastructure deployment.
// Using a shared storage account significantly reduces cost and complexity.

@description('Name of the storage account for deployment scripts')
param storageAccountName string

@description('Location for the storage account')
param location string = resourceGroup().location

@description('Tags to apply to the storage account')
param tags object = {}

// Deploy storage account using native Bicep resource
// Using native resource instead of AVM to ensure allowSharedKeyAccess is properly set
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
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
    allowSharedKeyAccess: true  // Required for deployment scripts
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Create container for deployment scripts
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'deployment-scripts'
  properties: {
    publicAccess: 'None'
  }
}

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary blob endpoint')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The primary access key for the storage account')
output storageAccountKey string = listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value
