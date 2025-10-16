# Using Bicep Module Orchestration

This guide explains how to use `main-with-modules.bicep` to deploy your Fabric-Purview integration infrastructure using Bicep deployment script modules instead of post-provisioning shell scripts.

## Overview

`main-with-modules.bicep` provides a **fully declarative alternative** to the shell script-based post-provisioning approach. All Fabric workspace creation, domain assignment, lakehouse provisioning, and Purview integration steps are now handled by Bicep deployment script modules.

## Key Benefits

✅ **Fully Declarative** - No manual post-provisioning scripts needed  
✅ **Idempotent** - Can be re-run safely  
✅ **Cost Optimized** - Single shared storage account for all deployment scripts  
✅ **Better Dependency Management** - Bicep handles sequencing automatically  
✅ **Integrated RBAC** - Managed identity created and used consistently  
✅ **Optional Features** - Enable/disable Purview scanning and Log Analytics

## Architecture

### Deployment Flow

```
1. Fabric Capacity (AVM module)
   ↓
2. Managed Identity (for deployment scripts)
   ↓
3. Shared Storage Account (cost optimization)
   ↓
4. Fabric Domain creation
   ↓
5. Fabric Workspace creation
   ↓
6. Assign Workspace to Domain
   ↓
7. Ensure Capacity is Active
   ↓
8. Create Lakehouses (bronze, silver, gold)
   ↓
9. Create Purview Collection
   ↓
10. Register Fabric as Purview Datasource
    ↓
11. [OPTIONAL] Trigger Purview Scan
    ↓
12. [OPTIONAL] Connect Log Analytics
```

### Resource Organization

```
infra/
├── main-with-modules.bicep        # Orchestration file (THIS FILE)
├── main-with-modules.bicepparam   # Parameters
└── modules/
    ├── shared/
    │   └── deploymentScriptStorage.bicep    # Shared storage (deployed once)
    ├── fabric/
    │   ├── fabricDomain.bicep
    │   ├── fabricWorkspace.bicep
    │   ├── assignWorkspaceToDomain.bicep
    │   ├── ensureActiveCapacity.bicep
    │   └── createLakehouses.bicep
    ├── purview/
    │   ├── createPurviewCollection.bicep
    │   ├── registerFabricDatasource.bicep
    │   └── triggerPurviewScan.bicep
    └── monitoring/
        └── connectLogAnalytics.bicep
```

## Prerequisites

### 1. Azure Permissions

The deployment requires:

- **Subscription Contributor** or higher
- **Fabric Administrator** permissions (for workspace/domain operations)
- **Purview Data Curator** permissions (for collection/datasource operations)

### 2. Existing Resources

Ensure these exist before deployment:

- ✅ Azure Subscription
- ✅ Resource Group
- ✅ **Purview Account** (specified in parameters)

### 3. RBAC Setup (IMPORTANT!)

The orchestration creates a **Managed Identity** but does NOT automatically assign roles. You must:

**Option A: Pre-assign roles to the Managed Identity**

```bash
# Get the managed identity principal ID after first deployment
PRINCIPAL_ID=$(az deployment group show \
  --resource-group <your-rg> \
  --name <deployment-name> \
  --query properties.outputs.managedIdentityPrincipalId.value \
  --output tsv)

# Assign Fabric Administrator role (use appropriate role ID for your environment)
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Fabric Administrator" \
  --scope /subscriptions/<subscription-id>

# Assign Purview Data Curator role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Purview Data Curator" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<purview-rg>/providers/Microsoft.Purview/accounts/<purview-account>
```

**Option B: Use custom RBAC module**

Uncomment and customize the RBAC section in `main-with-modules.bicep` (lines 188-198).

## Deployment Steps

### Step 1: Configure Parameters

Edit `main-with-modules.bicepparam`:

```bicep
// REQUIRED: Update these for your environment
param location = 'eastus'  // Your Azure region
param fabricCapacityName = 'your-capacity-name'
param fabricCapacitySKU = 'F8'  // Choose appropriate SKU
param capacityAdminMembers = ['admin@yourdomain.com']

param fabricWorkspaceName = 'your-workspace'
param domainName = 'your-domain'
param purviewAccountName = 'your-purview-account'

// OPTIONAL: Enable features
param enablePurviewScan = false  // Set true to trigger scan immediately
param enableLogAnalytics = false  // Set true if using Log Analytics
```

### Step 2: Deploy

#### Option A: Using Azure CLI

```bash
# Deploy to existing resource group
az deployment group create \
  --resource-group <your-resource-group> \
  --template-file infra/main-with-modules.bicep \
  --parameters infra/main-with-modules.bicepparam \
  --name fabric-purview-deployment
```

#### Option B: Using Azure Developer CLI (azd)

Update `azure.yaml` to use the new main file:

```yaml
infra:
  provider: "bicep"
  path: "infra"
  module: "main-with-modules"  # Changed from "main"
```

Then deploy:

```bash
azd up
```

#### Option C: Using PowerShell

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName <your-resource-group> `
  -TemplateFile infra/main-with-modules.bicep `
  -TemplateParameterFile infra/main-with-modules.bicepparam `
  -Name fabric-purview-deployment
```

### Step 3: Monitor Deployment

Deployment typically takes **30-60 minutes** due to deployment scripts. Monitor progress:

```bash
# Watch deployment status
az deployment group show \
  --resource-group <your-rg> \
  --name fabric-purview-deployment \
  --query properties.provisioningState

# View deployment logs
az deployment operation group list \
  --resource-group <your-rg> \
  --name fabric-purview-deployment
```

## Deployment Script Behavior

### Storage Account Usage

All 9 deployment script modules share a **single storage account** (`stdeploy{unique-id}`):

- **Cost**: ~$0.02/month vs ~$0.22/month for 11 separate accounts
- **Cleanup**: Automatically cleaned up by Azure after retention period
- **Logs**: Deployment script outputs stored temporarily

### Managed Identity

The orchestration creates a **User-Assigned Managed Identity**:

- **Name**: `id-fabric-automation-{unique-id}`
- **Purpose**: Execute deployment scripts with consistent identity
- **Lifecycle**: Persists after deployment for future updates

### Deployment Script Retention

- **Default**: Scripts retained for 1 day (`retentionInterval: 'P1D'`)
- **Cleanup**: `cleanupPreference: 'OnSuccess'` - scripts deleted after success
- **Troubleshooting**: Check script logs in Azure Portal if deployment fails

## Optional Features

### Enable Purview Scanning

Set `enablePurviewScan = true` to automatically trigger a Purview scan after datasource registration:

```bicep
param enablePurviewScan = true
```

**Note**: Scanning can take additional time depending on data volume.

### Enable Log Analytics Connection

Set `enableLogAnalytics = true` and provide workspace ID:

```bicep
param enableLogAnalytics = true
param logAnalyticsWorkspaceId = '/subscriptions/.../resourceGroups/.../providers/Microsoft.OperationalInsights/workspaces/...'
```

## Outputs

After successful deployment, you'll have these outputs:

| Output | Description |
|--------|-------------|
| `fabricCapacityId` | Resource ID of Fabric capacity |
| `fabricWorkspaceId` | Workspace ID (from deployment script) |
| `fabricDomainName` | Domain name |
| `managedIdentityId` | Managed identity resource ID |
| `managedIdentityPrincipalId` | Principal ID for RBAC assignments |
| `sharedStorageAccountName` | Shared storage account name |
| `purviewAccountName` | Purview account name |
| `deploymentComplete` | Boolean indicating success |

Access outputs:

```bash
az deployment group show \
  --resource-group <your-rg> \
  --name fabric-purview-deployment \
  --query properties.outputs
```

## Troubleshooting

### Deployment Script Failures

1. **Check deployment script logs** in Azure Portal:
   - Navigate to Resource Group → Deployment Scripts
   - Click on failed script
   - View "Logs" tab

2. **Common issues**:
   - ❌ **Insufficient permissions**: Managed identity lacks required roles
   - ❌ **Capacity not active**: Ensure F-series capacity has budget
   - ❌ **Purview permissions**: Managed identity needs Data Curator role
   - ❌ **Resource not found**: Check resource names/IDs in parameters

### Managed Identity RBAC Issues

If deployment scripts fail with "Unauthorized" or "Forbidden":

```bash
# Verify managed identity has required roles
az role assignment list \
  --assignee <managed-identity-principal-id> \
  --output table
```

Expected roles:
- Fabric Administrator (or equivalent)
- Purview Data Curator
- Contributor (on resource group)

### Capacity Issues

If workspace creation fails:

```bash
# Check capacity status
az fabric capacity show \
  --name <capacity-name> \
  --resource-group <your-rg> \
  --query state
```

Capacity must be in **"Active"** state. Resume if paused.

## Comparison: Shell Scripts vs. Bicep Modules

| Aspect | Shell Scripts (old) | Bicep Modules (new) |
|--------|---------------------|---------------------|
| **Deployment** | 2-step (provision + post-provision) | Single `az deployment` |
| **Idempotency** | Manual scripting required | Built-in |
| **Dependencies** | Manual ordering in YAML | Automatic via Bicep |
| **Storage Accounts** | 11 separate accounts | 1 shared account |
| **Cost** | ~$0.22/month | ~$0.02/month |
| **Troubleshooting** | Check YAML logs | Azure Portal deployment logs |
| **Re-runs** | Risk of duplicates | Safe to re-run |
| **RBAC** | Hard-coded in scripts | Managed identity + role assignments |

## Migration from Shell Scripts

If you're currently using the shell script approach (`azure.yaml` + `scripts/`):

1. **Keep existing deployment** - No need to tear down
2. **Switch orchestration file** - Update `azure.yaml`:
   ```yaml
   module: "main-with-modules"  # Was "main"
   ```
3. **Remove post-provision hooks** (optional):
   ```yaml
   # Comment out or remove:
   # postProvisionHooks:
   #   - ./scripts/...
   ```
4. **Deploy updates** - Use `azd deploy` or `az deployment group create`

**Important**: Resources created by shell scripts will not be automatically imported. Consider:
- **Green/Blue deployment**: Create new workspace/domain with modules, then migrate
- **Manual import**: Use existing resource IDs where possible

## Advanced: Customizing Modules

All modules are in `infra/modules/`. To customize:

1. **Edit module** (e.g., `fabric/fabricWorkspace.bicep`)
2. **Update orchestration** if parameters changed
3. **Redeploy** - Bicep will update only changed resources

Example: Add custom workspace configuration:

```bicep
// In fabricWorkspace.bicep
param customSetting string = 'default'

// In scriptContent
Set-FabricWorkspaceSettings -CustomSetting $env:CUSTOM_SETTING
```

## Cost Considerations

### Deployment Script Storage

- **Shared storage**: ~$0.02/month (Standard_LRS)
- **Transaction costs**: Minimal (~$0.01/deployment)
- **Retention**: 1 day (customize via `retentionInterval`)

### Managed Identity

- **Free** - No charges for User-Assigned Managed Identities

### Fabric Capacity

- **Variable** - Based on SKU (F2-F2048)
- **Auto-pause** - Consider enabling for dev/test environments

## Next Steps

- ✅ **Review outputs** - Verify all resources created successfully
- ✅ **Test workspace** - Login to Fabric and verify workspace/domain
- ✅ **Configure RBAC** - Assign users to workspace/domain
- ✅ **Add lakehouses data** - Populate bronze/silver/gold lakehouses
- ✅ **Verify Purview** - Check datasource registration and scans
- ✅ **Enable monitoring** - Configure Log Analytics if needed

## Support

- **Issues**: See [Troubleshooting](#troubleshooting) section
- **Documentation**: Review individual module READMEs in `infra/modules/`
- **Logs**: Check Azure Portal → Deployment Scripts for detailed logs

## Related Documentation

- [Module Organization](../modules/MODULE_ORGANIZATION.md)
- [Execution Order Guide](../modules/EXECUTION_ORDER_GUIDE.md)
- [Shared Storage Module](../modules/shared/README.md)
- [Fabric Modules](../modules/fabric/README.md)
- [Purview Modules](../modules/purview/README.md)
