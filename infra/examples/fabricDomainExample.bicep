// Example: Deploy Fabric domain with dependencies
// This example shows how to deploy a Fabric domain with managed identity

param environmentName string = 'dev'
param domainBaseName string = 'analytics'
param location string = resourceGroup().location

var domainName = '${domainBaseName}-domain-${environmentName}'
var tags = {
  Environment: environmentName
  Project: 'FabricPurviewIntegration'
  Component: 'FabricDomain'
}

// User-assigned managed identity for Fabric operations
resource fabricManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-fabric-domain-${environmentName}'
  location: location
  tags: tags
}

// Deploy Fabric domain using the module
module fabricDomain '../modules/fabric/fabricDomain.bicep' = {
  name: 'deploy-${domainName}'
  params: {
    domainName: domainName
    userAssignedIdentityId: fabricManagedIdentity.id
    location: location
    tags: tags
  }
}

// Outputs for downstream consumption
output domainDetails object = {
  id: fabricDomain.outputs.domainId
  name: fabricDomain.outputs.domainName
  managedIdentityId: fabricManagedIdentity.id
  resourceGroup: resourceGroup().name
}

output deploymentInfo object = {
  timestamp: utcNow()
  environment: environmentName
  domainName: domainName
  status: 'deployed'
}
