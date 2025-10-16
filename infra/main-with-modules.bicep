/*
=============================================================================
FABRIC-PURVIEW DOMAIN INTEGRATION - BICEP MODULE ORCHESTRATION
=============================================================================

This orchestration file replaces the post-provisioning shell scripts with
Bicep deployment script modules for a fully declarative infrastructure.

Deployment Order:
1. Fabric Capacity (AVM module)
2. Managed Identity (for deployment scripts)
3. RBAC role assignments
4. Shared Storage Account (for all deployment scripts)
4. Fabric Domain creation
   ↓
5. Fabric Workspace creation + Attach to Capacity (atomic operation)
   ↓
6. Ensure Capacity is Active (required before domain assignment)
   ↓
7. Assign Workspaces (by Capacity) to Domain (bulk operation)
   ↓
8. Create Lakehouses (bronze, silver, gold)
10. Purview Collection creation
11. Register Fabric as Purview datasource
12. Trigger Purview scan (optional)
13. Log Analytics connection (optional)

RBAC Requirements:
- Managed Identity needs Fabric Admin permissions
- Managed Identity needs Purview Data Curator permissions
- See main.bicep header for full RBAC requirements
*/

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Tags to apply to all resources')
param tags object = {}

@description('UTC timestamp for forcing deployment script updates')
param utcValue string = utcNow()

// Fabric Capacity Parameters
@description('Fabric Capacity name. Cannot have dashes or underscores!')
param fabricCapacityName string

@description('Fabric capacity SKU (F-series)')
@allowed([
  'F2'
  'F4'
  'F8'
  'F16'
  'F32'
  'F64'
  'F128'
  'F256'
  'F512'
  'F1024'
  'F2048'
])
param fabricCapacitySKU string

@description('Admin principal UPNs or objectIds to assign to the capacity')
param capacityAdminMembers array

// Fabric Workspace and Domain
@description('Fabric workspace display name')
param fabricWorkspaceName string

@description('Fabric Data Domain name (governance domain)')
param domainName string

@description('Domain description')
param domainDescription string = 'Data domain managed via Bicep deployment'

// Purview Parameters
@description('Name of the existing Purview account')
param purviewAccountName string

@description('Data Map domain (collection) name')
param purviewDataMapDomainName string

@description('Data Map domain description')
param purviewDataMapDomainDescription string

@description('Parent collection referenceName (empty for root)')
param purviewDataMapParentCollectionId string = ''

@description('Unified Catalog governance domain name')
param purviewGovernanceDomainName string

@description('Unified Catalog governance domain description')
param purviewGovernanceDomainDescription string

@allowed(['Functional Unit', 'Line of Business', 'Data Domain', 'Regulatory', 'Project'])
@description('Unified Catalog governance domain type')
param purviewGovernanceDomainType string

@description('Parent governance domain ID (empty for top-level)')
param purviewGovernanceDomainParentId string = ''

// Lakehouse Parameters
@description('Comma separated lakehouse names')
param lakehouseNames string = 'bronze,silver,gold'

@description('Default document lakehouse name for indexers')
param documentLakehouseName string = 'bronze'

// AI Services Parameters (optional)
@description('Optional: AI Search service name')
param aiSearchName string = ''

@description('Optional: AI Foundry name')
param aiFoundryName string = ''

@description('Optional: AI Search resource group')
param aiSearchResourceGroup string = ''

@description('Optional: AI Search subscription id')
param aiSearchSubscriptionId string = ''

@description('Optional: AI Foundry resource group')
param aiFoundryResourceGroup string = ''

@description('Optional: AI Foundry subscription id')
param aiFoundrySubscriptionId string = ''

// Optional Features
@description('Enable Purview scan triggering')
param enablePurviewScan bool = false

@description('Enable Log Analytics connection')
param enableLogAnalytics bool = false

@description('Log Analytics workspace ID (if enableLogAnalytics is true)')
param logAnalyticsWorkspaceId string = ''

// ============================================================================
// STEP 1: DEPLOY FABRIC CAPACITY
// ============================================================================

module capacity 'br/public:avm/res/fabric/capacity:0.1.1' = {
  name: 'fabric-capacity-${uniqueString(resourceGroup().id)}'
  params: {
    name: fabricCapacityName
    adminMembers: capacityAdminMembers
    skuName: fabricCapacitySKU
    location: location
    tags: tags
  }
}

// ============================================================================
// STEP 2: CREATE MANAGED IDENTITY FOR DEPLOYMENT SCRIPTS
// ============================================================================
// This managed identity is used by all deployment scripts for:
// - Authenticating to Azure Storage (Storage File Data Privileged Contributor)
// - Executing Fabric operations (requires Fabric Administrator role)
// - Executing Purview operations (requires Purview Data Curator role)

module managedIdentity './modules/shared/managedIdentity.bicep' = {
  name: 'managed-identity-${uniqueString(resourceGroup().id)}'
  params: {
    managedIdentityName: 'id-fabric-automation-${uniqueString(resourceGroup().id)}'
    location: location
    tags: tags
  }
}

// ============================================================================
// STEP 3: AUTOMATED RBAC ASSIGNMENTS
// ============================================================================
// These modules automatically assign Fabric and Purview roles via REST APIs.
// They run AFTER storage account is created so they can use it for execution.
// If API calls fail, they provide clear manual instructions.
//
// Note: Storage RBAC (Storage File Data Privileged Contributor) is automatically
// assigned by the AVM storage account module in STEP 4.

// ============================================================================
// STEP 4: DEPLOY SHARED STORAGE ACCOUNT (for all deployment scripts)
// ============================================================================
// Storage account uses managed identity authentication (WAF-compliant)
// - allowSharedKeyAccess: false (security best practice)
// - RBAC: Managed identity has Storage File Data Privileged Contributor role

module sharedStorage './modules/shared/deploymentScriptStorage.bicep' = {
  name: 'shared-storage-${uniqueString(resourceGroup().id)}'
  params: {
    storageAccountName: 'stdeploy${uniqueString(resourceGroup().id)}'
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
    location: location
    tags: tags
  }
}

// ============================================================================
// STEP 5A: ASSIGN FABRIC ADMINISTRATOR ROLE (Automated via API)
// ============================================================================
// This module uses the Fabric REST API to automatically assign the Fabric
// Administrator role to the managed identity for capacity operations.
// If the API call fails, it provides manual instructions.

module fabricRoles './modules/shared/assignFabricRoles.bicep' = {
  name: 'assign-fabric-roles-${uniqueString(resourceGroup().id)}'
  params: {
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
    fabricCapacityId: capacity.outputs.resourceId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 5B: ASSIGN PURVIEW ROLES (Automated via API)
// ============================================================================
// This module uses the Purview REST API to automatically assign Collection Admin,
// Data Source Administrator, and Data Curator roles to the managed identity.
// If the API call fails, it provides manual instructions.

module purviewRoles './modules/shared/assignPurviewRoles.bicep' = {
  name: 'assign-purview-roles-${uniqueString(resourceGroup().id)}'
  params: {
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
    purviewAccountName: purviewAccountName
    purviewCollectionName: purviewDataMapDomainName
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 6: CREATE FABRIC DOMAIN
// ============================================================================

module fabricDomain './modules/fabric/fabricDomain.bicep' = {
  name: 'fabric-domain-${uniqueString(resourceGroup().id)}'
  params: {
    domainName: domainName
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 6: CREATE FABRIC WORKSPACE AND ATTACH TO CAPACITY
// ============================================================================
// This module performs TWO atomic operations:
//   1. Creates the Fabric workspace
//   2. Attaches the workspace to the specified capacity

module fabricWorkspace './modules/fabric/fabricWorkspace.bicep' = {
  name: 'fabric-workspace-${uniqueString(resourceGroup().id)}'
  params: {
    workspaceName: fabricWorkspaceName
    capacityId: capacity.outputs.resourceId
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 7: ENSURE CAPACITY IS ACTIVE
// ============================================================================
// IMPORTANT: This must run BEFORE assigning workspace to domain because the
// domain assignment API requires the capacity to be active and accessible.

module ensureCapacity './modules/fabric/ensureActiveCapacity.bicep' = {
  name: 'ensure-capacity-${uniqueString(resourceGroup().id)}'
  params: {
    fabricCapacityId: capacity.outputs.resourceId
    fabricCapacityName: fabricCapacityName
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 8: ASSIGN WORKSPACES (BY CAPACITY) TO DOMAIN
// ============================================================================
// This module assigns ALL workspaces on the specified capacity to the domain.
// It's a BULK operation that works at the capacity level, not individual workspace level.
// 
// Prerequisites:
//   - Workspace must already be attached to capacity (done in step 6)
//   - Capacity must be active (ensured in step 7)
//   - Domain must exist (created in step 5)
//
// Note: This uses the Fabric Admin API endpoint:
//   POST /admin/domains/{domainId}/assignWorkspacesByCapacities

module assignWorkspacesToDomain './modules/fabric/assignWorkspaceToDomain.bicep' = {
  name: 'assign-workspaces-to-domain-${uniqueString(resourceGroup().id)}'
  params: {
    workspaceName: fabricWorkspaceName
    domainName: domainName
    capacityId: capacity.outputs.resourceId
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 9: CREATE LAKEHOUSES (bronze, silver, gold)
// ============================================================================

module lakehouses './modules/fabric/createLakehouses.bicep' = {
  name: 'lakehouses-${uniqueString(resourceGroup().id)}'
  params: {
    workspaceName: fabricWorkspaceName
    workspaceId: fabricWorkspace.outputs.workspaceId
    lakehouseNames: lakehouseNames
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 10: CREATE PURVIEW COLLECTION
// ============================================================================

module purviewCollection './modules/purview/createPurviewCollection.bicep' = {
  name: 'purview-collection-${uniqueString(resourceGroup().id)}'
  params: {
    purviewAccountName: purviewAccountName
    collectionName: purviewDataMapDomainName
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 11: REGISTER FABRIC AS PURVIEW DATASOURCE
// ============================================================================

module registerDatasource './modules/purview/registerFabricDatasource.bicep' = {
  name: 'register-datasource-${uniqueString(resourceGroup().id)}'
  params: {
    purviewAccountName: purviewAccountName
    collectionName: purviewDataMapDomainName
    workspaceId: fabricWorkspace.outputs.workspaceId
    workspaceName: fabricWorkspaceName
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 12 (OPTIONAL): TRIGGER PURVIEW SCAN
// ============================================================================

module triggerScan './modules/purview/triggerPurviewScan.bicep' = if (enablePurviewScan) {
  name: 'trigger-scan-${uniqueString(resourceGroup().id)}'
  params: {
    purviewAccountName: purviewAccountName
    datasourceName: fabricWorkspaceName // Assuming datasource name matches workspace
    workspaceId: fabricWorkspace.outputs.workspaceId
    workspaceName: fabricWorkspaceName
    collectionId: purviewDataMapDomainName
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// STEP 13 (OPTIONAL): CONNECT LOG ANALYTICS
// ============================================================================

module logAnalytics './modules/monitoring/connectLogAnalytics.bicep' = if (enableLogAnalytics) {
  name: 'log-analytics-${uniqueString(resourceGroup().id)}'
  params: {
    workspaceName: fabricWorkspaceName
    workspaceId: fabricWorkspace.outputs.workspaceId
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    userAssignedIdentityId: managedIdentity.outputs.managedIdentityId
    location: location
    tags: tags
    utcValue: utcValue
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

// Capacity Outputs
output fabricCapacityId string = capacity.outputs.resourceId
output fabricCapacityName string = fabricCapacityName

// Workspace Outputs
output fabricWorkspaceId string = fabricWorkspace.outputs.workspaceId
output fabricWorkspaceName string = fabricWorkspaceName

// Domain Outputs
output fabricDomainName string = domainName

// Managed Identity Outputs
output managedIdentityId string = managedIdentity.outputs.managedIdentityId
output managedIdentityPrincipalId string = managedIdentity.outputs.managedIdentityPrincipalId
output managedIdentityClientId string = managedIdentity.outputs.managedIdentityClientId

// Storage Outputs
output sharedStorageAccountName string = sharedStorage.outputs.storageAccountName
output sharedStorageAccountId string = sharedStorage.outputs.storageAccountId

// Purview Outputs
output purviewAccountName string = purviewAccountName
output purviewDataMapDomainName string = purviewDataMapDomainName
output purviewGovernanceDomainName string = purviewGovernanceDomainName

// AI Services Outputs (pass-through for downstream scripts if needed)
output aiSearchName string = aiSearchName
output aiFoundryName string = aiFoundryName
output lakehouseNames string = lakehouseNames
output documentLakehouseName string = documentLakehouseName

// Deployment Status
output deploymentComplete bool = true
output deploymentTimestamp string = utcValue
