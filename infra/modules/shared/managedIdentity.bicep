// ============================================================================
// Managed Identity Module for Deployment Scripts
// ============================================================================
// This module creates a user-assigned managed identity used by all deployment
// scripts in the solution. Using managed identity instead of storage account
// keys follows Azure Well-Architected Framework security best practices.
//
// The identity will be granted the following roles:
// - Storage File Data Privileged Contributor (on deployment storage account)
// - Fabric Administrator or Workspace Admin (for Fabric operations)
// - Purview Data Curator (for Purview operations)
// ============================================================================

@description('Name of the managed identity')
param managedIdentityName string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Tags to apply to resources')
param tags object = {}

// Deploy user-assigned managed identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// ============================================================================
// Outputs
// ============================================================================

@description('The resource ID of the managed identity')
output managedIdentityId string = managedIdentity.id

@description('The principal ID (object ID) of the managed identity')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('The client ID of the managed identity')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('The name of the managed identity')
output managedIdentityName string = managedIdentity.name
