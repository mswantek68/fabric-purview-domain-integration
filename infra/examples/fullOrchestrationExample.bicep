// Complete Fabric-Purview Integration Example
// This example demonstrates how to use all deployment script modules together
// to create a fully configured Fabric workspace with Purview integration

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Environment name (dev, test, prod)')
param environmentName string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the Fabric domain')
param domainName string

@description('Name of the Fabric workspace')
param workspaceName string

@description('Name of the Fabric capacity')
param fabricCapacityName string

@description('SKU for the Fabric capacity')
@allowed([
  'F2'
  'F4'
  'F8'
  'F16'
  'F32'
  'F64'
])
param fabricCapacitySku string = 'F2'

@description('Admin user principal names (comma-separated)')
param adminUPNs string

@description('Name of the Purview account')
param purviewAccountName string

@description('Lakehouse names to create (comma-separated)')
param lakehouseNames string = 'bronze,silver,gold'

@description('Enable Purview integration')
param enablePurview bool = true

@description('Enable Log Analytics connection (placeholder)')
param enableLogAnalytics bool = false

@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string = ''

@description('UTC timestamp for force update')
param utcValue string = utcNow()

// ============================================================================
// VARIABLES
// ============================================================================

var commonTags = {
  environment: environmentName
  project: 'fabric-purview-integration'
  managedBy: 'bicep'
}

// ============================================================================
// EXISTING RESOURCES
// ============================================================================

// Reference to existing Purview account (if enablePurview is true)
resource purviewAccount 'Microsoft.Purview/accounts@2021-07-01' existing = if (enablePurview) {
  name: purviewAccountName
}

// ============================================================================
// MANAGED IDENTITY
// ============================================================================

@description('User-assigned managed identity for deployment scripts')
resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-fabric-deployment-${environmentName}'
  location: location
  tags: commonTags
}

// Grant Contributor role to the identity (for resource management)
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deploymentIdentity.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// FABRIC CAPACITY
// ============================================================================

@description('Fabric capacity for the workspace')
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

// ============================================================================
// STEP 1: ENSURE CAPACITY IS ACTIVE
// ============================================================================

module ensureCapacity '../modules/fabric/ensureActiveCapacity.bicep' = {
  name: 'ensure-capacity-${utcValue}'
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
    contributorRoleAssignment
  ]
}

// ============================================================================
// STEP 2: CREATE FABRIC DOMAIN
// ============================================================================

module fabricDomain '../modules/fabric/fabricDomain.bicep' = {
  name: 'create-domain-${utcValue}'
  params: {
    domainName: domainName
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    ensureCapacity
  ]
}

// ============================================================================
// STEP 3: CREATE FABRIC WORKSPACE
// ============================================================================

module fabricWorkspace '../modules/fabric/fabricWorkspace.bicep' = {
  name: 'create-workspace-${utcValue}'
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
    ensureCapacity
  ]
}

// ============================================================================
// STEP 4: CREATE LAKEHOUSES
// ============================================================================

module lakehouses '../modules/fabric/createLakehouses.bicep' = {
  name: 'create-lakehouses-${utcValue}'
  params: {
    workspaceName: fabricWorkspace.outputs.workspaceName
    workspaceId: fabricWorkspace.outputs.workspaceId
    lakehouseNames: lakehouseNames
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    fabricWorkspace
  ]
}

// ============================================================================
// STEP 5: ASSIGN WORKSPACE TO DOMAIN
// ============================================================================

module assignDomain '../modules/fabric/assignWorkspaceToDomain.bicep' = {
  name: 'assign-domain-${utcValue}'
  params: {
    workspaceName: fabricWorkspace.outputs.workspaceName
    domainName: fabricDomain.outputs.domainName
    capacityId: fabricCapacity.id
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    fabricWorkspace
    fabricDomain
    lakehouses
  ]
}

// ============================================================================
// PURVIEW INTEGRATION (OPTIONAL)
// ============================================================================

// Step 6: Create Purview Collection
module purviewCollection '../modules/purview/createPurviewCollection.bicep' = if (enablePurview) {
  name: 'create-collection-${utcValue}'
  params: {
    purviewAccountName: purviewAccountName
    collectionName: domainName
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    fabricDomain
  ]
}

// Step 7: Register Fabric Datasource
module registerDatasource '../modules/purview/registerFabricDatasource.bicep' = if (enablePurview) {
  name: 'register-datasource-${utcValue}'
  params: {
    purviewAccountName: purviewAccountName
    collectionName: enablePurview ? purviewCollection.outputs.collectionName : ''
    workspaceId: fabricWorkspace.outputs.workspaceId
    workspaceName: fabricWorkspace.outputs.workspaceName
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    fabricWorkspace
    purviewCollection
  ]
}

// Step 8: Trigger Purview Scan
module triggerScan '../modules/purview/triggerPurviewScan.bicep' = if (enablePurview) {
  name: 'trigger-scan-${utcValue}'
  params: {
    purviewAccountName: purviewAccountName
    datasourceName: enablePurview ? registerDatasource.outputs.datasourceName : ''
    workspaceId: fabricWorkspace.outputs.workspaceId
    workspaceName: fabricWorkspace.outputs.workspaceName
    collectionId: enablePurview ? purviewCollection.outputs.collectionId : ''
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    registerDatasource
    lakehouses
  ]
}

// ============================================================================
// LOG ANALYTICS INTEGRATION (OPTIONAL/PLACEHOLDER)
// ============================================================================

module connectLogAnalytics '../modules/monitoring/connectLogAnalytics.bicep' = if (enableLogAnalytics) {
  name: 'connect-log-analytics-${utcValue}'
  params: {
    workspaceName: fabricWorkspace.outputs.workspaceName
    workspaceId: fabricWorkspace.outputs.workspaceId
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    location: location
    tags: commonTags
    userAssignedIdentityId: deploymentIdentity.id
    utcValue: utcValue
  }
  dependsOn: [
    fabricWorkspace
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The name of the Fabric domain')
output fabricDomainName string = fabricDomain.outputs.domainName

@description('The ID of the Fabric domain')
output fabricDomainId string = fabricDomain.outputs.domainId

@description('The name of the Fabric workspace')
output fabricWorkspaceName string = fabricWorkspace.outputs.workspaceName

@description('The ID of the Fabric workspace')
output fabricWorkspaceId string = fabricWorkspace.outputs.workspaceId

@description('The capacity ID assigned to the workspace')
output fabricCapacityId string = fabricCapacity.id

@description('The capacity state')
output capacityState string = ensureCapacity.outputs.capacityState

@description('Whether the capacity is active')
output capacityActive bool = ensureCapacity.outputs.capacityActive

@description('Number of lakehouses created')
output lakehousesCreated int = lakehouses.outputs.lakehousesCreated

@description('Lakehouse IDs (JSON)')
output lakehouseIds string = lakehouses.outputs.lakehouseIds

@description('Whether the domain assignment succeeded')
output domainAssigned bool = assignDomain.outputs.domainAssigned

@description('Purview collection name (if enabled)')
output purviewCollectionName string = enablePurview ? purviewCollection.outputs.collectionName : ''

@description('Purview collection ID (if enabled)')
output purviewCollectionId string = enablePurview ? purviewCollection.outputs.collectionId : ''

@description('Purview datasource name (if enabled)')
output purviewDatasourceName string = enablePurview ? registerDatasource.outputs.datasourceName : ''

@description('Whether Purview scan was triggered (if enabled)')
output purviewScanTriggered bool = enablePurview ? triggerScan.outputs.scanTriggered : false

@description('Purview scan status (if enabled)')
output purviewScanStatus string = enablePurview ? triggerScan.outputs.status : 'N/A'
