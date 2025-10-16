# Module Organization Changelog

## Overview

Bicep modules have been reorganized into logical category folders for improved discoverability, maintainability, and scalability.

## New Folder Structure

```
infra/modules/
├── README.md                          # Main documentation (updated)
├── fabric/                            # Microsoft Fabric operations
│   ├── ensureActiveCapacity.bicep
│   ├── fabricDomain.bicep
│   ├── fabricWorkspace.bicep
│   ├── assignWorkspaceToDomain.bicep
│   └── createLakehouses.bicep
├── purview/                           # Azure Purview governance
│   ├── createPurviewCollection.bicep
│   ├── registerFabricDatasource.bicep
│   └── triggerPurviewScan.bicep
├── monitoring/                        # Monitoring & observability
│   └── connectLogAnalytics.bicep
└── onelake-index/                    # OneLake AI Search (future)
    └── README.md                      # Planned modules documentation
```

## Migration Path

### Before (Flat Structure)

```bicep
module capacity '../modules/ensureActiveCapacity.bicep' = { ... }
module domain '../modules/fabricDomain.bicep' = { ... }
module collection '../modules/createPurviewCollection.bicep' = { ... }
```

### After (Organized Structure)

```bicep
module capacity '../modules/fabric/ensureActiveCapacity.bicep' = { ... }
module domain '../modules/fabric/fabricDomain.bicep' = { ... }
module collection '../modules/purview/createPurviewCollection.bicep' = { ... }
```

## What Changed

### Files Moved

| Original Path | New Path | Category |
|--------------|----------|----------|
| `modules/ensureActiveCapacity.bicep` | `modules/fabric/ensureActiveCapacity.bicep` | Fabric |
| `modules/fabricDomain.bicep` | `modules/fabric/fabricDomain.bicep` | Fabric |
| `modules/fabricWorkspace.bicep` | `modules/fabric/fabricWorkspace.bicep` | Fabric |
| `modules/assignWorkspaceToDomain.bicep` | `modules/fabric/assignWorkspaceToDomain.bicep` | Fabric |
| `modules/createLakehouses.bicep` | `modules/fabric/createLakehouses.bicep` | Fabric |
| `modules/createPurviewCollection.bicep` | `modules/purview/createPurviewCollection.bicep` | Purview |
| `modules/registerFabricDatasource.bicep` | `modules/purview/registerFabricDatasource.bicep` | Purview |
| `modules/triggerPurviewScan.bicep` | `modules/purview/triggerPurviewScan.bicep` | Purview |
| `modules/connectLogAnalytics.bicep` | `modules/monitoring/connectLogAnalytics.bicep` | Monitoring |

### Files Updated with New Paths

All orchestration examples have been updated to reference the new module paths:

- ✅ `infra/examples/fullOrchestrationExample.bicep`
- ✅ `infra/examples/sequentialOrchestrationExample.bicep`
- ✅ `infra/examples/fabricDomainExample.bicep`
- ✅ `infra/examples/fabricWorkspaceExample.bicep`
- ✅ `infra/examples/main-bicep-integration.bicep`

### Documentation Updated

- ✅ **`infra/modules/README.md`** - Completely rewritten with:
  - Visual folder structure diagram
  - Category-based organization
  - Updated module paths in all examples
  - Module quick reference by category
  
- ✅ **`infra/modules/onelake-index/README.md`** - New file documenting:
  - Planned OneLake Index modules
  - Current PowerShell script alternatives
  - Future design patterns
  - Contributing guidelines

## Benefits of Reorganization

### 1. **Improved Discoverability**
Modules are now grouped by functional area, making it easier to find the right module for your task:
- Need Fabric operations? → `fabric/`
- Need Purview governance? → `purview/`
- Need monitoring? → `monitoring/`

### 2. **Logical Grouping**
Related operations are co-located:
- All Fabric workspace/domain operations in one folder
- All Purview governance operations together
- Clear separation of concerns

### 3. **Scalability**
Easy to add new modules in the future:
- OneLake Index modules can be added to `onelake-index/`
- New categories can be added as needed (e.g., `security/`, `networking/`)

### 4. **Maintainability**
- Easier to navigate during development
- Clear ownership and responsibility boundaries
- Simpler to update category-specific documentation

### 5. **Alignment with Best Practices**
Follows Azure Bicep module organization best practices:
- Category-based folder structure
- Separate concerns
- Single responsibility per folder

## Impact on Existing Code

### ✅ No Breaking Changes for New Deployments
If you're starting fresh with the examples:
- All example templates have been updated
- No action required - just use the examples

### ⚠️ Action Required for Custom Templates
If you have custom Bicep templates referencing the old module paths:

1. **Find all module references:**
   ```bash
   grep -r "../modules/" your-custom-templates/
   ```

2. **Update paths using this mapping:**
   ```bicep
   # Fabric modules - add "fabric/" folder
   '../modules/ensureActiveCapacity.bicep'      → '../modules/fabric/ensureActiveCapacity.bicep'
   '../modules/fabricDomain.bicep'              → '../modules/fabric/fabricDomain.bicep'
   '../modules/fabricWorkspace.bicep'           → '../modules/fabric/fabricWorkspace.bicep'
   '../modules/assignWorkspaceToDomain.bicep'   → '../modules/fabric/assignWorkspaceToDomain.bicep'
   '../modules/createLakehouses.bicep'          → '../modules/fabric/createLakehouses.bicep'
   
   # Purview modules - add "purview/" folder
   '../modules/createPurviewCollection.bicep'   → '../modules/purview/createPurviewCollection.bicep'
   '../modules/registerFabricDatasource.bicep'  → '../modules/purview/registerFabricDatasource.bicep'
   '../modules/triggerPurviewScan.bicep'        → '../modules/purview/triggerPurviewScan.bicep'
   
   # Monitoring modules - add "monitoring/" folder
   '../modules/connectLogAnalytics.bicep'       → '../modules/monitoring/connectLogAnalytics.bicep'
   ```

3. **Use sed for batch updates (Linux/Mac):**
   ```bash
   sed -i "s|'../modules/fabricDomain\\.bicep'|'../modules/fabric/fabricDomain.bicep'|g" your-template.bicep
   # Repeat for each module
   ```

## Verification

To verify your templates still work after updating paths:

```bash
# Check for syntax errors
az bicep build --file your-template.bicep

# Validate the template
az deployment group validate \
  --resource-group <rg-name> \
  --template-file your-template.bicep \
  --parameters @your-parameters.json
```

## Future Additions

### OneLake Index Modules (Planned)

The `onelake-index/` folder is ready for future modules that will wrap PowerShell scripts:

- `setupSearchRbac.bicep`
- `createOneLakeSkillsets.bicep`
- `createOneLakeIndex.bicep`
- `createOneLakeDatasource.bicep`
- `createOneLakeIndexer.bicep`
- `setupAIFoundrySearchRbac.bicep`
- `automateAIFoundryConnection.bicep`

See `infra/modules/onelake-index/README.md` for details.

## Questions & Support

- **Documentation**: See `infra/modules/README.md` for complete module documentation
- **Examples**: See `infra/examples/` for updated orchestration examples
- **Execution Order**: See `EXECUTION_ORDER_GUIDE.md` for dependency management
- **Migration**: See `MIGRATION_GUIDE.md` for PowerShell → Bicep migration

## Summary

This reorganization provides a solid foundation for future growth while maintaining backward compatibility through simple path updates. All examples and documentation have been updated to reflect the new structure.

**Action Items:**
- ✅ No action required for new deployments using provided examples
- ⚠️ Update custom templates to use new module paths (see mapping above)
- ℹ️ Review `infra/modules/README.md` for updated module documentation
