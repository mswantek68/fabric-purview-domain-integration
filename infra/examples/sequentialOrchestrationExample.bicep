// ============================================================================
// SEQUENTIAL DEPLOYMENT ORCHESTRATION
// ============================================================================
// This example demonstrates GUARANTEED SEQUENTIAL EXECUTION using Bicep's
// dependency management. Each phase is documented with WHY it must wait.
//
// Execution Flow:
//   Phase 0: Prerequisites (managed identity, capacity, permissions)
//   Phase 1: Ensure capacity is active
//   Phase 2: Create domain and workspace (parallel)
//   Phase 3: Create lakehouses (requires workspace)
//   Phase 4: Assign to domain (requires all above)
//   Phase 5: Purview integration (sequential chain)
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

param environmentName string = 'dev'
param location string = resourceGroup().location
param domainName string
param workspaceName string
param fabricCapacityName string
param fabricCapacitySku string = 'F2'
param adminUPNs string
param purviewAccountName string
param lakehouseNames string = 'bronze,silver,gold'
param enablePurview bool = true
param utcValue string = utcNow()

var commonTags = {
  environment: environmentName
  project: 'fabric-purview-sequential-deployment'
  managedBy: 'bicep'
}

// ============================================================================
// PHASE 0: PREREQUISITES
// These resources have no dependencies and deploy first
// ============================================================================

@description('Managed identity for deployment scripts - must exist before any scripts run')
resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-fabric-deployment-${environmentName}'
  location: location
  tags: commonTags
}

@description('Fabric capacity - must exist before workspace creation')
resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: fabricCapacityName
  location: location
  tags: commonTags
  sku: {
    name: fabricCapacitySku
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: split(adminUPNs, ',')
    }
  }
}

@description('Role assignment - must complete before identity can run scripts')
resource contributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deploymentIdentity.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// PHASE 1: ENSURE CAPACITY IS ACTIVE
// WHY: Workspace creation fails if capacity is paused/suspended
// WAITS FOR: Role assignment to complete (needs permissions)
// ============================================================================

module phase1_EnsureCapacity '../modules/fabric/ensureActiveCapacity.bicep' = {
  name: 'phase1-ensure-capacity-${utcValue}'
  params: {
    fabricCapacityId: fabricCapacity.id
    fabricCapacityName: fabricCapacity.name
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    resumeTimeoutSeconds: 900
    pollIntervalSeconds: 20
    utcValue: utcValue
  }
  dependsOn: [
    contributorRole  // EXPLICIT: Must wait for permissions to propagate
  ]
}

// ============================================================================
// PHASE 2A: CREATE FABRIC DOMAIN
// WHY: Domain should exist before workspace assignment
// WAITS FOR: Capacity to be active
// PARALLEL WITH: Workspace creation (they don't depend on each other)
// ============================================================================

module phase2a_CreateDomain '../modules/fabric/fabricDomain.bicep' = {
  name: 'phase2a-create-domain-${utcValue}'
  params: {
    domainName: domainName
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    phase1_EnsureCapacity  // EXPLICIT: Must wait for capacity to be active
  ]
}

// ============================================================================
// PHASE 2B: CREATE FABRIC WORKSPACE
// WHY: Lakehouses need a workspace to be created in
// WAITS FOR: Capacity to be active
// PARALLEL WITH: Domain creation (they don't depend on each other)
// ============================================================================

module phase2b_CreateWorkspace '../modules/fabric/fabricWorkspace.bicep' = {
  name: 'phase2b-create-workspace-${utcValue}'
  params: {
    workspaceName: workspaceName
    capacityId: fabricCapacity.id
    adminUPNs: adminUPNs
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    phase1_EnsureCapacity  // EXPLICIT: Must wait for capacity to be active
  ]
}

// ============================================================================
// PHASE 3: CREATE LAKEHOUSES
// WHY: Lakehouses must be created in an existing workspace
// WAITS FOR: Workspace creation to complete
// IMPLICIT DEPENDENCY: Uses workspace.outputs.workspaceId
// ============================================================================

module phase3_CreateLakehouses '../modules/fabric/createLakehouses.bicep' = {
  name: 'phase3-create-lakehouses-${utcValue}'
  params: {
    // IMPLICIT DEPENDENCIES: Using outputs automatically creates wait condition
    workspaceId: phase2b_CreateWorkspace.outputs.workspaceId
    workspaceName: phase2b_CreateWorkspace.outputs.workspaceName
    lakehouseNames: lakehouseNames
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  // NO EXPLICIT dependsOn NEEDED: Output usage creates implicit dependency
}

// ============================================================================
// PHASE 4: ASSIGN WORKSPACE TO DOMAIN
// WHY: Domain assignment requires workspace, domain, and lakehouses all exist
// WAITS FOR: Workspace, domain, and lakehouses
// COMBINES: Implicit dependencies (outputs) + explicit (lakehouses)
// ============================================================================

module phase4_AssignDomain '../modules/fabric/assignWorkspaceToDomain.bicep' = {
  name: 'phase4-assign-domain-${utcValue}'
  params: {
    // IMPLICIT DEPENDENCIES: Using outputs from previous phases
    workspaceName: phase2b_CreateWorkspace.outputs.workspaceName
    domainName: phase2a_CreateDomain.outputs.domainName
    capacityId: fabricCapacity.id
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    phase3_CreateLakehouses  // EXPLICIT: Wait for lakehouses before assigning domain
  ]
}

// ============================================================================
// PHASE 5A: CREATE PURVIEW COLLECTION (if enabled)
// WHY: Collection is needed before registering datasource
// WAITS FOR: Domain creation (uses domain name for collection)
// IMPLICIT DEPENDENCY: Uses domain.outputs.domainName
// ============================================================================

module phase5a_CreatePurviewCollection '../modules/purview/createPurviewCollection.bicep' = if (enablePurview) {
  name: 'phase5a-create-collection-${utcValue}'
  params: {
    purviewAccountName: purviewAccountName
    // IMPLICIT DEPENDENCY: Using domain output creates wait condition
    collectionName: phase2a_CreateDomain.outputs.domainName
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  // NO EXPLICIT dependsOn NEEDED: Output usage creates implicit dependency
}

// ============================================================================
// PHASE 5B: REGISTER FABRIC DATASOURCE (if enabled)
// WHY: Must register datasource before scanning
// WAITS FOR: Workspace, lakehouses, and Purview collection
// COMBINES: Multiple implicit dependencies from outputs
// ============================================================================

module phase5b_RegisterDatasource '../modules/purview/registerFabricDatasource.bicep' = if (enablePurview) {
  name: 'phase5b-register-datasource-${utcValue}'
  params: {
    purviewAccountName: purviewAccountName
    // IMPLICIT DEPENDENCIES: All these outputs create wait conditions
    // Safe access: phase5a only deploys when enablePurview is true
    collectionName: phase5a_CreatePurviewCollection.outputs!.collectionName
    workspaceId: phase2b_CreateWorkspace.outputs.workspaceId
    workspaceName: phase2b_CreateWorkspace.outputs.workspaceName
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    phase3_CreateLakehouses  // EXPLICIT: Wait for lakehouses to exist before registering
  ]
}

// ============================================================================
// PHASE 5C: TRIGGER PURVIEW SCAN (if enabled)
// WHY: Final step - scans the registered datasource
// WAITS FOR: Datasource registration
// IMPLICIT DEPENDENCY: Uses datasource output
// ============================================================================

module phase5c_TriggerScan '../modules/purview/triggerPurviewScan.bicep' = if (enablePurview) {
  name: 'phase5c-trigger-scan-${utcValue}'
  params: {
    purviewAccountName: purviewAccountName
    // IMPLICIT DEPENDENCIES: These outputs ensure proper wait sequence
    // Safe access: both phase5a and phase5b only deploy when enablePurview is true
    datasourceName: phase5b_RegisterDatasource.outputs!.datasourceName
    workspaceId: phase2b_CreateWorkspace.outputs.workspaceId
    workspaceName: phase2b_CreateWorkspace.outputs.workspaceName
    collectionId: phase5a_CreatePurviewCollection.outputs!.collectionId
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  // NO EXPLICIT dependsOn NEEDED: Output usage creates complete dependency chain
}

// ============================================================================
// OUTPUTS
// These outputs capture results from each phase for reference
// ============================================================================

// Phase 0 Outputs
output deploymentIdentityId string = deploymentIdentity.id
output fabricCapacityId string = fabricCapacity.id

// Phase 1 Outputs
output phase1_CapacityState string = phase1_EnsureCapacity.outputs.capacityState
output phase1_CapacityActive bool = phase1_EnsureCapacity.outputs.capacityActive

// Phase 2 Outputs
output phase2a_DomainId string = phase2a_CreateDomain.outputs.domainId
output phase2a_DomainName string = phase2a_CreateDomain.outputs.domainName
output phase2b_WorkspaceId string = phase2b_CreateWorkspace.outputs.workspaceId
output phase2b_WorkspaceName string = phase2b_CreateWorkspace.outputs.workspaceName

// Phase 3 Outputs
output phase3_LakehousesCreated int = phase3_CreateLakehouses.outputs.lakehousesCreated
output phase3_LakehouseIds string = phase3_CreateLakehouses.outputs.lakehouseIds

// Phase 4 Outputs
output phase4_DomainAssigned bool = phase4_AssignDomain.outputs.domainAssigned

// Phase 5 Outputs (if Purview enabled)
output phase5a_CollectionId string = enablePurview ? phase5a_CreatePurviewCollection.outputs!.collectionId : ''
output phase5b_DatasourceName string = enablePurview ? phase5b_RegisterDatasource.outputs!.datasourceName : ''
output phase5c_ScanTriggered bool = enablePurview ? phase5c_TriggerScan.outputs!.scanTriggered : false
output phase5c_ScanStatus string = enablePurview ? phase5c_TriggerScan.outputs!.status : 'N/A'

// ============================================================================
// DEPLOYMENT SUMMARY
// ============================================================================
// When this deployment completes, you can verify the execution order by:
//
// 1. View deployment operations timeline:
//    az deployment operation group list \
//      --resource-group <rg-name> \
//      --name <deployment-name> \
//      --query "[].{Resource:properties.targetResource.resourceName, Time:properties.timestamp}" \
//      --output table
//
// 2. Check deployment script logs for each phase:
//    az deployment-scripts show-log \
//      --resource-group <rg-name> \
//      --name phase1-ensure-capacity-<timestamp>
//
// 3. Review outputs to confirm completion:
//    az deployment group show \
//      --resource-group <rg-name> \
//      --name <deployment-name> \
//      --query properties.outputs
// ============================================================================
