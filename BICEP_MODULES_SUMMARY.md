# Bicep Deployment Modules - Feature Branch Summary

## Overview

This feature branch (`feature/bicep-deployment-modules`) adds comprehensive Bicep deployment script modules for each atomic operation in the Fabric-Purview integration workflow. Each module wraps a PowerShell script as a deployment script resource, providing maximum flexibility for infrastructure-as-code deployments.

## What Was Added

### New Bicep Modules (7 total)

1. **`ensureActiveCapacity.bicep`** - Ensures Fabric capacity is active, attempts resume if paused/suspended
2. **`assignWorkspaceToDomain.bicep`** - Assigns Fabric workspace to a domain by capacity
3. **`createLakehouses.bicep`** - Creates bronze/silver/gold lakehouses in a workspace
4. **`createPurviewCollection.bicep`** - Creates a collection in Azure Purview
5. **`registerFabricDatasource.bicep`** - Registers Fabric workspace as Purview datasource
6. **`triggerPurviewScan.bicep`** - Creates and triggers Purview scan for workspace
7. **`connectLogAnalytics.bicep`** - Placeholder for Log Analytics integration (API not available)

### Documentation

- **`infra/modules/README.md`** - Comprehensive documentation including:
  - Description of each module
  - Parameter documentation
  - Output documentation
  - Usage examples
  - Common deployment patterns
  - Troubleshooting guide
  - Best practices

### Examples

- **`infra/examples/fullOrchestrationExample.bicep`** - Complete end-to-end example showing:
  - Sequential deployment of all modules
  - Proper dependency management
  - Conditional Purview integration
  - All outputs captured and exposed
  
- **`infra/examples/fullOrchestrationExample.parameters.json`** - Sample parameters file

## Key Features

### Modular Design
Each module is completely independent and can be used alone or in combination with others. This gives users maximum flexibility to:
- Deploy only what they need
- Skip steps they want to handle manually
- Customize the deployment sequence
- Reuse modules across different projects

### Atomic Operations
Each module wraps exactly one atomic script operation:
- Maps 1:1 to PowerShell scripts in `scripts/Fabric_Purview_Automation/`
- Ensures single responsibility
- Makes troubleshooting easier
- Enables incremental deployments

### Idempotent Execution
All modules handle existing resources gracefully:
- Check for existing resources before creation
- Skip creation if resource already exists
- Update resources when appropriate
- Return consistent outputs regardless of state

### Comprehensive Error Handling
- Proper error messages in deployment script logs
- Fallback mechanisms for API calls
- Graceful degradation when APIs are unavailable
- Clear output messages about what happened

## Module Architecture

Each module follows a consistent pattern:

```bicep
// 1. Parameters (inputs)
param resourceName string
param location string = resourceGroup().location
param userAssignedIdentityId string
// ...

// 2. Storage account for deployment script
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = { ... }

// 3. Deployment script resource
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  // Environment variables pass parameters to script
  environmentVariables: [ ... ]
  
  // PowerShell script content (embedded)
  scriptContent: '''
    # PowerShell logic here
    # Sets $DeploymentScriptOutputs for Bicep
  '''
}

// 4. Outputs (results)
output resourceId string = deploymentScript.properties.outputs.resourceId
```

## Deployment Sequence

The recommended deployment sequence (as shown in `fullOrchestrationExample.bicep`):

```
1. ensureActiveCapacity     → Ensure capacity is ready
2. fabricDomain             → Create domain
3. fabricWorkspace          → Create workspace
4. createLakehouses         → Create lakehouses
5. assignWorkspaceToDomain  → Assign to domain
6. createPurviewCollection  → Create Purview collection
7. registerFabricDatasource → Register in Purview
8. triggerPurviewScan       → Scan the workspace
9. connectLogAnalytics      → (Optional) Connect Log Analytics
```

## Prerequisites

To use these modules, you need:

1. **User-Assigned Managed Identity** with:
   - Fabric Administrator role
   - Power BI Service Administrator
   - Purview Data Curator role
   - Contributor role on resource group

2. **Existing Resources**:
   - Fabric capacity (or module will create one)
   - Purview account (if using Purview integration)
   - Log Analytics workspace (if using Log Analytics integration)

3. **Azure CLI** installed in deployment environment

## Usage Examples

### Deploy Everything
```bash
az deployment group create \
  --resource-group myResourceGroup \
  --template-file infra/examples/fullOrchestrationExample.bicep \
  --parameters infra/examples/fullOrchestrationExample.parameters.json
```

### Deploy Single Module
```bash
az deployment group create \
  --resource-group myResourceGroup \
  --template-file infra/modules/createLakehouses.bicep \
  --parameters \
    workspaceName=MyWorkspace \
    workspaceId=00000000-0000-0000-0000-000000000000 \
    lakehouseNames="bronze,silver,gold" \
    userAssignedIdentityId=/subscriptions/.../managedIdentities/myIdentity
```

### Use in Your Own Bicep
```bicep
module lakehouses 'path/to/modules/createLakehouses.bicep' = {
  name: 'deployLakehouses'
  params: {
    workspaceName: 'MyWorkspace'
    workspaceId: workspace.outputs.workspaceId
    lakehouseNames: 'bronze,silver,gold,raw'
    userAssignedIdentityId: identity.id
  }
}
```

## Benefits Over Script-Based Approach

### Before (Scripts Only)
- Manual execution required
- No declarative state
- Hard to track what's deployed
- Difficult to integrate with pipelines
- No automatic retry/rollback

### After (Bicep Modules)
- Declarative infrastructure-as-code
- Full Azure deployment tracking
- Easy CI/CD integration
- Automatic dependency management
- Native retry and rollback support
- Parameter validation
- Deployment history and auditing

## Testing the Modules

1. **Validate Bicep syntax**:
   ```bash
   az bicep build --file infra/examples/fullOrchestrationExample.bicep
   ```

2. **What-if deployment**:
   ```bash
   az deployment group what-if \
     --resource-group myResourceGroup \
     --template-file infra/examples/fullOrchestrationExample.bicep \
     --parameters @infra/examples/fullOrchestrationExample.parameters.json
   ```

3. **Deploy to dev environment**:
   ```bash
   az deployment group create \
     --resource-group myResourceGroup-dev \
     --template-file infra/examples/fullOrchestrationExample.bicep \
     --parameters @infra/examples/fullOrchestrationExample.parameters.json
   ```

## Next Steps

1. **Review** the modules and documentation
2. **Test** in a development environment
3. **Customize** parameters for your needs
4. **Deploy** to test/prod environments
5. **Integrate** into your CI/CD pipelines

## Migration Path

Existing users can:
1. Continue using PowerShell scripts directly
2. Gradually adopt Bicep modules
3. Mix and match (use modules for some steps, scripts for others)
4. Eventually migrate fully to Bicep-based deployments

## Files Changed

- **New Files** (9):
  - `infra/modules/ensureActiveCapacity.bicep`
  - `infra/modules/assignWorkspaceToDomain.bicep`
  - `infra/modules/createLakehouses.bicep`
  - `infra/modules/createPurviewCollection.bicep`
  - `infra/modules/registerFabricDatasource.bicep`
  - `infra/modules/triggerPurviewScan.bicep`
  - `infra/modules/connectLogAnalytics.bicep`
  - `infra/examples/fullOrchestrationExample.bicep`
  - `infra/examples/fullOrchestrationExample.parameters.json`

- **Modified Files** (1):
  - `infra/modules/README.md` (comprehensive documentation added)

## Compatibility

- **Backward Compatible**: Existing scripts continue to work unchanged
- **PowerShell Scripts**: Still the source of truth for logic
- **Bicep Modules**: Wrap scripts for IaC deployment
- **No Breaking Changes**: Purely additive functionality

## Questions?

See the comprehensive documentation in `infra/modules/README.md` for:
- Detailed parameter descriptions
- Output specifications
- Usage examples
- Troubleshooting guide
- Best practices

---

**Branch**: `feature/bicep-deployment-modules`  
**Base Branch**: `main`  
**Status**: Ready for review  
**Testing**: Recommended before merge
