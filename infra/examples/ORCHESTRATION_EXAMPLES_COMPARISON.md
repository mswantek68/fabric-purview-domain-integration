# Orchestration Examples Comparison

This repository includes two comprehensive orchestration examples that demonstrate different approaches to deploying the Fabric-Purview integration stack.

## Overview

| Example | Best For | Documentation Level | Complexity |
|---------|----------|-------------------|------------|
| `fullOrchestrationExample.bicep` | General deployments | Moderate | Standard |
| `sequentialOrchestrationExample.bicep` | Learning dependencies | Extensive | Annotated |

## fullOrchestrationExample.bicep

**Purpose**: Production-ready deployment template with clean structure

**Characteristics**:
- ✅ **Concise**: Standard Bicep code without excessive comments
- ✅ **Production-focused**: Ready to use in CI/CD pipelines
- ✅ **Complete**: All features included (conditional Purview, phases, outputs)
- ✅ **Clean**: Follows typical Bicep formatting conventions

**When to use**:
- You understand Bicep dependency management
- You want a production-ready template
- You prefer clean, minimal comments
- You're deploying to dev/test/prod environments

**Example structure**:
```bicep
module ensureCapacity '../modules/ensureActiveCapacity.bicep' = {
  name: 'ensure-capacity-${utcValue}'
  params: {
    fabricCapacityId: fabricCapacity.id
    fabricCapacityName: fabricCapacity.name
    // ... other params
  }
  dependsOn: [contributorRole]
}
```

## sequentialOrchestrationExample.bicep

**Purpose**: Educational template with extensive inline documentation

**Characteristics**:
- 📚 **Heavily documented**: Every phase explains WHY it waits
- 📚 **Dependency annotations**: Explicit and implicit dependencies explained inline
- 📚 **Phase-labeled**: Clear phase numbers (Phase 0, 1, 2a, 2b, 3, 4, 5a, 5b, 5c)
- 📚 **Learning resource**: Perfect for understanding Bicep execution order
- 📚 **Verification commands**: Includes commands to verify deployment order

**When to use**:
- You're learning Bicep dependency management
- You want to understand WHY dependencies exist
- You need to explain deployment order to team members
- You're troubleshooting dependency issues

**Example structure**:
```bicep
// ============================================================================
// PHASE 1: ENSURE CAPACITY IS ACTIVE
// WHY: Workspace creation fails if capacity is paused/suspended
// WAITS FOR: Role assignment to complete (needs permissions)
// ============================================================================

module phase1_EnsureCapacity '../modules/ensureActiveCapacity.bicep' = {
  name: 'phase1-ensure-capacity-${utcValue}'
  params: {
    fabricCapacityId: fabricCapacity.id
    fabricCapacityName: fabricCapacity.name
    // ... other params
  }
  dependsOn: [
    contributorRole  // EXPLICIT: Must wait for permissions to propagate
  ]
}
```

## Key Differences

### 1. Documentation Density

**fullOrchestrationExample.bicep**:
- ~250 lines total
- Standard inline comments
- Minimal explanatory text

**sequentialOrchestrationExample.bicep**:
- ~320 lines total
- Heavy section headers with ASCII art
- Every dependency explained with WHY/WAITS FOR annotations
- Includes verification commands at the end

### 2. Module Naming

**fullOrchestrationExample.bicep**:
```bicep
module ensureCapacity '../modules/ensureActiveCapacity.bicep' = { ... }
module createDomain '../modules/fabricDomain.bicep' = { ... }
module createWorkspace '../modules/fabricWorkspace.bicep' = { ... }
```

**sequentialOrchestrationExample.bicep**:
```bicep
module phase1_EnsureCapacity '../modules/ensureActiveCapacity.bicep' = { ... }
module phase2a_CreateDomain '../modules/fabricDomain.bicep' = { ... }
module phase2b_CreateWorkspace '../modules/fabricWorkspace.bicep' = { ... }
```

### 3. Comment Style

**fullOrchestrationExample.bicep**:
```bicep
// Ensure capacity is active before proceeding
module ensureCapacity '../modules/ensureActiveCapacity.bicep' = {
  dependsOn: [contributorRole]
}
```

**sequentialOrchestrationExample.bicep**:
```bicep
// ============================================================================
// PHASE 1: ENSURE CAPACITY IS ACTIVE
// WHY: Workspace creation fails if capacity is paused/suspended
// WAITS FOR: Role assignment to complete (needs permissions)
// ============================================================================

module phase1_EnsureCapacity '../modules/ensureActiveCapacity.bicep' = {
  dependsOn: [
    contributorRole  // EXPLICIT: Must wait for permissions to propagate
  ]
}
```

### 4. Output Naming

**fullOrchestrationExample.bicep**:
```bicep
output capacityState string = ensureCapacity.outputs.capacityState
output domainId string = createDomain.outputs.domainId
output workspaceId string = createWorkspace.outputs.workspaceId
```

**sequentialOrchestrationExample.bicep**:
```bicep
output phase1_CapacityState string = phase1_EnsureCapacity.outputs.capacityState
output phase2a_DomainId string = phase2a_CreateDomain.outputs.domainId
output phase2b_WorkspaceId string = phase2b_CreateWorkspace.outputs.workspaceId
```

## Shared Features

Both examples include:

✅ **Complete deployment flow**
- Prerequisites (managed identity, capacity, RBAC)
- Capacity activation
- Domain and workspace creation
- Lakehouse creation
- Domain assignment
- Optional Purview integration

✅ **Conditional Purview**
- `enablePurview` parameter to toggle Purview integration
- Safe handling of conditional module outputs

✅ **Proper dependency management**
- Explicit `dependsOn` arrays where needed
- Implicit dependencies via output references
- Correct handling of parallel vs sequential phases

✅ **Comprehensive outputs**
- All resource IDs and names
- Status flags (capacity active, domain assigned, scan triggered)
- Phase-specific results

## Migration Path

If you start with `sequentialOrchestrationExample.bicep` for learning, you can easily migrate to `fullOrchestrationExample.bicep` for production:

1. **Keep**: All parameter values, module paths, dependency structure
2. **Remove**: Phase labels from module names (e.g., `phase1_` → ``)
3. **Remove**: Extensive section headers and WHY comments
4. **Keep**: All `dependsOn` arrays and output references (these are the same)

## Deployment Commands

Both examples use identical deployment commands:

```bash
# Using Azure CLI
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file infra/examples/fullOrchestrationExample.bicep \
  --parameters @infra/examples/fullOrchestrationExample.parameters.json

# Or with the sequential example
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file infra/examples/sequentialOrchestrationExample.bicep \
  --parameters @infra/examples/sequentialOrchestrationExample.parameters.json
```

## Recommendation

- **For learning**: Start with `sequentialOrchestrationExample.bicep` + `EXECUTION_ORDER_GUIDE.md`
- **For production**: Use `fullOrchestrationExample.bicep`
- **For CI/CD**: Use `fullOrchestrationExample.bicep`
- **For troubleshooting**: Reference `sequentialOrchestrationExample.bicep` to understand dependencies
- **For team training**: Use `sequentialOrchestrationExample.bicep` to teach Bicep execution order

## Verification

Both examples produce identical deployments. To verify:

```bash
# Deploy both to different resource groups
az deployment group create --resource-group rg-sequential --template-file sequentialOrchestrationExample.bicep --parameters @sequentialOrchestrationExample.parameters.json
az deployment group create --resource-group rg-full --template-file fullOrchestrationExample.bicep --parameters @fullOrchestrationExample.parameters.json

# Compare outputs (should be identical except for timestamps)
az deployment group show --resource-group rg-sequential --name sequentialOrchestrationExample --query properties.outputs
az deployment group show --resource-group rg-full --name fullOrchestrationExample --query properties.outputs
```

## Summary

Choose `sequentialOrchestrationExample.bicep` for **learning and documentation**.  
Choose `fullOrchestrationExample.bicep` for **production deployments**.

Both are functionally equivalent and deploy the exact same infrastructure with the same execution order guarantees.
