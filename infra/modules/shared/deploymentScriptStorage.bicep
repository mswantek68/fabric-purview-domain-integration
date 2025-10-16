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

// Deploy storage account using Azure Verified Module (AVM)
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
    allowSharedKeyAccess: true  // Required for deployment scripts
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
  }
}

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.outputs.resourceId

@description('The name of the storage account')
output storageAccountName string = storageAccount.outputs.name

@description('The primary blob endpoint')
output blobEndpoint string = storageAccount.outputs.primaryBlobEndpoint

@description('The primary access key for the storage account')
output storageAccountKey string = storageAccount.outputs.primaryAccessKey
