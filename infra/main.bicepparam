using 'main.bicep'

// ========================================================================
// REQUIRED PARAMETERS - Must be configured for your environment
// ========================================================================

// Fabric Capacity Configuration
param fabricCapacityName = 'swancapacity002'
param fabricCapacitySKU = 'F8'
param capacityAdminMembers = [''] // Add admin UPNs or object IDs: ['admin@yourdomain.onmicrosoft.com']

// Fabric Workspace and Domain Names
param fabricWorkspaceName = 'workspace002'
param domainName = 'datadomain002'

// Purview Integration
param purviewAccountName = 'Purview'

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
param aiSearchName = ''
param aiSearchResourceGroup = ''
param aiSearchSubscriptionId = '' // Leave empty to use current subscription

// AI Foundry Configuration  
param aiFoundryName = ''
param aiFoundryResourceGroup = ''
param aiFoundrySubscriptionId = '' // Leave empty to use current subscription

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
