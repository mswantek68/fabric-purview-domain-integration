// Main Bicep Integration Example
// This demonstrates a complete Fabric integration deployment with domain, workspace, and dependencies

@description('Environment name (dev, test, prod)')
param environmentName string = 'dev'

@description('Base name for the project resources')
param projectBaseName string = 'fabricintegration'

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Fabric capacity resource ID (must exist)')
param fabricCapacityId string

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Project: 'FabricPurviewIntegration'
  CreatedBy: 'Bicep'
}

// Generate resource names
var domainName = '${projectBaseName}-domain-${environmentName}'
var workspaceName = '${projectBaseName}-workspace-${environmentName}'
var managedIdentityName = 'mi-fabric-${projectBaseName}-${environmentName}'

// User-assigned managed identity for Fabric operations
resource fabricManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Deploy Fabric domain first
module fabricDomain '../modules/fabricDomain.bicep' = {
  name: 'deploy-fabric-domain'
  params: {
    domainName: domainName
    userAssignedIdentityId: fabricManagedIdentity.id
    location: location
    tags: tags
  }
}

// Deploy Fabric workspace (depends on domain)
module fabricWorkspace '../modules/fabricWorkspace.bicep' = {
  name: 'deploy-fabric-workspace'
  params: {
    workspaceName: workspaceName
    capacityId: fabricCapacityId
    userAssignedIdentityId: fabricManagedIdentity.id
    location: location
    tags: tags
  }
  dependsOn: [
    fabricDomain
  ]
}

// Log Analytics workspace for monitoring (optional)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${projectBaseName}-${environmentName}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${projectBaseName}-${environmentName}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Key Vault for storing secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${projectBaseName}-${take(uniqueString(resourceGroup().id), 6)}'
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Grant the managed identity access to Key Vault
resource keyVaultAccessPolicy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, fabricManagedIdentity.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: fabricManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Store important values in Key Vault
resource domainIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'fabric-domain-id'
  parent: keyVault
  properties: {
    value: fabricDomain.outputs.domainId
    contentType: 'text/plain'
  }
}

resource workspaceIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'fabric-workspace-id'
  parent: keyVault
  properties: {
    value: fabricWorkspace.outputs.workspaceId
    contentType: 'text/plain'
  }
}

// Outputs for downstream consumption
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environmentName
  projectName: projectBaseName
  deployedAt: utcNow()
}

output fabricResources object = {
  domain: {
    id: fabricDomain.outputs.domainId
    name: fabricDomain.outputs.domainName
  }
  workspace: {
    id: fabricWorkspace.outputs.workspaceId
    name: fabricWorkspace.outputs.workspaceName
    capacityId: fabricWorkspace.outputs.capacityId
  }
  managedIdentity: {
    id: fabricManagedIdentity.id
    principalId: fabricManagedIdentity.properties.principalId
    clientId: fabricManagedIdentity.properties.clientId
  }
}

output supportingResources object = {
  keyVault: {
    id: keyVault.id
    name: keyVault.name
    vaultUri: keyVault.properties.vaultUri
  }
  logAnalytics: {
    id: logAnalyticsWorkspace.id
    name: logAnalyticsWorkspace.name
    customerId: logAnalyticsWorkspace.properties.customerId
  }
  applicationInsights: {
    id: applicationInsights.id
    name: applicationInsights.name
    instrumentationKey: applicationInsights.properties.InstrumentationKey
    connectionString: applicationInsights.properties.ConnectionString
  }
}

output nextSteps array = [
  'Verify that the managed identity has Fabric Administrator permissions'
  'Configure workspace access policies in the Fabric portal'
  'Set up data sources and lakehouse connections'
  'Configure Purview scanning and governance policies'
  'Test the OneLake indexing integration'
]
