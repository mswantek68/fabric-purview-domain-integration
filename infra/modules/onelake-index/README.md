# OneLake Index Bicep Modules

This folder contains Bicep modules for setting up Azure AI Search indexing of Microsoft Fabric OneLake data.

## Module Overview

| Module | Description | PowerShell Script |
|--------|-------------|-------------------|
| `setupRBAC.bicep` | Configures RBAC permissions for AI Search managed identity to access OneLake and AI Foundry | `01_setup_rbac.ps1` |
| `createSkillsets.bicep` | Creates AI Search skillsets for document processing (text extraction, chunking) | `02_create_onelake_skillsets.ps1` |
| `createIndex.bicep` | Creates the search index schema for OneLake documents | `03_create_onelake_index.ps1` |
| `createDataSource.bicep` | Creates the OneLake data source connection to Fabric lakehouse | `04_create_onelake_datasource.ps1` |
| `createIndexer.bicep` | Creates and runs the indexer to process OneLake documents | `05_create_onelake_indexer.ps1` |

## Execution Order

These modules must be deployed in sequence:

1. **setupRBAC** - Configure permissions first
2. **createSkillsets** - Define how documents are processed
3. **createIndex** - Create the search index schema
4. **createDataSource** - Connect to the Fabric lakehouse
5. **createIndexer** - Start indexing documents

## Shared Storage Account

All OneLake Index modules use a **shared storage account** for deployment scripts. This storage account is created once (typically with the first Fabric module) and passed as a parameter to all subsequent modules.

### Benefits of Shared Storage Account:
- **Cost Reduction**: Single storage account instead of 5+ separate accounts
- **Simplified Management**: One resource to monitor and maintain
- **Consistent Configuration**: Same settings across all deployment scripts

## Prerequisites

### Azure Resources Required:
- **AI Search Service** with system-assigned managed identity enabled
- **AI Foundry Workspace** 
- **Fabric Workspace** with lakehouse
- **User-Assigned Managed Identity** with:
  - Fabric Admin role
  - Power BI Service Admin role
  - Storage Blob Data Reader role

### RBAC Permissions:
The AI Search managed identity needs:
- OneLake data access role in Fabric workspace
- Search Service Contributor role
- Storage Blob Data Reader role

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure AI Search has system-assigned managed identity enabled
   - Verify RBAC permissions are set correctly
   - Check that the user-assigned managed identity has Fabric Admin role

2. **No Documents Indexed**
   - Verify lakehouse has documents in the specified path
   - Check AI Search managed identity has OneLake data access
   - Review indexer status for detailed error messages

3. **Storage Account Issues**
   - Ensure shared storage account is deployed first
   - Verify storage account name is passed correctly to all modules
   - Check that managed identity has access to storage account

## Related Documentation

- [Azure AI Search OneLake Indexing](https://learn.microsoft.com/azure/search/search-howto-index-onelake-files)
- [Microsoft Fabric OneLake](https://learn.microsoft.com/fabric/onelake/onelake-overview)
- [Azure Deployment Scripts](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-script-bicep)
- [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/)
