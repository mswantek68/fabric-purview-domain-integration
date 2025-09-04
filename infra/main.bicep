/*
RBAC Requirements for AI Search and AI Foundry Integration:

1. AI Search RBAC Roles (assign to execution managed identity):
   - Search Service Contributor (7ca78c08-252a-4471-8644-bb5ff32d4ba0) - Full access to search service
   - OR Search Index Data Contributor (8ebe5a00-799e-43f5-93ac-243d3dce84a7) - Index data operations
   - OR Search Index Data Reader (1407120a-92aa-4202-b7e9-c0e197c71c8f) - Read-only access

2. AI Foundry RBAC Roles (assign to execution managed identity):
   - Cognitive Services Contributor (25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68) - Full access
   - OR Cognitive Services User (a97b65f3-24c7-4388-baec-2e87135dc908) - Runtime access

3. Cross-Subscription Access:
   - If AI services are in different subscriptions, ensure managed identity has:
   - Reader role on target subscription/resource group
   - Appropriate service-specific roles on the AI resources

4. Private Endpoint Considerations:
   - Network access from execution environment to private endpoints
   - Private DNS zone configuration
   - VNet peering or connectivity if needed
*/

// Parameters for resource group and subscription
@description('Fabric Capacity name. Cannot have dashes or underscores!')
param fabricCapacityName string = 'swantestcapacity3'
@description('Fabric capacity SKU (F-series). Available SKUs: F2, F4, F8, F16, F32, F64, F128, F256, F512, F1024, F2048.')
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
param fabricCapacitySKU string = 'F64'
@description('Admin principal UPNs or objectIds to assign to the capacity (optional).')
param capacityAdminMembers array = ['admin@MngEnv282784.onmicrosoft.com']
// Optional: workspace name passed via azd env or parameters (used by post-provision script, not ARM)
@description('Desired Fabric workspace display name (workspace is currently not deployable via ARM as of Aug 2025).')
param fabricWorkspaceName string = 'swantest-ws3'
@description('Desired Fabric Data Domain name (governance domain). Used only by post-provision script; Fabric Domains not deployable via ARM yet.')
param domainName string = 'swantest-domain3'
@description('Name of the existing Purview account for governance integration')
param purviewAccountName string = 'swantekpurview'

// AI Search and AI Foundry parameters
@description('Name of the existing AI Search service')
param aiSearchName string = 'aisearchswan2'
@description('Subscription ID where the AI Search service is deployed (leave empty if same as current subscription)')
param aiSearchSubscriptionId string = '48ab3756-f962-40a8-b0cf-b33ddae744bb'
@description('Resource group where the AI Search service is deployed (leave empty if same as current resource group)')
param aiSearchResourceGroup string = 'AI_Related'
@description('Custom endpoint for AI Search (use if behind private endpoint, e.g., https://aisearch.privatelink.search.windows.net)')
param aiSearchCustomEndpoint string = 'https://aisearchswan2.search.windows.net'
@description('Name of the existing AI Foundry service')
param aiFoundryName string ='swantekFoundry1'
@description('Subscription ID where the AI Foundry service is deployed (leave empty if same as current subscription)')
param aiFoundrySubscriptionId string = '48ab3756-f962-40a8-b0cf-b33ddae744bb'
@description('Resource group where the AI Foundry service is deployed (leave empty if same as current resource group)')
param aiFoundryResourceGroup string = 'AI_Related'
@description('Custom endpoint for AI Foundry (use if behind private endpoint)')
param aiFoundryCustomEndpoint string = 'https://swantekfoundry1.services.ai.azure.com/'

// Lakehouse and Document Processing parameters
@description('Names of the lakehouses to create (comma-separated)')
param lakehouseNames string = 'bronze,silver,gold'
@description('Name of the lakehouse used for document indexing')
param documentLakehouseName string = 'bronze'
@description('Base folder path for documents in the lakehouse')
param documentBaseFolderPath string = 'Files/documents'
@description('Document categories and their folder names (JSON object)')
param documentCategories string = '{"contracts":"contracts","reports":"reports","policies":"policies","manuals":"manuals"}'

// RBAC and Authentication parameters
@description('Principal ID of the managed identity that will access AI Search (leave empty to skip RBAC assignments)')
param executionManagedIdentityPrincipalId string = 'e86388dc-fbf7-40b1-92eb-d3a6bfb21db8'
@description('Principal ID of the managed identity that will access AI Foundry (leave empty to skip RBAC assignments)')  
param aiFoundryManagedIdentityPrincipalId string = '33544cdd-8ba0-4d66-92bc-2f73713097c9'

// Purview Data Map domain parameters (technical collection hierarchy used by scans/RBAC)
@description('Data Map domain (top-level collection) name used for automation. Distinct from Unified Catalog governance domain.')
param purviewDataMapDomainName string = '${domainName}-collection'
@description('Description for the Data Map domain (collection)')
param purviewDataMapDomainDescription string = 'Data Map domain (collection) for ${domainName}'
@description('Optional: Parent collection referenceName to nest under; empty for root')
param purviewDataMapParentCollectionId string = ''
// param adminMembers array

// Purview Unified Catalog governance domain parameters (business-level domain)
@description('Unified Catalog governance domain name (business grouping). Defaults to Fabric domain name + "-governance"')
param purviewGovernanceDomainName string = '${domainName}-governance'
@description('Unified Catalog governance domain description')
param purviewGovernanceDomainDescription string = 'Governance domain for ${domainName}'
@allowed(['Functional Unit', 'Line of Business', 'Data Domain', 'Regulatory', 'Project'])
@description('Unified Catalog governance domain classification/type')
param purviewGovernanceDomainType string = 'Data Domain'
@description('Optional: Parent governance domain ID (GUID) in Unified Catalog; empty for top-level')
param purviewGovernanceDomainParentId string = ''



// Deploy Fabric Capacity
module capacity 'br/public:avm/res/fabric/capacity:0.1.1' = {
  name: 'FabricCapacityDeployment'
  params: {
    name: fabricCapacityName
    adminMembers: capacityAdminMembers
    skuName:fabricCapacitySKU
  }
}
// NOTE: Microsoft.Fabric/workspaces resource type is not yet available via Azure Resource Manager/Bicep.
// The workspace will be created post-provision using the Fabric REST API (see scripts/create_fabric_workspace.sh).
// NOTE: AI Search and AI Foundry are assumed to be already deployed in the AI Landing Zone environment.

output fabricCapacityId string = capacity.outputs.resourceId
output fabricCapacityName string = fabricCapacityName
// Echo back desired workspace name for post-provision script consumption
output desiredFabricWorkspaceName string = fabricWorkspaceName
// Echo back desired domain name for post-provision script consumption
output desiredFabricDomainName string = domainName
// Echo back Purview account name for governance integration scripts
output purviewAccountName string = purviewAccountName
// Echo back Purview governance domain name for scripts
output purviewGovernanceDomainName string = purviewGovernanceDomainName
// Echo back additional governance domain details for scripts
output purviewGovernanceDomainDescription string = purviewGovernanceDomainDescription
output purviewGovernanceDomainType string = purviewGovernanceDomainType
output purviewGovernanceDomainParentId string = purviewGovernanceDomainParentId

// Echo back Data Map domain parameters for automation scripts
output purviewDataMapDomainName string = purviewDataMapDomainName
output purviewDataMapDomainDescription string = purviewDataMapDomainDescription
output purviewDataMapParentCollectionId string = purviewDataMapParentCollectionId

// Echo back AI Search and AI Foundry service names for post-provision scripts
output aiSearchName string = aiSearchName
output aiSearchSubscriptionId string = aiSearchSubscriptionId
output aiSearchResourceGroup string = aiSearchResourceGroup
output aiSearchCustomEndpoint string = aiSearchCustomEndpoint
output aiFoundryName string = aiFoundryName
output aiFoundrySubscriptionId string = aiFoundrySubscriptionId
output aiFoundryResourceGroup string = aiFoundryResourceGroup
output aiFoundryCustomEndpoint string = aiFoundryCustomEndpoint

// RBAC configuration outputs for post-deployment setup
output executionManagedIdentityPrincipalId string = executionManagedIdentityPrincipalId
output aiFoundryManagedIdentityPrincipalId string = aiFoundryManagedIdentityPrincipalId

// Lakehouse and Document Processing configuration outputs
output lakehouseNames string = lakehouseNames
output documentLakehouseName string = documentLakehouseName
output documentBaseFolderPath string = documentBaseFolderPath
output documentCategories string = documentCategories
