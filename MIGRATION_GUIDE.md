# Migration Guide: PowerShell Scripts to Bicep Modules

This guide helps you transition from running PowerShell scripts directly to using Bicep deployment modules.

## Why Migrate?

### Benefits of Bicep Modules

✅ **Declarative** - Define desired state, not steps  
✅ **Repeatable** - Same deployment every time  
✅ **Trackable** - Full deployment history in Azure  
✅ **Auditable** - Know who deployed what and when  
✅ **Integrated** - Works with Azure Pipelines, GitHub Actions  
✅ **Validated** - Parameter validation before deployment  
✅ **Dependency Management** - Automatic ordering  
✅ **Rollback Support** - Built-in rollback on failure  

### When to Use Scripts vs. Modules

| Use PowerShell Scripts | Use Bicep Modules |
|------------------------|-------------------|
| One-off manual tasks | Automated deployments |
| Troubleshooting | Production deployments |
| Exploration/learning | CI/CD pipelines |
| Custom workflows | Standard deployments |
| Quick fixes | Infrastructure as Code |

## Migration Paths

### Path 1: Gradual Migration (Recommended)

Migrate one component at a time while keeping others as scripts.

**Week 1: Capacity Management**
```bicep
// Start with capacity management
module ensureCapacity 'modules/ensureActiveCapacity.bicep' = {
  params: {
    fabricCapacityId: existingCapacity.id
    fabricCapacityName: existingCapacity.name
    userAssignedIdentityId: identity.id
  }
}

// Still run other scripts manually
```

**Week 2: Add Workspace Creation**
```bicep
module ensureCapacity 'modules/ensureActiveCapacity.bicep' = { ... }

module workspace 'modules/fabricWorkspace.bicep' = {
  params: {
    workspaceName: 'MyWorkspace'
    capacityId: existingCapacity.id
    userAssignedIdentityId: identity.id
  }
  dependsOn: [ensureCapacity]
}

// Still run lakehouse/Purview scripts manually
```

**Week 3: Add Lakehouses**
```bicep
module lakehouses 'modules/createLakehouses.bicep' = {
  params: {
    workspaceId: workspace.outputs.workspaceId
    workspaceName: workspace.outputs.workspaceName
    lakehouseNames: 'bronze,silver,gold'
    userAssignedIdentityId: identity.id
  }
  dependsOn: [workspace]
}
```

**Week 4: Add Purview (if needed)**
```bicep
module purviewCollection 'modules/createPurviewCollection.bicep' = { ... }
module registerDatasource 'modules/registerFabricDatasource.bicep' = { ... }
module triggerScan 'modules/triggerPurviewScan.bicep' = { ... }
```

### Path 2: Full Migration (Advanced)

Deploy everything at once using the complete orchestration example.

```bash
# Clone the full example
cp infra/examples/fullOrchestrationExample.bicep my-deployment.bicep
cp infra/examples/fullOrchestrationExample.parameters.json my-parameters.json

# Customize parameters
code my-parameters.json

# Deploy everything
az deployment group create \
  --resource-group myResourceGroup \
  --template-file my-deployment.bicep \
  --parameters @my-parameters.json
```

### Path 3: Hybrid Approach

Use Bicep for infrastructure, keep scripts for operations.

```bicep
// Bicep for infrastructure creation
module workspace 'modules/fabricWorkspace.bicep' = { ... }
module lakehouses 'modules/createLakehouses.bicep' = { ... }

// Then run operational scripts manually:
// - Data loading
// - Permissions management
// - Ad-hoc scans
```

## Script to Module Mapping

| PowerShell Script | Bicep Module | Notes |
|-------------------|--------------|-------|
| `ensure_active_capacity.ps1` | `ensureActiveCapacity.bicep` | Direct 1:1 mapping |
| `create_fabric_domain.ps1` | `fabricDomain.bicep` | Direct 1:1 mapping |
| `create_fabric_workspace.ps1` | `fabricWorkspace.bicep` | Direct 1:1 mapping |
| `create_lakehouses.ps1` | `createLakehouses.bicep` | Direct 1:1 mapping |
| `assign_workspace_to_domain.ps1` | `assignWorkspaceToDomain.bicep` | Direct 1:1 mapping |
| `create_purview_collection.ps1` | `createPurviewCollection.bicep` | Direct 1:1 mapping |
| `register_fabric_datasource.ps1` | `registerFabricDatasource.bicep` | Direct 1:1 mapping |
| `trigger_purview_scan_for_fabric_workspace.ps1` | `triggerPurviewScan.bicep` | Direct 1:1 mapping |
| `connect_log_analytics.ps1` | `connectLogAnalytics.bicep` | Placeholder (API not available) |

## Parameter Translation

### From Environment Variables to Bicep Parameters

**Before (PowerShell script with env vars):**
```powershell
$env:FABRIC_WORKSPACE_NAME = "MyWorkspace"
$env:FABRIC_CAPACITY_ID = "/subscriptions/.../capacities/myCapacity"
.\create_fabric_workspace.ps1
```

**After (Bicep module with parameters):**
```bicep
module workspace 'modules/fabricWorkspace.bicep' = {
  params: {
    workspaceName: 'MyWorkspace'
    capacityId: fabricCapacity.id  // or '/subscriptions/.../capacities/myCapacity'
    userAssignedIdentityId: identity.id
  }
}
```

### From Script Parameters to Module Parameters

**Before (PowerShell with parameters):**
```powershell
.\create_lakehouses.ps1 `
  -WorkspaceName "MyWorkspace" `
  -WorkspaceId "00000000-0000-0000-0000-000000000000" `
  -LakehouseNames "bronze,silver,gold"
```

**After (Bicep with parameters):**
```bicep
module lakehouses 'modules/createLakehouses.bicep' = {
  params: {
    workspaceName: 'MyWorkspace'
    workspaceId: '00000000-0000-0000-0000-000000000000'
    lakehouseNames: 'bronze,silver,gold'
    userAssignedIdentityId: identity.id
  }
}
```

## Common Migration Scenarios

### Scenario 1: Manual Deployment to Automated

**Current State:**
- Run scripts manually when needed
- Pass parameters via environment variables
- Execute in specific order

**Migration Steps:**

1. Create a managed identity:
```bash
az identity create \
  --name fabric-deployment-identity \
  --resource-group myResourceGroup
```

2. Assign roles to identity:
```bash
# Get identity principal ID
PRINCIPAL_ID=$(az identity show \
  --name fabric-deployment-identity \
  --resource-group myResourceGroup \
  --query principalId -o tsv)

# Assign Contributor role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role Contributor \
  --scope /subscriptions/.../resourceGroups/myResourceGroup
```

3. Create Bicep deployment:
```bicep
// main.bicep
module workspace 'modules/fabricWorkspace.bicep' = {
  params: {
    workspaceName: 'MyWorkspace'
    capacityId: '/subscriptions/.../capacities/myCapacity'
    userAssignedIdentityId: '/subscriptions/.../managedIdentities/fabric-deployment-identity'
  }
}
```

4. Deploy:
```bash
az deployment group create \
  --resource-group myResourceGroup \
  --template-file main.bicep
```

### Scenario 2: CI/CD Pipeline Integration

**Before (Azure Pipelines with scripts):**
```yaml
steps:
  - task: AzurePowerShell@5
    inputs:
      azureSubscription: 'MyServiceConnection'
      ScriptPath: 'scripts/create_fabric_workspace.ps1'
      ScriptArguments: '-WorkspaceName "$(workspaceName)"'
```

**After (Azure Pipelines with Bicep):**
```yaml
steps:
  - task: AzureCLI@2
    inputs:
      azureSubscription: 'MyServiceConnection'
      scriptType: 'bash'
      scriptLocation: 'inlineScript'
      inlineScript: |
        az deployment group create \
          --resource-group $(resourceGroup) \
          --template-file infra/examples/fullOrchestrationExample.bicep \
          --parameters @infra/examples/fullOrchestrationExample.parameters.json \
          --parameters workspaceName="$(workspaceName)"
```

### Scenario 3: Multi-Environment Deployment

**Before:**
- Separate script execution for dev/test/prod
- Manual parameter changes
- No environment tracking

**After:**
```bicep
// main.bicep
param environmentName string  // 'dev', 'test', 'prod'

var environmentConfig = {
  dev: {
    capacitySku: 'F2'
    lakehouseNames: 'bronze,silver'
  }
  test: {
    capacitySku: 'F4'
    lakehouseNames: 'bronze,silver,gold'
  }
  prod: {
    capacitySku: 'F16'
    lakehouseNames: 'bronze,silver,gold'
  }
}

module lakehouses 'modules/createLakehouses.bicep' = {
  params: {
    lakehouseNames: environmentConfig[environmentName].lakehouseNames
    // ...
  }
}
```

Deploy to each environment:
```bash
# Dev
az deployment group create \
  --resource-group rg-fabric-dev \
  --template-file main.bicep \
  --parameters environmentName=dev

# Test
az deployment group create \
  --resource-group rg-fabric-test \
  --template-file main.bicep \
  --parameters environmentName=test

# Prod
az deployment group create \
  --resource-group rg-fabric-prod \
  --template-file main.bicep \
  --parameters environmentName=prod
```

## Troubleshooting Migration Issues

### Issue: "Can't find my outputs"

**Problem:** Script output was in console, now need structured outputs.

**Solution:** Use Bicep outputs and query them:
```bash
az deployment group show \
  --resource-group myResourceGroup \
  --name myDeployment \
  --query properties.outputs.workspaceId.value -o tsv
```

### Issue: "Script ran but Bicep module failed"

**Problem:** Different error handling between scripts and modules.

**Solution:** Check deployment script logs:
```bash
az deployment-scripts show-log \
  --resource-group myResourceGroup \
  --name deploy-fabric-workspace-abc123
```

### Issue: "Can't pass complex parameters"

**Problem:** Need to pass arrays or objects.

**Solution:** Use JSON in parameters file:
```json
{
  "parameters": {
    "adminUPNs": {
      "value": "admin1@contoso.com,admin2@contoso.com"
    }
  }
}
```

### Issue: "Deployment takes too long"

**Problem:** Deployment scripts have timeout limits.

**Solution:** Increase timeout in module:
```bicep
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  properties: {
    timeout: 'PT1H'  // 1 hour instead of default 30 minutes
  }
}
```

## Best Practices During Migration

1. **Test in Dev First** - Never migrate production directly
2. **Keep Scripts** - Don't delete scripts until Bicep is proven
3. **Document Changes** - Note what works differently
4. **Version Control** - Commit working states frequently
5. **Monitor Deployments** - Watch Azure deployment history
6. **Backup First** - Export existing configurations
7. **Use What-If** - Run `az deployment group what-if` first
8. **Incremental Changes** - Migrate one module at a time

## Rollback Plan

If Bicep deployment fails, you can:

1. **Redeploy with scripts:**
```bash
# Fall back to scripts
.\scripts\Fabric_Purview_Automation\create_fabric_workspace.ps1
```

2. **Delete failed deployment:**
```bash
az deployment group delete \
  --resource-group myResourceGroup \
  --name myDeployment
```

3. **Clean up deployment scripts:**
```bash
# List them
az deployment-scripts list --resource-group myResourceGroup

# Delete
az deployment-scripts delete \
  --resource-group myResourceGroup \
  --name deploy-fabric-workspace-abc123
```

## Success Checklist

- [ ] Created managed identity with required roles
- [ ] Tested one module in dev environment
- [ ] Documented parameter mappings
- [ ] Updated CI/CD pipelines (if applicable)
- [ ] Trained team on Bicep deployment
- [ ] Created environment-specific parameter files
- [ ] Established deployment monitoring
- [ ] Documented rollback procedures
- [ ] Migrated all critical workflows
- [ ] Kept scripts as backup for 3 months

## Getting Help

- **Full Documentation**: `infra/modules/README.md`
- **Quick Reference**: `BICEP_MODULES_QUICK_REFERENCE.md`
- **Examples**: `infra/examples/fullOrchestrationExample.bicep`
- **Original Scripts**: `scripts/Fabric_Purview_Automation/*.ps1`

## Next Steps After Migration

1. Set up automated deployments
2. Implement deployment gates
3. Add deployment notifications
4. Create deployment templates for common scenarios
5. Build self-service deployment portal
6. Enable deployment approvals
7. Implement infrastructure drift detection

---

**Remember**: Migration is a journey, not a destination. Take it one step at a time!
