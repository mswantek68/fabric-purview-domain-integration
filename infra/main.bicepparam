using 'main.bicep'

// ========================================================================
// REQUIRED PARAMETERS - Must be configured for your environment
// ========================================================================

// Fabric Capacity Configuration
param fabricCapacityName = 'swantekcapacity01'
param fabricCapacitySKU = 'F8'
param capacityAdminMembers = ['admin@MngEnv282784.onmicrosoft.com'] // Add admin UPNs or object IDs: ['admin@yourdomain.onmicrosoft.com']

// Fabric Workspace and Domain Names
param fabricWorkspaceName = 'swantekworkspace01'
param domainName = 'swantekdatadomain01'

// Purview Integration
param purviewAccountName = 'swantekPurview'

// ========================================================================
// PURVIEW DATA MAP CONFIGURATION
// ========================================================================

// Data Map domain (technical collection hierarchy for scans/RBAC)
param purviewDataMapDomainName = '${domainName}-collection'
param purviewDataMapDomainDescription = 'Data Map domain (collection) for ${domainName}'
param purviewDataMapParentCollectionId = '' // Empty for root level

// ========================================================================
// PURVIEW GOVERNANCE DOMAIN CONFIGURATION  
// ========================================================================

// Unified Catalog governance domain (business-level grouping)
param purviewGovernanceDomainName = '${domainName}-governance'
param purviewGovernanceDomainDescription = 'Governance domain for ${domainName}'
param purviewGovernanceDomainType = 'Data Domain'
param purviewGovernanceDomainParentId = '' // Empty for top-level

// ========================================================================
// AI SERVICES INTEGRATION (Optional)
// ========================================================================

// AI Search Configuration
param aiSearchName = 'aisearchswan2'
param aiSearchResourceGroup = 'AI_Related'
param aiSearchSubscriptionId = '48ab3756-f962-40a8-b0cf-b33ddae744bb' // Leave empty to use current subscription

// AI Foundry Configuration  
param aiFoundryName = 'swantekFoundry1'
param aiFoundryResourceGroup = 'AI_Related'
param aiFoundrySubscriptionId = '48ab3756-f962-40a8-b0cf-b33ddae744bb' // Leave empty to use current subscription

// ========================================================================
// EXECUTION AND LAKEHOUSE CONFIGURATION
// ========================================================================

// NOTE: executionManagedIdentityPrincipalId is omitted from this parameter file
// as it's typically provided dynamically by deployment pipelines.
// 
// However, if you have your own User-Assigned Managed Identity (UAMI) or 
// Service Principal that you want to use for RBAC assignments, you can:
//
// 1. Add it here: param executionManagedIdentityPrincipalId = 'your-principal-id'
// 2. Pass via CLI: --parameters executionManagedIdentityPrincipalId='your-principal-id'
// 3. Leave empty (default) for pipeline-managed scenarios

// Lakehouse Configuration
param lakehouseNames = 'bronze,silver,gold'
param documentLakehouseName = 'bronze'
