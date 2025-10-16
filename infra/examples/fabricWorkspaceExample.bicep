// Example: Deploy Fabric workspace with dependencies
// This example shows how to deploy a complete Fabric workspace with managed identity and capacity

param environmentName string = 'dev'
param workspaceBaseName string = 'analytics'
param location string = resourceGroup().location

var workspaceName = '${workspaceBaseName}-${environmentName}'
var tags = {
  Environment: environmentName
  Project: 'FabricPurviewIntegration'
  Component: 'DataWorkspace'
}

// User-assigned managed identity for Fabric operations
resource fabricManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-fabric-${environmentName}'
  location: location
  tags: tags
}

// Example capacity (this would typically reference an existing capacity)
// For this example, we're showing the structure - actual capacity should be created separately
var capacityId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Fabric/capacities/fabric-capacity-${environmentName}'

// Deploy Fabric workspace using the module
module fabricWorkspace '../modules/fabric/fabricWorkspace.bicep' = {
  name: 'deploy-${workspaceName}'
  params: {
    workspaceName: workspaceName
    capacityId: capacityId
    userAssignedIdentityId: fabricManagedIdentity.id
    location: location
    tags: tags
  }
}

// Outputs for downstream consumption
output workspaceDetails object = {
  id: fabricWorkspace.outputs.workspaceId
  name: fabricWorkspace.outputs.workspaceName
  capacityId: fabricWorkspace.outputs.capacityId
  managedIdentityId: fabricManagedIdentity.id
  resourceGroup: resourceGroup().name
}

output deploymentInfo object = {
  timestamp: utcNow()
  environment: environmentName
  workspaceName: workspaceName
  status: 'deployed'
}
