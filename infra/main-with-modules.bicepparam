using 'main-with-modules.bicep'

// ========================================================================
// REQUIRED PARAMETERS - Must be configured for your environment
// ========================================================================

// Resource Group Configuration
param location = 'eastus2' // Change to your preferred Azure region
param tags = {
  environment: 'dev'
  project: 'fabric-purview-integration'
  managedBy: 'bicep'
}

// Fabric Capacity Configuration
param fabricCapacityName = 'swancapacitytest1016'
param fabricCapacitySKU = 'F8'
param capacityAdminMembers = ['admin@MngEnv282784.onmicrosoft.com'] // Add admin UPNs or object IDs: ['admin@yourdomain.onmicrosoft.com']

// Fabric Workspace and Domain Names
param fabricWorkspaceName = 'workspacetest1016'
param domainName = 'datadomain1016'

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
// LAKEHOUSE CONFIGURATION
// ========================================================================

param lakehouseNames = 'bronze,silver,gold'
param documentLakehouseName = 'bronze'

// ========================================================================
// OPTIONAL FEATURES
// ========================================================================

// Enable Purview Scan (runs immediately after datasource registration)
param enablePurviewScan = false

// Enable Log Analytics Connection
param enableLogAnalytics = false
param logAnalyticsWorkspaceId = '' // Required if enableLogAnalytics is true

// ========================================================================
// AI SERVICES INTEGRATION (Optional - for OneLake Index features)
// ========================================================================

// AI Search Configuration
param aiSearchName = ''
param aiSearchResourceGroup = ''
param aiSearchSubscriptionId = '' // Leave empty to use current subscription

// AI Foundry Configuration  
param aiFoundryName = ''
param aiFoundryResourceGroup = ''
param aiFoundrySubscriptionId = '' // Leave empty to use current subscription
