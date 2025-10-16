# OneLake Index Modules

_Status: Planned / Future Development_

This folder will contain Bicep deployment script modules for Azure AI Search OneLake indexing operations. These modules will wrap the PowerShell scripts currently located in `scripts/OneLakeIndex/`.

## Planned Modules

The following modules are planned to automate OneLake indexing with Azure AI Search:

1. **setupSearchRbac.bicep** - Setup RBAC permissions for Azure AI Search on OneLake
2. **createOneLakeSkillsets.bicep** - Create AI skillsets for OneLake data processing
3. **createOneLakeIndex.bicep** - Create the search index schema for OneLake
4. **createOneLakeDatasource.bicep** - Register OneLake as a datasource
5. **createOneLakeIndexer.bicep** - Create and configure the OneLake indexer
6. **setupAIFoundrySearchRbac.bicep** - Setup RBAC for AI Foundry integration
7. **automateAIFoundryConnection.bicep** - Automate AI Foundry search connection

## Current State

Currently, these operations are automated via PowerShell scripts in `scripts/OneLakeIndex/`. To use these capabilities today:

```bash
# Run PowerShell scripts in sequence
./scripts/OneLakeIndex/01_setup_rbac.ps1
./scripts/OneLakeIndex/02_create_onelake_skillsets.ps1
./scripts/OneLakeIndex/03_create_onelake_index.ps1
./scripts/OneLakeIndex/04_create_onelake_datasource.ps1
./scripts/OneLakeIndex/05_create_onelake_indexer.ps1
./scripts/OneLakeIndex/06_setup_ai_foundry_search_rbac.ps1
./scripts/OneLakeIndex/07_automate_ai_foundry_connection.ps1
```

See `scripts/OneLakeIndex/README.md` for detailed documentation.

## Future Design

When implemented, these modules will follow the same patterns as other modules:

- **Idempotent operations** - Safe to run multiple times
- **Deployment script wrappers** - Each module wraps atomic operations
- **Output chaining** - Modules expose outputs for dependency management
- **Consistent parameters** - userAssignedIdentityId, location, tags, etc.

Example future usage:

```bicep
module searchRbac 'modules/onelake-index/setupSearchRbac.bicep' = {
  name: 'setup-search-rbac'
  params: {
    searchServiceName: 'mySearchService'
    storageAccountName: 'onelakestorage'
    userAssignedIdentityId: deploymentIdentity.id
  }
}

module indexer 'modules/onelake-index/createOneLakeIndexer.bicep' = {
  name: 'create-indexer'
  params: {
    searchServiceName: 'mySearchService'
    indexerName: 'onelake-indexer'
    datasourceName: datasource.outputs.datasourceName
    indexName: index.outputs.indexName
    userAssignedIdentityId: deploymentIdentity.id
  }
  dependsOn: [searchRbac]
}
```

## Contributing

If you'd like to contribute Bicep modules for OneLake indexing operations:

1. Follow the existing module patterns in `fabric/` and `purview/` folders
2. Wrap the equivalent PowerShell script functionality
3. Ensure idempotent behavior
4. Add comprehensive documentation
5. Update this README with module details
6. Add examples to the main `infra/examples/` folder

## Related Documentation

- **PowerShell Scripts**: `scripts/OneLakeIndex/`
- **OneLake Index README**: `scripts/OneLakeIndex/README.md`
- **Module Design Patterns**: `infra/modules/README.md`
- **Migration Guide**: `MIGRATION_GUIDE.md`
