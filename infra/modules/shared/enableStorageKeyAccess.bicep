@description('Enables shared key access on a storage account using Azure CLI')
param storageAccountName string
param storageAccountResourceGroup string = resourceGroup().name
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Managed Identity for deployment script execution')
param userAssignedIdentityId string

@description('Tags to apply to resources')
param tags object = {}

var deploymentScriptName = 'enable-storage-key-access-${uniqueString(resourceGroup().id, storageAccountName)}'

// This deployment script uses managed identity to call Azure CLI
// and enable shared key access on the storage account
resource enableKeyAccessScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: deploymentScriptName
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    azCliVersion: '2.59.0'
    forceUpdateTag: utcValue
    retentionInterval: 'P1D'
    timeout: 'PT10M'
    cleanupPreference: 'OnSuccess'
    // NO storageAccountSettings - this script doesn't need storage!
    // It just calls Azure CLI to update the storage account property
    environmentVariables: [
      {
        name: 'STORAGE_ACCOUNT_NAME'
        value: storageAccountName
      }
      {
        name: 'RESOURCE_GROUP'
        value: storageAccountResourceGroup
      }
    ]
    scriptContent: '''
#!/bin/bash
set -e

echo "Enabling shared key access on storage account: $STORAGE_ACCOUNT_NAME"

# Enable shared key access
az storage account update \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --allow-shared-key-access true

# Verify it worked
RESULT=$(az storage account show \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "allowSharedKeyAccess" -o tsv)

echo "Result: allowSharedKeyAccess = $RESULT"

if [ "$RESULT" != "true" ]; then
  echo "ERROR: Failed to enable shared key access"
  exit 1
fi

echo "Successfully enabled shared key access"
'''
  }
}

output scriptStatus string = enableKeyAccessScript.properties.provisioningState
