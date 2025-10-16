# Bicep Deployment Modules - Quick Reference

## Module Inventory

| Module | Purpose | Key Outputs |
|--------|---------|-------------|
| `ensureActiveCapacity.bicep` | Ensure Fabric capacity is active | `capacityState`, `capacityActive` |
| `fabricDomain.bicep` | Create Fabric domain | `domainId`, `domainName` |
| `fabricWorkspace.bicep` | Create Fabric workspace | `workspaceId`, `workspaceName`, `capacityId` |
| `createLakehouses.bicep` | Create lakehouses (bronze/silver/gold) | `lakehousesCreated`, `lakehouseIds` |
| `assignWorkspaceToDomain.bicep` | Assign workspace to domain | `domainAssigned`, `domainId`, `workspaceId` |
| `createPurviewCollection.bicep` | Create Purview collection | `collectionId`, `collectionName` |
| `registerFabricDatasource.bicep` | Register Fabric datasource in Purview | `datasourceName`, `collectionId` |
| `triggerPurviewScan.bicep` | Trigger Purview scan | `scanCreated`, `scanTriggered`, `runId`, `status` |
| `connectLogAnalytics.bicep` | Connect to Log Analytics (placeholder) | `connected`, `message` |

## Common Parameters

All modules support these parameters:

```bicep
param location string = resourceGroup().location
param tags object = {}
param userAssignedIdentityId string  // Required
param utcValue string = utcNow()
```

## Deployment Patterns

### Pattern 1: Full Stack (All Modules)
```bicep
module ensureCapacity 'modules/ensureActiveCapacity.bicep' = { ... }
module domain 'modules/fabricDomain.bicep' = { ... }
module workspace 'modules/fabricWorkspace.bicep' = { ... }
module lakehouses 'modules/createLakehouses.bicep' = { ... }
module assignDomain 'modules/assignWorkspaceToDomain.bicep' = { ... }
module purviewCollection 'modules/createPurviewCollection.bicep' = { ... }
module registerDatasource 'modules/registerFabricDatasource.bicep' = { ... }
module triggerScan 'modules/triggerPurviewScan.bicep' = { ... }
```

### Pattern 2: Fabric Only (No Purview)
```bicep
module ensureCapacity 'modules/ensureActiveCapacity.bicep' = { ... }
module domain 'modules/fabricDomain.bicep' = { ... }
module workspace 'modules/fabricWorkspace.bicep' = { ... }
module lakehouses 'modules/createLakehouses.bicep' = { ... }
module assignDomain 'modules/assignWorkspaceToDomain.bicep' = { ... }
```

### Pattern 3: Workspace + Lakehouses Only
```bicep
module workspace 'modules/fabricWorkspace.bicep' = { ... }
module lakehouses 'modules/createLakehouses.bicep' = { ... }
```

## CLI Commands

### Deploy Full Stack
```bash
az deployment group create \
  --resource-group <rg-name> \
  --template-file infra/examples/fullOrchestrationExample.bicep \
  --parameters @infra/examples/fullOrchestrationExample.parameters.json
```

### Deploy Single Module
```bash
az deployment group create \
  --resource-group <rg-name> \
  --template-file infra/modules/<module-name>.bicep \
  --parameters \
    param1=value1 \
    param2=value2 \
    userAssignedIdentityId=<identity-resource-id>
```

### Validate Before Deploy
```bash
az deployment group validate \
  --resource-group <rg-name> \
  --template-file <bicep-file> \
  --parameters @<params-file>
```

### What-If Analysis
```bash
az deployment group what-if \
  --resource-group <rg-name> \
  --template-file <bicep-file> \
  --parameters @<params-file>
```

### View Deployment Logs
```bash
# List deployment scripts
az deployment-scripts list --resource-group <rg-name>

# View logs
az deployment-scripts show-log \
  --resource-group <rg-name> \
  --name <deployment-script-name>
```

## Required Permissions

The user-assigned managed identity needs:

### Azure RBAC
- **Contributor** on resource group

### Fabric/Power BI
- **Fabric Administrator** role
- **Power BI Service Administrator** role

### Purview
- **Purview Data Curator** role on Purview account

## Dependency Chain

```
ensureActiveCapacity
    ↓
fabricDomain + fabricWorkspace (parallel)
    ↓
createLakehouses
    ↓
assignWorkspaceToDomain + createPurviewCollection (parallel)
    ↓
registerFabricDatasource
    ↓
triggerPurviewScan
```

## Troubleshooting Quick Tips

| Issue | Solution |
|-------|----------|
| "Failed to acquire token" | Check managed identity has required roles |
| "Capacity not active" | Run `ensureActiveCapacity` module first |
| "Workspace not found" | Ensure `fabricWorkspace` completed successfully |
| "Collection already exists" | Modules are idempotent - this is OK |
| Deployment script timeout | Increase `timeout` parameter in script properties |
| "Permission denied" | Add missing role to managed identity |

## Output Usage Examples

### Use outputs in subsequent modules
```bicep
module workspace 'modules/fabricWorkspace.bicep' = { ... }

module lakehouses 'modules/createLakehouses.bicep' = {
  params: {
    workspaceId: workspace.outputs.workspaceId
    workspaceName: workspace.outputs.workspaceName
  }
}
```

### Export outputs from deployment
```bicep
output workspaceId string = workspace.outputs.workspaceId
output lakehouseIds string = lakehouses.outputs.lakehouseIds
```

### Retrieve outputs after deployment
```bash
az deployment group show \
  --resource-group <rg-name> \
  --name <deployment-name> \
  --query properties.outputs
```

## Best Practices Checklist

- [ ] Use user-assigned managed identity (not system-assigned)
- [ ] Apply consistent tags across all resources
- [ ] Set explicit `dependsOn` for deployment order
- [ ] Use `utcNow()` for deployment script force updates
- [ ] Enable cleanup (`cleanupPreference: 'OnSuccess'`)
- [ ] Set appropriate timeout values
- [ ] Test in dev environment first
- [ ] Review deployment script logs
- [ ] Export important outputs
- [ ] Document custom parameter values

## File Locations

```
infra/
├── modules/
│   ├── README.md                        ← Full documentation
│   ├── ensureActiveCapacity.bicep
│   ├── fabricDomain.bicep
│   ├── fabricWorkspace.bicep
│   ├── createLakehouses.bicep
│   ├── assignWorkspaceToDomain.bicep
│   ├── createPurviewCollection.bicep
│   ├── registerFabricDatasource.bicep
│   ├── triggerPurviewScan.bicep
│   └── connectLogAnalytics.bicep
└── examples/
    ├── fullOrchestrationExample.bicep           ← Complete example
    └── fullOrchestrationExample.parameters.json ← Sample parameters
```

## Support Resources

- **Full Documentation**: `infra/modules/README.md`
- **Summary**: `BICEP_MODULES_SUMMARY.md`
- **Complete Example**: `infra/examples/fullOrchestrationExample.bicep`
- **Original Scripts**: `scripts/Fabric_Purview_Automation/*.ps1`

---

**Quick Start**: See `infra/examples/fullOrchestrationExample.bicep` for a complete working example.
