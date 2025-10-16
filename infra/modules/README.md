# Bicep Deployment Modules

This directory contains modular Bicep templates for deploying and configuring Microsoft Fabric and Azure Purview resources. Each module wraps an atomic operation as a deployment script, providing maximum flexibility for infrastructure-as-code deployments.

## Available Modules

### Core Infrastructure Modules

#### 1. **fabricDomain.bicep**
Creates a Microsoft Fabric domain using deployment scripts.

**Parameters:**
- `domainName` (required): Name of the Fabric domain to create
- `location`: Azure region for deployment (default: resource group location)
- `tags`: Tags to apply to resources
- `userAssignedIdentityId` (required): Managed Identity for script execution

**Outputs:**
- `domainId`: The ID of the created/existing domain
- `domainName`: The name of the domain

**Example:**
```bicep
module domain 'modules/fabricDomain.bicep' = {
  name: 'deployFabricDomain'
  params: {
    domainName: 'MyDataDomain'
    userAssignedIdentityId: managedIdentity.id
    tags: commonTags
  }
}
```

---

#### 2. **fabricWorkspace.bicep**
Creates a Microsoft Fabric workspace and assigns it to a capacity.

**Parameters:**
- `workspaceName` (required): Name of the Fabric workspace
- `capacityId` (required): ARM resource ID of the Fabric capacity
- `adminUPNs`: Comma-separated list of admin user principal names
- `location`: Azure region for deployment
- `tags`: Tags to apply to resources
- `userAssignedIdentityId` (required): Managed Identity for script execution

**Outputs:**
- `workspaceId`: The GUID of the created workspace
- `workspaceName`: The name of the workspace
- `capacityId`: The capacity GUID assigned to the workspace

**Example:**
```bicep
module workspace 'modules/fabricWorkspace.bicep' = {
  name: 'deployFabricWorkspace'
  params: {
    workspaceName: 'MyWorkspace'
    capacityId: fabricCapacity.id
    adminUPNs: 'admin@contoso.com,user@contoso.com'
    userAssignedIdentityId: managedIdentity.id
  }
}
```

---

### Operational Modules

#### 3. **ensureActiveCapacity.bicep**
Ensures a Fabric capacity is in Active state, attempting to resume if paused/suspended.

**Parameters:**
- `fabricCapacityId` (required): ARM resource ID of the Fabric capacity
- `fabricCapacityName` (required): Name of the Fabric capacity
- `resumeTimeoutSeconds`: Timeout for resume operation (default: 900)
- `pollIntervalSeconds`: Polling interval (default: 20)
- `location`: Azure region for deployment
- `tags`: Tags to apply to resources
- `userAssignedIdentityId` (required): Managed Identity for script execution

**Outputs:**
- `capacityState`: Current state of the capacity
- `capacityActive`: Boolean indicating if capacity is active

**Example:**
```bicep
module ensureCapacity 'modules/ensureActiveCapacity.bicep' = {
  name: 'ensureFabricCapacityActive'
  params: {
    fabricCapacityId: fabricCapacity.id
    fabricCapacityName: fabricCapacity.name
    userAssignedIdentityId: managedIdentity.id
  }
}
```

---

#### 4. **assignWorkspaceToDomain.bicep**
Assigns a Fabric workspace to a domain by capacity.

**Parameters:**
- `workspaceName` (required): Name of the Fabric workspace
- `domainName` (required): Name of the target domain
- `capacityId` (required): ARM resource ID of the Fabric capacity
- `location`: Azure region for deployment
- `tags`: Tags to apply to resources
- `userAssignedIdentityId` (required): Managed Identity for script execution

**Outputs:**
- `domainAssigned`: Boolean indicating success
- `domainId`: The domain object ID
- `workspaceId`: The workspace GUID

**Example:**
```bicep
module assignDomain 'modules/assignWorkspaceToDomain.bicep' = {
  name: 'assignWorkspaceToDomain'
  params: {
    workspaceName: workspace.outputs.workspaceName
    domainName: domain.outputs.domainName
    capacityId: fabricCapacity.id
    userAssignedIdentityId: managedIdentity.id
  }
  dependsOn: [
    workspace
    domain
  ]
}
```

---

#### 5. **createLakehouses.bicep**
Creates Fabric lakehouses (bronze, silver, gold) in a workspace.

**Parameters:**
- `workspaceName` (required): Name of the Fabric workspace
- `workspaceId` (required): GUID of the workspace
- `lakehouseNames`: Comma-separated list of lakehouse names (default: 'bronze,silver,gold')
- `location`: Azure region for deployment
- `tags`: Tags to apply to resources
- `userAssignedIdentityId` (required): Managed Identity for script execution

**Outputs:**
- `lakehousesCreated`: Number of lakehouses created
- `lakehousesSkipped`: Number already existing
- `lakehousesFailed`: Number that failed to create
- `lakehouseIds`: JSON string of lakehouse name-to-ID mappings

**Example:**
```bicep
module lakehouses 'modules/createLakehouses.bicep' = {
  name: 'createFabricLakehouses'
  params: {
    workspaceName: workspace.outputs.workspaceName
    workspaceId: workspace.outputs.workspaceId
    lakehouseNames: 'bronze,silver,gold,raw'
    userAssignedIdentityId: managedIdentity.id
  }
  dependsOn: [
    workspace
  ]
}
```

---

### Purview Integration Modules

#### 6. **createPurviewCollection.bicep**
Creates a collection in Azure Purview.

**Parameters:**
- `purviewAccountName` (required): Name of the Purview account
- `collectionName` (required): Name of the collection to create
- `location`: Azure region for deployment
- `tags`: Tags to apply to resources
- `userAssignedIdentityId` (required): Managed Identity for script execution

**Outputs:**
- `collectionId`: The ID of the created collection
- `collectionName`: The name of the collection

**Example:**
```bicep
module purviewCollection 'modules/createPurviewCollection.bicep' = {
  name: 'createPurviewCollection'
  params: {
    purviewAccountName: purview.name
    collectionName: 'FabricDataCollection'
    userAssignedIdentityId: managedIdentity.id
  }
}
```

---

#### 7. **registerFabricDatasource.bicep**
Registers a Fabric workspace as a datasource in Purview.

**Parameters:**
- `purviewAccountName` (required): Name of the Purview account
- `collectionName` (required): Target collection name
- `workspaceId` (required): Fabric workspace GUID
- `workspaceName` (required): Fabric workspace name
- `tenantId`: Azure AD tenant ID (default: subscription tenant)
- `location`: Azure region for deployment
- `tags`: Tags to apply to resources
- `userAssignedIdentityId` (required): Managed Identity for script execution

**Outputs:**
- `datasourceName`: Name of the registered datasource
- `collectionId`: Collection ID where datasource is registered

**Example:**
```bicep
module registerDatasource 'modules/registerFabricDatasource.bicep' = {
  name: 'registerFabricDatasource'
  params: {
    purviewAccountName: purview.name
    collectionName: purviewCollection.outputs.collectionName
    workspaceId: workspace.outputs.workspaceId
    workspaceName: workspace.outputs.workspaceName
    userAssignedIdentityId: managedIdentity.id
  }
  dependsOn: [
    workspace
    purviewCollection
  ]
}
```

---

#### 8. **triggerPurviewScan.bicep**
Creates and triggers a Purview scan for a Fabric workspace.

**Parameters:**
- `purviewAccountName` (required): Name of the Purview account
- `datasourceName` (required): Name of the registered datasource
- `workspaceId` (required): Fabric workspace GUID
- `workspaceName` (required): Fabric workspace name
- `collectionId`: Target collection ID (optional)
- `location`: Azure region for deployment
- `tags`: Tags to apply to resources
- `userAssignedIdentityId` (required): Managed Identity for script execution

**Outputs:**
- `scanCreated`: Boolean indicating scan definition created
- `scanTriggered`: Boolean indicating scan run triggered
- `runId`: The scan run ID (if available)
- `status`: Current status of the scan run

**Example:**
```bicep
module triggerScan 'modules/triggerPurviewScan.bicep' = {
  name: 'triggerPurviewScan'
  params: {
    purviewAccountName: purview.name
    datasourceName: registerDatasource.outputs.datasourceName
    workspaceId: workspace.outputs.workspaceId
    workspaceName: workspace.outputs.workspaceName
    collectionId: purviewCollection.outputs.collectionId
    userAssignedIdentityId: managedIdentity.id
  }
  dependsOn: [
    registerDatasource
  ]
}
```

---

#### 9. **connectLogAnalytics.bicep**
Placeholder module for connecting Fabric workspace to Log Analytics (API not yet available).

**Parameters:**
- `workspaceName` (required): Name of the Fabric workspace
- `workspaceId` (required): Fabric workspace GUID
- `logAnalyticsWorkspaceId`: Log Analytics workspace resource ID
- `location`: Azure region for deployment
- `tags`: Tags to apply to resources
- `userAssignedIdentityId` (required): Managed Identity for script execution

**Outputs:**
- `connected`: Boolean (always false - placeholder)
- `message`: Status message

**Example:**
```bicep
module connectLA 'modules/connectLogAnalytics.bicep' = {
  name: 'connectLogAnalytics'
  params: {
    workspaceName: workspace.outputs.workspaceName
    workspaceId: workspace.outputs.workspaceId
    logAnalyticsWorkspaceId: logAnalytics.id
    userAssignedIdentityId: managedIdentity.id
  }
}
```

---

## Prerequisites

All modules require:

1. **Managed Identity**: A user-assigned managed identity with appropriate permissions
2. **Azure CLI**: Installed in the deployment script execution environment
3. **Permissions**: The managed identity must have:
   - Fabric Administrator role (for Fabric operations)
   - Purview Data Curator role (for Purview operations)
   - Power BI Service Administrator (for workspace operations)

## Common Patterns

### Sequential Deployment
Many operations must be performed in sequence:

```bicep
// 1. Ensure capacity is active
module ensureCapacity 'modules/ensureActiveCapacity.bicep' = { ... }

// 2. Create workspace
module workspace 'modules/fabricWorkspace.bicep' = {
  dependsOn: [ensureCapacity]
  ...
}

// 3. Create lakehouses
module lakehouses 'modules/createLakehouses.bicep' = {
  dependsOn: [workspace]
  ...
}

// 4. Assign to domain
module assignDomain 'modules/assignWorkspaceToDomain.bicep' = {
  dependsOn: [workspace, lakehouses]
  ...
}
```

### Conditional Deployment
Skip modules based on conditions:

```bicep
param enablePurview bool = true

module purviewCollection 'modules/createPurviewCollection.bicep' = if (enablePurview) {
  ...
}
```

### Passing Outputs Between Modules
Chain modules using outputs:

```bicep
module workspace 'modules/fabricWorkspace.bicep' = { ... }

module lakehouses 'modules/createLakehouses.bicep' = {
  params: {
    workspaceId: workspace.outputs.workspaceId
    workspaceName: workspace.outputs.workspaceName
  }
}
```

## Troubleshooting

### Common Issues

1. **Capacity Not Active**: Ensure `ensureActiveCapacity` completes before workspace creation
2. **Permission Errors**: Verify managed identity has required Fabric Admin and Purview roles
3. **Timeout Errors**: Increase `timeout` in deployment script properties
4. **Token Acquisition Failures**: Ensure managed identity has correct resource permissions

### Debugging

View deployment script logs:
```bash
az deployment-scripts show-log \
  --resource-group <rg-name> \
  --name <script-name>
```

## Best Practices

1. **Use consistent naming**: Apply naming conventions across all resources
2. **Tag everything**: Use tags for cost tracking and resource management
3. **Handle failures gracefully**: Most modules handle existing resources idempotently
4. **Monitor deployments**: Review deployment script outputs and logs
5. **Test incrementally**: Deploy and test each module before chaining them

## See Also

- [Fabric REST API Documentation](https://learn.microsoft.com/rest/api/fabric)
- [Purview REST API Documentation](https://learn.microsoft.com/rest/api/purview)
- [Azure Deployment Scripts](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deployment-script-bicep)
- [Example Deployments](../examples/)
