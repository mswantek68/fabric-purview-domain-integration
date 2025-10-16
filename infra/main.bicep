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
param fabricCapacityName string

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
param fabricCapacitySKU string

@description('Admin principal UPNs or objectIds to assign to the capacity (optional).')
param capacityAdminMembers array

// Optional: workspace name passed via azd env or parameters (used by post-provision script, not ARM)
@description('Desired Fabric workspace display name (workspace is currently not deployable via ARM as of Aug 2025).')
param fabricWorkspaceName string

@description('Desired Fabric Data Domain name (governance domain). Used only by post-provision script; Fabric Domains not deployable via ARM yet.')
param domainName string

@description('Name of the existing Purview account for governance integration')
param purviewAccountName string

// Purview Data Map domain parameters (technical collection hierarchy used by scans/RBAC)
@description('Data Map domain (top-level collection) name used for automation. Distinct from Unified Catalog governance domain.')
param purviewDataMapDomainName string

@description('Description for the Data Map domain (collection)')
param purviewDataMapDomainDescription string

@description('Optional: Parent collection referenceName to nest under; empty for root')
param purviewDataMapParentCollectionId string

// Purview Unified Catalog governance domain parameters (business-level domain)
@description('Unified Catalog governance domain name (business grouping). Defaults to Fabric domain name + "-governance"')
param purviewGovernanceDomainName string

@description('Unified Catalog governance domain description')
param purviewGovernanceDomainDescription string

@allowed(['Functional Unit', 'Line of Business', 'Data Domain', 'Regulatory', 'Project'])
@description('Unified Catalog governance domain classification/type')
param purviewGovernanceDomainType string

@description('Optional: Parent governance domain ID (GUID) in Unified Catalog; empty for top-level')
param purviewGovernanceDomainParentId string

// Optional parameters for AI Search/Foundry integration and lakehouse configuration
@description('Optional: AI Search service name')
param aiSearchName string

@description('Optional: AI Foundry (Cognitive Services) name')
param aiFoundryName string

@description('Optional: AI Search resource group')
param aiSearchResourceGroup string

@description('Optional: AI Search subscription id')
param aiSearchSubscriptionId string

@description('Optional: AI Foundry resource group')
param aiFoundryResourceGroup string

@description('Optional: AI Foundry subscription id')
param aiFoundrySubscriptionId string

@description('Optional: Azure AI Document Intelligence (Form Recognizer) account name; leave empty to skip provisioning.')
param documentIntelligenceName string = ''

@description('SKU for the Document Intelligence account when provisioned.')
@allowed([
   'S0'
   'S1'
   'S2'
   'S3'
])
param documentIntelligenceSku string = 'S0'

@description('Set to false to skip Document Intelligence deployment even when a name is provided.')
param enableDocumentIntelligence bool = true

@description('Optional: Execution Managed Identity Principal ID used for RBAC configuration')
param executionManagedIdentityPrincipalId string = ''

@description('Comma separated lakehouse names (defaults to bronze,silver,gold)')
param lakehouseNames string

@description('Default document lakehouse name to use for indexers')
param documentLakehouseName string

var deployDocumentIntelligence = enableDocumentIntelligence && !empty(documentIntelligenceName)
var documentIntelligenceResourceId = deployDocumentIntelligence ? resourceId('Microsoft.CognitiveServices/accounts', documentIntelligenceName) : ''

// Provision Azure AI Document Intelligence (Form Recognizer) when requested
resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2023-05-01' = if (deployDocumentIntelligence) {
   name: documentIntelligenceName
   location: resourceGroup().location
   kind: 'FormRecognizer'
   sku: {
      name: documentIntelligenceSku
   }
   properties: {
      customSubDomainName: documentIntelligenceName
      publicNetworkAccess: 'Enabled'
      disableLocalAuth: true
      networkAcls: {
         defaultAction: 'Allow'
         ipRules: []
      }
   }
}

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

// New AI service and lakehouse outputs for scripts to consume
output aiSearchName string = aiSearchName
output aiFoundryName string = aiFoundryName
output aiSearchResourceGroup string = aiSearchResourceGroup
output aiSearchSubscriptionId string = aiSearchSubscriptionId
output aiFoundryResourceGroup string = aiFoundryResourceGroup
output aiFoundrySubscriptionId string = aiFoundrySubscriptionId
output executionManagedIdentityPrincipalId string = executionManagedIdentityPrincipalId
output lakehouseNames string = lakehouseNames
output documentLakehouseName string = documentLakehouseName
output documentIntelligenceName string = deployDocumentIntelligence ? documentIntelligenceName : ''
output documentIntelligenceEndpoint string = deployDocumentIntelligence ? reference(documentIntelligenceResourceId, '2023-05-01', 'full').endpoint : ''
output documentIntelligenceResourceId string = documentIntelligenceResourceId
