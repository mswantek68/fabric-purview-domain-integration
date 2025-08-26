// Parameters for resource group and subscription
param fabricCapacityName string = 'swancapacity9'
param fabricCapacitySKU string ='F64'
@description('Admin principal UPNs or objectIds to assign to the capacity (optional).')
param capacityAdminMembers array = ['admin@MngEnv282784.onmicrosoft.com', 'mswantek@MngEnv282784.onmicrosoft.com']
// Optional: workspace name passed via azd env or parameters (used by post-provision script, not ARM)
@description('Desired Fabric workspace display name (workspace is currently not deployable via ARM as of Aug 2025).')
param fabricWorkspaceName string = 'swan-workspace9'
@description('Desired Fabric Data Domain name (governance domain). Used only by post-provision script; Fabric Domains not deployable via ARM yet.')
param domainName string = 'swan-data-domain9'
@description('Name of the existing Purview account for governance integration')
param purviewAccountName string = 'swantekpurview'

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
