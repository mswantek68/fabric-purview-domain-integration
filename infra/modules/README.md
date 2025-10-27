# Bicep Deployment Modules# Bicep Deployment Modules



This directory contains modular Bicep templates for deploying and configuring Microsoft Fabric, Azure Purview, and monitoring resources. Each module wraps an atomic operation as a deployment script, providing maximum flexibility for infrastructure-as-code deployments.This directory contains modular Bicep templates for deploying and configuring Microsoft Fabric and Azure Purview resources. Each module wraps an atomic operation as a deployment script, providing maximum flexibility for infrastructure-as-code deployments.



## 📁 Module Organization## Available Modules



Modules are organized into logical categories for better discoverability and maintainability:### Core Infrastructure Modules



```#### 1. **fabricDomain.bicep**

infra/modules/Creates a Microsoft Fabric domain using deployment scripts.

├── fabric/                    # Microsoft Fabric operations

│   ├── ensureActiveCapacity.bicep         # Ensure capacity is active**Parameters:**

│   ├── fabricDomain.bicep                 # Create Fabric domain- `domainName` (required): Name of the Fabric domain to create

│   ├── fabricWorkspace.bicep              # Create Fabric workspace- `location`: Azure region for deployment (default: resource group location)

│   ├── assignWorkspaceToDomain.bicep      # Assign workspace to domain- `tags`: Tags to apply to resources

│   └── createLakehouses.bicep             # Create lakehouses- `userAssignedIdentityId` (required): Managed Identity for script execution

├── purview/                   # Azure Purview governance operations

│   ├── createPurviewCollection.bicep      # Create Purview collection**Outputs:**

│   ├── registerFabricDatasource.bicep     # Register Fabric datasource- `domainId`: The ID of the created/existing domain

│   └── triggerPurviewScan.bicep           # Trigger Purview scan- `domainName`: The name of the domain

├── monitoring/                # Monitoring and observability

│   └── connectLogAnalytics.bicep          # Connect Log Analytics (placeholder)**Example:**

└── onelake-index/            # OneLake AI Search indexing (future)```bicep

```module domain 'modules/fabricDomain.bicep' = {

  name: 'deployFabricDomain'

## 🚀 Quick Start  params: {

    domainName: 'MyDataDomain'

### Using Individual Modules    userAssignedIdentityId: managedIdentity.id

    tags: commonTags

```bicep  }

// Reference modules from their organized folders}

module capacity 'modules/fabric/ensureActiveCapacity.bicep' = {```

  name: 'ensure-capacity'

  params: {---

    fabricCapacityId: capacityResource.id

    fabricCapacityName: capacityResource.name#### 2. **fabricWorkspace.bicep**

    userAssignedIdentityId: identity.idCreates a Microsoft Fabric workspace and assigns it to a capacity.

  }

}**Parameters:**

- `workspaceName` (required): Name of the Fabric workspace

module workspace 'modules/fabric/fabricWorkspace.bicep' = {- `capacityId` (required): ARM resource ID of the Fabric capacity

  name: 'create-workspace'- `adminUPNs`: Comma-separated list of admin user principal names

  params: {- `location`: Azure region for deployment

    workspaceName: 'MyWorkspace'- `tags`: Tags to apply to resources

    capacityId: capacityResource.id- `userAssignedIdentityId` (required): Managed Identity for script execution

    userAssignedIdentityId: identity.id

  }**Outputs:**

  dependsOn: [capacity]- `workspaceId`: The GUID of the created workspace

}- `workspaceName`: The name of the workspace

- `capacityId`: The capacity GUID assigned to the workspace

module collection 'modules/purview/createPurviewCollection.bicep' = {

  name: 'create-collection'**Example:**

  params: {```bicep

    purviewAccountName: 'myPurviewAccount'module workspace 'modules/fabricWorkspace.bicep' = {

    collectionName: 'MyCollection'  name: 'deployFabricWorkspace'

    userAssignedIdentityId: identity.id  params: {

  }    workspaceName: 'MyWorkspace'

}    capacityId: fabricCapacity.id

```    adminUPNs: 'admin@contoso.com,user@contoso.com'

    userAssignedIdentityId: managedIdentity.id

### Complete Orchestration Examples  }

}

See the [`examples/`](../examples/) folder for complete end-to-end orchestration templates:```



- **`fullOrchestrationExample.bicep`** - Production-ready template with clean structure---

- **`sequentialOrchestrationExample.bicep`** - Heavily documented educational template with execution order details

- **`ORCHESTRATION_EXAMPLES_COMPARISON.md`** - Comparison guide to choose the right template### Operational Modules



---#### 3. **ensureActiveCapacity.bicep**

Ensures a Fabric capacity is in Active state, attempting to resume if paused/suspended.

## 📦 Fabric Modules (`fabric/`)

**Parameters:**

### 1. **ensureActiveCapacity.bicep**- `fabricCapacityId` (required): ARM resource ID of the Fabric capacity

Ensures that a Fabric capacity is in the Active state before proceeding with workspace operations. Attempts to resume the capacity if it's paused or suspended.- `fabricCapacityName` (required): Name of the Fabric capacity

- `resumeTimeoutSeconds`: Timeout for resume operation (default: 900)

**Module Path:** `modules/fabric/ensureActiveCapacity.bicep`- `pollIntervalSeconds`: Polling interval (default: 20)

- `location`: Azure region for deployment

**Parameters:**- `tags`: Tags to apply to resources

- `fabricCapacityId` (required): ARM resource ID of the Fabric capacity- `userAssignedIdentityId` (required): Managed Identity for script execution

- `fabricCapacityName` (required): Name of the Fabric capacity

- `resumeTimeoutSeconds`: Maximum time to wait for resume operation (default: 900)**Outputs:**

- `pollIntervalSeconds`: Interval between status checks (default: 20)- `capacityState`: Current state of the capacity

- `location`: Azure region for deployment- `capacityActive`: Boolean indicating if capacity is active

- `tags`: Tags to apply to resources

- `userAssignedIdentityId` (required): Managed Identity for script execution**Example:**

- `utcValue`: Force update timestamp```bicep

module ensureCapacity 'modules/ensureActiveCapacity.bicep' = {

**Outputs:**  name: 'ensureFabricCapacityActive'

- `capacityState`: Current state of the capacity (Active, Paused, Suspended, etc.)  params: {

- `capacityActive`: Boolean indicating if capacity is active    fabricCapacityId: fabricCapacity.id

    fabricCapacityName: fabricCapacity.name

**Example:**    userAssignedIdentityId: managedIdentity.id

```bicep  }

module ensureCapacity 'modules/fabric/ensureActiveCapacity.bicep' = {}

  name: 'ensure-capacity-active'```

  params: {

    fabricCapacityId: fabricCapacity.id---

    fabricCapacityName: fabricCapacity.name

    userAssignedIdentityId: deploymentIdentity.id#### 4. **assignWorkspaceToDomain.bicep**

    resumeTimeoutSeconds: 600Assigns a Fabric workspace to a domain by capacity.

  }

}**Parameters:**

```- `workspaceName` (required): Name of the Fabric workspace

- `domainName` (required): Name of the target domain

---- `capacityId` (required): ARM resource ID of the Fabric capacity

- `location`: Azure region for deployment

### 2. **fabricDomain.bicep**- `tags`: Tags to apply to resources

Creates a Microsoft Fabric domain using deployment scripts.- `userAssignedIdentityId` (required): Managed Identity for script execution



**Module Path:** `modules/fabric/fabricDomain.bicep`**Outputs:**

- `domainAssigned`: Boolean indicating success

**Parameters:**- `domainId`: The domain object ID

- `domainName` (required): Name of the Fabric domain to create- `workspaceId`: The workspace GUID

- `location`: Azure region for deployment

- `tags`: Tags to apply to resources**Example:**

- `userAssignedIdentityId` (required): Managed Identity for script execution```bicep

- `utcValue`: Force update timestampmodule assignDomain 'modules/assignWorkspaceToDomain.bicep' = {

  name: 'assignWorkspaceToDomain'

**Outputs:**  params: {

- `domainId`: The GUID of the created/existing domain    workspaceName: workspace.outputs.workspaceName

- `domainName`: The name of the domain    domainName: domain.outputs.domainName

    capacityId: fabricCapacity.id

**Example:**    userAssignedIdentityId: managedIdentity.id

```bicep  }

module domain 'modules/fabric/fabricDomain.bicep' = {  dependsOn: [

  name: 'create-fabric-domain'    workspace

  params: {    domain

    domainName: 'DataGovernanceDomain'  ]

    userAssignedIdentityId: deploymentIdentity.id}

    tags: commonTags```

  }

}---

```

#### 5. **createLakehouses.bicep**

---Creates Fabric lakehouses (bronze, silver, gold) in a workspace.



### 3. **fabricWorkspace.bicep****Parameters:**

Creates a Microsoft Fabric workspace and assigns it to a capacity.- `workspaceName` (required): Name of the Fabric workspace

- `workspaceId` (required): GUID of the workspace

**Module Path:** `modules/fabric/fabricWorkspace.bicep`- `lakehouseNames`: Comma-separated list of lakehouse names (default: 'bronze,silver,gold')

- `location`: Azure region for deployment

**Parameters:**- `tags`: Tags to apply to resources

- `workspaceName` (required): Name of the Fabric workspace- `userAssignedIdentityId` (required): Managed Identity for script execution

- `capacityId` (required): ARM resource ID of the Fabric capacity

- `adminUPNs`: Comma-separated list of admin user principal names**Outputs:**

- `location`: Azure region for deployment- `lakehousesCreated`: Number of lakehouses created

- `tags`: Tags to apply to resources- `lakehousesSkipped`: Number already existing

- `userAssignedIdentityId` (required): Managed Identity for script execution- `lakehousesFailed`: Number that failed to create

- `utcValue`: Force update timestamp- `lakehouseIds`: JSON string of lakehouse name-to-ID mappings



**Outputs:****Example:**

- `workspaceId`: The GUID of the created workspace```bicep

- `workspaceName`: The name of the workspacemodule lakehouses 'modules/createLakehouses.bicep' = {

- `capacityId`: The capacity GUID assigned to the workspace  name: 'createFabricLakehouses'

  params: {

**Example:**    workspaceName: workspace.outputs.workspaceName

```bicep    workspaceId: workspace.outputs.workspaceId

module workspace 'modules/fabric/fabricWorkspace.bicep' = {    lakehouseNames: 'bronze,silver,gold,raw'

  name: 'create-fabric-workspace'    userAssignedIdentityId: managedIdentity.id

  params: {  }

    workspaceName: 'AnalyticsWorkspace'  dependsOn: [

    capacityId: fabricCapacity.id    workspace

    adminUPNs: 'admin1@contoso.com,admin2@contoso.com'  ]

    userAssignedIdentityId: deploymentIdentity.id}

  }```

}

```---



---### Purview Integration Modules



### 4. **assignWorkspaceToDomain.bicep**#### 6. **createPurviewCollection.bicep**

Assigns a Fabric workspace to a domain by resolving the capacity ID and making the appropriate API calls.Creates a collection in Azure Purview.



**Module Path:** `modules/fabric/assignWorkspaceToDomain.bicep`**Parameters:**

- `purviewAccountName` (required): Name of the Purview account

**Parameters:**- `collectionName` (required): Name of the collection to create

- `workspaceName` (required): Name of the workspace to assign- `location`: Azure region for deployment

- `domainName` (required): Name of the target domain- `tags`: Tags to apply to resources

- `capacityId` (required): ARM resource ID of the Fabric capacity- `userAssignedIdentityId` (required): Managed Identity for script execution

- `location`: Azure region for deployment

- `tags`: Tags to apply to resources**Outputs:**

- `userAssignedIdentityId` (required): Managed Identity for script execution- `collectionId`: The ID of the created collection

- `utcValue`: Force update timestamp- `collectionName`: The name of the collection



**Outputs:****Example:**

- `workspaceName`: Name of the assigned workspace```bicep

- `domainName`: Name of the domainmodule purviewCollection 'modules/createPurviewCollection.bicep' = {

- `domainAssigned`: Boolean indicating success  name: 'createPurviewCollection'

  params: {

**Example:**    purviewAccountName: purview.name

```bicep    collectionName: 'FabricDataCollection'

module assignDomain 'modules/fabric/assignWorkspaceToDomain.bicep' = {    userAssignedIdentityId: managedIdentity.id

  name: 'assign-workspace-to-domain'  }

  params: {}

    workspaceName: workspace.outputs.workspaceName```

    domainName: domain.outputs.domainName

    capacityId: fabricCapacity.id---

    userAssignedIdentityId: deploymentIdentity.id

  }#### 7. **registerFabricDatasource.bicep**

  dependsOn: [workspace, domain]Registers a Fabric workspace as a datasource in Purview.

}

```**Parameters:**

- `purviewAccountName` (required): Name of the Purview account

---- `collectionName` (required): Target collection name

- `workspaceId` (required): Fabric workspace GUID

### 5. **createLakehouses.bicep**- `workspaceName` (required): Fabric workspace name

Creates bronze, silver, and gold lakehouses in a Fabric workspace.- `tenantId`: Azure AD tenant ID (default: subscription tenant)

- `location`: Azure region for deployment

**Module Path:** `modules/fabric/createLakehouses.bicep`- `tags`: Tags to apply to resources

- `userAssignedIdentityId` (required): Managed Identity for script execution

**Parameters:**

- `workspaceId` (required): GUID of the Fabric workspace**Outputs:**

- `workspaceName` (required): Name of the Fabric workspace- `datasourceName`: Name of the registered datasource

- `lakehouseNames`: Comma-separated lakehouse names (default: 'bronze,silver,gold')- `collectionId`: Collection ID where datasource is registered

- `location`: Azure region for deployment

- `tags`: Tags to apply to resources**Example:**

- `userAssignedIdentityId` (required): Managed Identity for script execution```bicep

- `utcValue`: Force update timestampmodule registerDatasource 'modules/registerFabricDatasource.bicep' = {

  name: 'registerFabricDatasource'

**Outputs:**  params: {

- `lakehousesCreated`: Count of lakehouses created    purviewAccountName: purview.name

- `lakehouseIds`: JSON string with lakehouse IDs/names    collectionName: purviewCollection.outputs.collectionName

    workspaceId: workspace.outputs.workspaceId

**Example:**    workspaceName: workspace.outputs.workspaceName

```bicep    userAssignedIdentityId: managedIdentity.id

module lakehouses 'modules/fabric/createLakehouses.bicep' = {  }

  name: 'create-lakehouses'  dependsOn: [

  params: {    workspace

    workspaceId: workspace.outputs.workspaceId    purviewCollection

    workspaceName: workspace.outputs.workspaceName  ]

    lakehouseNames: 'bronze,silver,gold,platinum'}

    userAssignedIdentityId: deploymentIdentity.id```

  }

}---

```

#### 8. **triggerPurviewScan.bicep**

---Creates and triggers a Purview scan for a Fabric workspace.



## 🏛️ Purview Modules (`purview/`)**Parameters:**

- `purviewAccountName` (required): Name of the Purview account

### 6. **createPurviewCollection.bicep**- `datasourceName` (required): Name of the registered datasource

Creates a collection in Azure Purview under the default root collection.- `workspaceId` (required): Fabric workspace GUID

- `workspaceName` (required): Fabric workspace name

**Module Path:** `modules/purview/createPurviewCollection.bicep`- `collectionId`: Target collection ID (optional)

- `location`: Azure region for deployment

**Parameters:**- `tags`: Tags to apply to resources

- `purviewAccountName` (required): Name of the Purview account- `userAssignedIdentityId` (required): Managed Identity for script execution

- `collectionName` (required): Friendly name for the collection

- `parentCollectionName`: Parent collection (default: root collection)**Outputs:**

- `location`: Azure region for deployment- `scanCreated`: Boolean indicating scan definition created

- `tags`: Tags to apply to resources- `scanTriggered`: Boolean indicating scan run triggered

- `userAssignedIdentityId` (required): Managed Identity for script execution- `runId`: The scan run ID (if available)

- `utcValue`: Force update timestamp- `status`: Current status of the scan run



**Outputs:****Example:**

- `collectionName`: Friendly name of the collection```bicep

- `collectionId`: Full collection ID (friendly name)module triggerScan 'modules/triggerPurviewScan.bicep' = {

- `parentCollectionName`: Parent collection name  name: 'triggerPurviewScan'

  params: {

**Example:**    purviewAccountName: purview.name

```bicep    datasourceName: registerDatasource.outputs.datasourceName

module purviewCollection 'modules/purview/createPurviewCollection.bicep' = {    workspaceId: workspace.outputs.workspaceId

  name: 'create-purview-collection'    workspaceName: workspace.outputs.workspaceName

  params: {    collectionId: purviewCollection.outputs.collectionId

    purviewAccountName: 'myPurviewAccount'    userAssignedIdentityId: managedIdentity.id

    collectionName: domain.outputs.domainName  }

    userAssignedIdentityId: deploymentIdentity.id  dependsOn: [

  }    registerDatasource

}  ]

```}

```

---

---

### 7. **registerFabricDatasource.bicep**

Registers a Fabric workspace as a datasource in Azure Purview for governance and scanning.#### 9. **connectLogAnalytics.bicep**

Placeholder module for connecting Fabric workspace to Log Analytics (API not yet available).

**Module Path:** `modules/purview/registerFabricDatasource.bicep`

**Parameters:**

**Parameters:**- `workspaceName` (required): Name of the Fabric workspace

- `purviewAccountName` (required): Name of the Purview account- `workspaceId` (required): Fabric workspace GUID

- `collectionName` (required): Purview collection for the datasource- `logAnalyticsWorkspaceId`: Log Analytics workspace resource ID

- `workspaceId` (required): GUID of the Fabric workspace- `location`: Azure region for deployment

- `workspaceName` (required): Name of the Fabric workspace- `tags`: Tags to apply to resources

- `datasourceName`: Override datasource name (default: workspace name)- `userAssignedIdentityId` (required): Managed Identity for script execution

- `location`: Azure region for deployment

- `tags`: Tags to apply to resources**Outputs:**

- `userAssignedIdentityId` (required): Managed Identity for script execution- `connected`: Boolean (always false - placeholder)

- `utcValue`: Force update timestamp- `message`: Status message



**Outputs:****Example:**

- `datasourceName`: Name of the registered datasource```bicep

- `workspaceId`: Fabric workspace GUIDmodule connectLA 'modules/connectLogAnalytics.bicep' = {

- `collectionName`: Associated Purview collection  name: 'connectLogAnalytics'

  params: {

**Example:**    workspaceName: workspace.outputs.workspaceName

```bicep    workspaceId: workspace.outputs.workspaceId

module registerDatasource 'modules/purview/registerFabricDatasource.bicep' = {    logAnalyticsWorkspaceId: logAnalytics.id

  name: 'register-fabric-datasource'    userAssignedIdentityId: managedIdentity.id

  params: {  }

    purviewAccountName: 'myPurviewAccount'}

    collectionName: purviewCollection.outputs.collectionName```

    workspaceId: workspace.outputs.workspaceId

    workspaceName: workspace.outputs.workspaceName---

    userAssignedIdentityId: deploymentIdentity.id

  }## Prerequisites

}

```All modules require:



---1. **Managed Identity**: A user-assigned managed identity with appropriate permissions

2. **Azure CLI**: Installed in the deployment script execution environment

### 8. **triggerPurviewScan.bicep**3. **Permissions**: The managed identity must have:

Creates and triggers a Purview scan for a registered Fabric datasource, with status polling.   - Fabric Administrator role (for Fabric operations)

   - Purview Data Curator role (for Purview operations)

**Module Path:** `modules/purview/triggerPurviewScan.bicep`   - Power BI Service Administrator (for workspace operations)



**Parameters:**## Common Patterns

- `purviewAccountName` (required): Name of the Purview account

- `datasourceName` (required): Name of the registered datasource### Sequential Deployment

- `workspaceId` (required): Fabric workspace GUIDMany operations must be performed in sequence:

- `workspaceName`: Workspace name for scan naming

- `collectionId`: Collection ID for scan association```bicep

- `scanName`: Override scan name// 1. Ensure capacity is active

- `maxPollAttempts`: Maximum poll attempts (default: 60)module ensureCapacity 'modules/ensureActiveCapacity.bicep' = { ... }

- `pollIntervalSeconds`: Seconds between polls (default: 10)

- `location`: Azure region for deployment// 2. Create workspace

- `tags`: Tags to apply to resourcesmodule workspace 'modules/fabricWorkspace.bicep' = {

- `userAssignedIdentityId` (required): Managed Identity for script execution  dependsOn: [ensureCapacity]

- `utcValue`: Force update timestamp  ...

}

**Outputs:**

- `scanName`: Name of the scan// 3. Create lakehouses

- `scanTriggered`: Boolean indicating if scan was triggeredmodule lakehouses 'modules/createLakehouses.bicep' = {

- `status`: Final scan status  dependsOn: [workspace]

- `workspaceId`: Associated workspace GUID  ...

}

**Example:**

```bicep// 4. Assign to domain

module triggerScan 'modules/purview/triggerPurviewScan.bicep' = {module assignDomain 'modules/assignWorkspaceToDomain.bicep' = {

  name: 'trigger-purview-scan'  dependsOn: [workspace, lakehouses]

  params: {  ...

    purviewAccountName: 'myPurviewAccount'}

    datasourceName: registerDatasource.outputs.datasourceName```

    workspaceId: workspace.outputs.workspaceId

    collectionId: purviewCollection.outputs.collectionId### Conditional Deployment

    userAssignedIdentityId: deploymentIdentity.idSkip modules based on conditions:

  }

}```bicep

```param enablePurview bool = true



---module purviewCollection 'modules/createPurviewCollection.bicep' = if (enablePurview) {

  ...

## 📊 Monitoring Modules (`monitoring/`)}

```

### 9. **connectLogAnalytics.bicep**

Placeholder module for connecting a Log Analytics workspace to Fabric resources. Currently returns a placeholder response as the public API is not yet available.### Passing Outputs Between Modules

Chain modules using outputs:

**Module Path:** `modules/monitoring/connectLogAnalytics.bicep`

```bicep

**Parameters:**module workspace 'modules/fabricWorkspace.bicep' = { ... }

- `workspaceName` (required): Fabric workspace name

- `workspaceId` (required): Fabric workspace GUIDmodule lakehouses 'modules/createLakehouses.bicep' = {

- `logAnalyticsWorkspaceId`: Log Analytics resource ID  params: {

- `location`: Azure region for deployment    workspaceId: workspace.outputs.workspaceId

- `tags`: Tags to apply to resources    workspaceName: workspace.outputs.workspaceName

- `userAssignedIdentityId` (required): Managed Identity for script execution  }

- `utcValue`: Force update timestamp}

```

**Outputs:**

- `workspaceName`: Fabric workspace name## Troubleshooting

- `connected`: Always false (placeholder)

- `message`: Informational message### Common Issues



**Example:**1. **Capacity Not Active**: Ensure `ensureActiveCapacity` completes before workspace creation

```bicep2. **Permission Errors**: Verify managed identity has required Fabric Admin and Purview roles

module logAnalytics 'modules/monitoring/connectLogAnalytics.bicep' = {3. **Timeout Errors**: Increase `timeout` in deployment script properties

  name: 'connect-log-analytics'4. **Token Acquisition Failures**: Ensure managed identity has correct resource permissions

  params: {

    workspaceName: workspace.outputs.workspaceName### Debugging

    workspaceId: workspace.outputs.workspaceId

    logAnalyticsWorkspaceId: logAnalyticsWorkspace.idView deployment script logs:

    userAssignedIdentityId: deploymentIdentity.id```bash

  }az deployment-scripts show-log \

}  --resource-group <rg-name> \

```  --name <script-name>

```

---

## Best Practices

## 🔍 OneLake Index Modules (`onelake-index/`)

1. **Use consistent naming**: Apply naming conventions across all resources

_Coming soon: Bicep modules for Azure AI Search OneLake indexing operations_2. **Tag everything**: Use tags for cost tracking and resource management

3. **Handle failures gracefully**: Most modules handle existing resources idempotently

These modules will wrap the PowerShell scripts found in `scripts/OneLakeIndex/`:4. **Monitor deployments**: Review deployment script outputs and logs

- Setup RBAC for AI Search5. **Test incrementally**: Deploy and test each module before chaining them

- Create OneLake skillsets

- Create OneLake index## See Also

- Create OneLake datasource

- Create and configure OneLake indexer- [Fabric REST API Documentation](https://learn.microsoft.com/rest/api/fabric)

- Setup AI Foundry search RBAC- [Purview REST API Documentation](https://learn.microsoft.com/rest/api/purview)

- Automate AI Foundry connections- [Azure Deployment Scripts](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-script-bicep)

- [Example Deployments](../examples/)

---

## 🔗 Dependencies and Prerequisites

All modules require:

1. **User-Assigned Managed Identity** with appropriate permissions:
   - **Fabric Admin** role for Fabric operations
   - **Power BI Service Administrator** for domain/workspace management
   - **Purview Data Curator** for Purview operations
   - **Contributor** on the resource group for Azure resource management

2. **Azure CLI** and PowerShell installed in deployment scripts (automatically provided)

3. **Authentication context** configured for the managed identity

## 🏗️ Module Design Patterns

### Idempotency
All modules are designed to be idempotent - safe to run multiple times. They check for existing resources before creating new ones.

### Error Handling
Modules include comprehensive error handling with:
- Try-catch blocks for API failures
- Retry logic for transient errors
- Fallback mechanisms where applicable
- Detailed error messages in deployment logs

### Output Chaining
Modules expose outputs that can be consumed by dependent modules, enabling implicit dependency management:

```bicep
module workspace 'modules/fabric/fabricWorkspace.bicep' = { ... }

module lakehouses 'modules/fabric/createLakehouses.bicep' = {
  params: {
    workspaceId: workspace.outputs.workspaceId  // Implicit dependency
    workspaceName: workspace.outputs.workspaceName
  }
}
```

### Force Updates
All modules accept a `utcValue` parameter (set to `utcNow()` by default) to force re-execution of deployment scripts even when parameters haven't changed.

---

## 📖 Additional Documentation

- **[EXECUTION_ORDER_GUIDE.md](../../EXECUTION_ORDER_GUIDE.md)** - Understanding Bicep execution order and dependency management
- **[ORCHESTRATION_EXAMPLES_COMPARISON.md](../examples/ORCHESTRATION_EXAMPLES_COMPARISON.md)** - Choosing between example templates
- **[MIGRATION_GUIDE.md](../../MIGRATION_GUIDE.md)** - Migrating from PowerShell scripts to Bicep modules
- **[BICEP_MODULES_SUMMARY.md](../../BICEP_MODULES_SUMMARY.md)** - High-level feature overview
- **[BICEP_MODULES_QUICK_REFERENCE.md](../../BICEP_MODULES_QUICK_REFERENCE.md)** - Quick parameter reference

---

## 🤝 Contributing

When adding new modules:

1. Place them in the appropriate category folder (`fabric/`, `purview/`, `monitoring/`, or `onelake-index/`)
2. Follow the existing naming conventions
3. Include comprehensive parameter documentation
4. Provide example usage
5. Ensure idempotent behavior
6. Update this README with module details

---

## 📝 License

This project follows the license specified in the repository root.
