# Bicep Module Execution Order and Dependencies

## Understanding Bicep Execution

### The Challenge
You're absolutely correct! In Bicep, **the order of module declarations does NOT determine execution order**. Bicep deploys resources in parallel by default for performance. This is great for speed but can cause issues when operations must run sequentially.

### The Solution: Explicit Dependencies

Bicep provides **two ways** to control execution order:

1. **Implicit Dependencies** - Bicep automatically detects when you use outputs
2. **Explicit Dependencies** - You manually specify using `dependsOn`

## How Deployment Script Modules Execute

Each deployment script module is a **blocking operation** that:
1. Creates a storage account
2. Runs the PowerShell script in a container
3. Waits for completion
4. Returns outputs

This means each module is **atomic** and **sequential within itself**, but multiple modules will run in parallel unless you control the order.

## Dependency Strategies

### Strategy 1: Output-Based Dependencies (Recommended)

When you use a module's output as another module's input, Bicep **automatically** creates a dependency.

```bicep
// Step 1: Create workspace
module workspace 'modules/fabricWorkspace.bicep' = {
  params: {
    workspaceName: 'MyWorkspace'
    capacityId: capacity.id
    userAssignedIdentityId: identity.id
  }
}

// Step 2: Create lakehouses (automatically waits for workspace)
module lakehouses 'modules/createLakehouses.bicep' = {
  params: {
    workspaceId: workspace.outputs.workspaceId      // ← Using output creates implicit dependency
    workspaceName: workspace.outputs.workspaceName  // ← Bicep knows to wait
    userAssignedIdentityId: identity.id
  }
}
```

**How it works:**
- Bicep sees `workspace.outputs.workspaceId`
- It knows it can't start `lakehouses` until `workspace` completes
- **No explicit `dependsOn` needed!**

### Strategy 2: Explicit dependsOn (When No Outputs Used)

Sometimes you need to wait but don't use outputs. Use `dependsOn`:

```bicep
// Step 1: Ensure capacity is active
module ensureCapacity 'modules/ensureActiveCapacity.bicep' = {
  params: {
    fabricCapacityId: capacity.id
    fabricCapacityName: capacity.name
    userAssignedIdentityId: identity.id
  }
}

// Step 2: Create workspace (must wait but doesn't use ensureCapacity outputs)
module workspace 'modules/fabricWorkspace.bicep' = {
  params: {
    workspaceName: 'MyWorkspace'
    capacityId: capacity.id
    userAssignedIdentityId: identity.id
  }
  dependsOn: [
    ensureCapacity  // ← Explicit: "Don't start until this completes"
  ]
}
```

### Strategy 3: Hybrid (Combine Both)

Most robust - use outputs AND explicit dependencies:

```bicep
module assignDomain 'modules/assignWorkspaceToDomain.bicep' = {
  params: {
    workspaceName: workspace.outputs.workspaceName   // ← Implicit dependency
    domainName: domain.outputs.domainName            // ← Implicit dependency
    capacityId: capacity.id
    userAssignedIdentityId: identity.id
  }
  dependsOn: [
    lakehouses  // ← Explicit: Also wait for lakehouses to complete
  ]
}
```

## The Correct Execution Order

Here's the proper sequence with dependency explanations:

```bicep
// ============================================================================
// PHASE 0: Prerequisites (Deploy First - No Dependencies)
// ============================================================================

resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-fabric-deployment'
  location: location
}

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: 'myCapacity'
  location: location
  sku: { name: 'F2', tier: 'Fabric' }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deploymentIdentity.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// PHASE 1: Ensure Capacity Active
// Reason: Workspace creation will fail if capacity is paused
// ============================================================================

module ensureCapacity 'modules/ensureActiveCapacity.bicep' = {
  name: 'ensure-capacity-${utcValue}'
  params: {
    fabricCapacityId: fabricCapacity.id
    fabricCapacityName: fabricCapacity.name
    userAssignedIdentityId: deploymentIdentity.id
  }
  dependsOn: [
    roleAssignment  // Wait for permissions to be applied
  ]
}

// ============================================================================
// PHASE 2: Create Domain and Workspace (Can Run in Parallel)
// Reason: These don't depend on each other
// ============================================================================

module fabricDomain 'modules/fabricDomain.bicep' = {
  name: 'create-domain-${utcValue}'
  params: {
    domainName: 'MyDomain'
    userAssignedIdentityId: deploymentIdentity.id
  }
  dependsOn: [
    ensureCapacity  // Must wait for capacity to be active
  ]
}

module fabricWorkspace 'modules/fabricWorkspace.bicep' = {
  name: 'create-workspace-${utcValue}'
  params: {
    workspaceName: 'MyWorkspace'
    capacityId: fabricCapacity.id
    userAssignedIdentityId: deploymentIdentity.id
  }
  dependsOn: [
    ensureCapacity  // Must wait for capacity to be active
  ]
}

// ============================================================================
// PHASE 3: Create Lakehouses
// Reason: Needs workspace to exist
// ============================================================================

module lakehouses 'modules/createLakehouses.bicep' = {
  name: 'create-lakehouses-${utcValue}'
  params: {
    workspaceId: fabricWorkspace.outputs.workspaceId      // Implicit dependency
    workspaceName: fabricWorkspace.outputs.workspaceName  // Implicit dependency
    lakehouseNames: 'bronze,silver,gold'
    userAssignedIdentityId: deploymentIdentity.id
  }
  // No explicit dependsOn needed - outputs create implicit dependency
}

// ============================================================================
// PHASE 4: Assign to Domain
// Reason: Workspace, domain, and lakehouses must all exist
// ============================================================================

module assignDomain 'modules/assignWorkspaceToDomain.bicep' = {
  name: 'assign-domain-${utcValue}'
  params: {
    workspaceName: fabricWorkspace.outputs.workspaceName  // Implicit dependency
    domainName: fabricDomain.outputs.domainName          // Implicit dependency
    capacityId: fabricCapacity.id
    userAssignedIdentityId: deploymentIdentity.id
  }
  dependsOn: [
    lakehouses  // Explicit: Wait for lakehouses too
  ]
}

// ============================================================================
// PHASE 5: Purview Integration (Sequential)
// Reason: Each step depends on the previous
// ============================================================================

module purviewCollection 'modules/createPurviewCollection.bicep' = {
  name: 'create-collection-${utcValue}'
  params: {
    purviewAccountName: 'myPurview'
    collectionName: fabricDomain.outputs.domainName  // Implicit dependency on domain
    userAssignedIdentityId: deploymentIdentity.id
  }
  dependsOn: [
    fabricDomain  // Explicit: Collection name comes from domain
  ]
}

module registerDatasource 'modules/registerFabricDatasource.bicep' = {
  name: 'register-datasource-${utcValue}'
  params: {
    purviewAccountName: 'myPurview'
    collectionName: purviewCollection.outputs.collectionName  // Implicit dependency
    workspaceId: fabricWorkspace.outputs.workspaceId          // Implicit dependency
    workspaceName: fabricWorkspace.outputs.workspaceName      // Implicit dependency
    userAssignedIdentityId: deploymentIdentity.id
  }
  dependsOn: [
    lakehouses  // Explicit: Wait for lakehouses to be registered
  ]
}

module triggerScan 'modules/triggerPurviewScan.bicep' = {
  name: 'trigger-scan-${utcValue}'
  params: {
    purviewAccountName: 'myPurview'
    datasourceName: registerDatasource.outputs.datasourceName  // Implicit dependency
    workspaceId: fabricWorkspace.outputs.workspaceId
    workspaceName: fabricWorkspace.outputs.workspaceName
    collectionId: purviewCollection.outputs.collectionId
    userAssignedIdentityId: deploymentIdentity.id
  }
  // No explicit dependsOn needed - outputs create complete dependency chain
}
```

## Visual Dependency Graph

```
deploymentIdentity ──┐
fabricCapacity ──────┤
roleAssignment ──────┴──→ ensureCapacity
                              │
                    ┌─────────┴─────────┐
                    ↓                   ↓
              fabricDomain      fabricWorkspace
                    │                   │
                    │                   ↓
                    │            lakehouses
                    │                   │
                    └─────────┬─────────┘
                              ↓
                      assignDomain
                              │
                              ↓
                    purviewCollection
                              │
                              ↓
                    registerDatasource
                              │
                              ↓
                       triggerScan
```

## Dependency Rules by Module

| Module | Must Wait For | Reason |
|--------|--------------|---------|
| `ensureActiveCapacity` | Role assignment | Needs permissions |
| `fabricDomain` | ensureCapacity | Needs active capacity |
| `fabricWorkspace` | ensureCapacity | Needs active capacity |
| `createLakehouses` | fabricWorkspace | Needs workspace ID |
| `assignWorkspaceToDomain` | workspace, domain, lakehouses | Needs all resources |
| `createPurviewCollection` | fabricDomain | Uses domain name |
| `registerFabricDatasource` | workspace, purviewCollection, lakehouses | Needs workspace and collection |
| `triggerPurviewScan` | registerDatasource | Needs datasource registered |

## Common Pitfalls and Solutions

### ❌ Pitfall 1: No Dependencies
```bicep
// WRONG - These will run in parallel!
module workspace 'modules/fabricWorkspace.bicep' = { ... }
module lakehouses 'modules/createLakehouses.bicep' = { ... }
// Lakehouses might start before workspace exists!
```

### ✅ Solution: Use Output Dependencies
```bicep
module workspace 'modules/fabricWorkspace.bicep' = { ... }
module lakehouses 'modules/createLakehouses.bicep' = {
  params: {
    workspaceId: workspace.outputs.workspaceId  // Creates dependency
  }
}
```

### ❌ Pitfall 2: Circular Dependencies
```bicep
// WRONG - Circular dependency!
module a 'moduleA.bicep' = {
  dependsOn: [b]
}
module b 'moduleB.bicep' = {
  dependsOn: [a]
}
```

### ✅ Solution: Linear Chain
```bicep
module a 'moduleA.bicep' = { ... }
module b 'moduleB.bicep' = {
  dependsOn: [a]  // B depends on A
}
module c 'moduleC.bicep' = {
  dependsOn: [b]  // C depends on B (and implicitly A)
}
```

### ❌ Pitfall 3: Missing Intermediate Dependencies
```bicep
// WRONG - Scan might run before datasource is registered
module registerDatasource 'modules/registerFabricDatasource.bicep' = { ... }
module triggerScan 'modules/triggerPurviewScan.bicep' = {
  params: {
    datasourceName: 'MyDatasource'  // Hardcoded - no dependency!
  }
}
```

### ✅ Solution: Use Outputs
```bicep
module registerDatasource 'modules/registerFabricDatasource.bicep' = { ... }
module triggerScan 'modules/triggerPurviewScan.bicep' = {
  params: {
    datasourceName: registerDatasource.outputs.datasourceName  // Creates dependency
  }
}
```

## Testing Execution Order

### View Deployment Timeline
```bash
# Deploy and watch the sequence
az deployment group create \
  --resource-group myResourceGroup \
  --template-file main.bicep \
  --parameters @params.json \
  --verbose

# View deployment operations in order
az deployment operation group list \
  --resource-group myResourceGroup \
  --name myDeployment \
  --query "[].{Resource:properties.targetResource.resourceName, Status:properties.provisioningState, Time:properties.timestamp}" \
  --output table
```

### Validate Dependency Graph
```bash
# Build the Bicep file to see dependency graph
az bicep build --file main.bicep --stdout | jq '.resources[] | {name: .name, dependsOn: .dependsOn}'
```

## Best Practices for Guaranteed Sequencing

1. **Always use outputs** when one module needs data from another
2. **Add explicit dependsOn** when outputs aren't enough
3. **Comment why** each dependency exists
4. **Test the order** by deploying to a dev environment
5. **Use unique names** with `utcValue` to force redeployment
6. **Monitor deployments** to verify sequence

## Complete Working Example

See `infra/examples/fullOrchestrationExample.bicep` which demonstrates:
- ✅ Proper dependency chains
- ✅ Output-based implicit dependencies
- ✅ Explicit `dependsOn` where needed
- ✅ Commented phases showing execution order
- ✅ Parallel execution where safe (domain + workspace)
- ✅ Sequential execution where required (Purview chain)

## Summary

**The order in the file DOES NOT matter. Dependencies DO.**

To guarantee sequential execution:
1. Use outputs as inputs (creates implicit dependencies)
2. Add `dependsOn` for additional constraints
3. Test the deployment to verify order
4. Document why each dependency exists

This ensures your atomic modules execute in the correct sequence every time! 🎯
