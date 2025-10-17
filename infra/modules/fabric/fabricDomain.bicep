@description('Creates a Microsoft Fabric domain using deployment script')
param domainName string
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

@description('Managed Identity resource ID for deployment script execution')
param userAssignedIdentityId string

@description('Storage account name for deployment scripts (managed identity auth)')
param storageAccountName string

@description('Storage account key for deployment scripts')
@secure()
param storageAccountKey string

var deploymentScriptName = 'deploy-fabric-domain-${uniqueString(resourceGroup().id, domainName)}'

// Deployment script using native Azure resource with managed identity
resource fabricDomainDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: deploymentScriptName
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    forceUpdateTag: utcValue
    retentionInterval: 'P1D'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    storageAccountSettings: {
      storageAccountName: storageAccountName
      storageAccountKey: storageAccountKey
    }
    environmentVariables: [
      {
        name: 'FABRIC_DOMAIN_NAME'
        value: domainName
      }
    ]
    scriptContent: '''
param([string]$DomainName = $env:FABRIC_DOMAIN_NAME)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Log([string]$m) { Write-Host "[fabric-domain] $m"; Write-Output "[fabric-domain] $m" }
if (-not $DomainName) { throw "FABRIC_DOMAIN_NAME is required" }
Log "Starting Fabric domain creation for: $DomainName"
$fabricToken = (Get-AzAccessToken -ResourceUrl "https://api.fabric.microsoft.com").Token
if (-not $fabricToken) { throw "Failed to obtain Fabric API token" }
$headers = @{ 'Authorization' = "Bearer $fabricToken"; 'Content-Type' = 'application/json' }
$apiFabricRoot = 'https://api.fabric.microsoft.com/v1'
$domainId = $null
try {
  Log "Checking if domain exists..."
  $domains = Invoke-RestMethod -Uri "$apiFabricRoot/governance/domains" -Headers $headers -Method Get
  if ($domains.value) {
    $existingDomain = $domains.value | Where-Object { $_.displayName -eq $DomainName -or $_.name -eq $DomainName }
    if ($existingDomain) {
      $domainId = $existingDomain.id
      Log "Domain already exists with ID: $domainId"
    }
  }
} catch { Log "Could not check existing domains: $($_.Exception.Message)" }
if (-not $domainId) {
  Log "Creating new Fabric domain: $DomainName"
  $payload = @{ displayName = $DomainName } | ConvertTo-Json
  $response = Invoke-RestMethod -Uri "$apiFabricRoot/admin/domains" -Method Post -Headers $headers -Body $payload
  $domainId = $response.id
  Log "✅ Created domain with ID: $domainId"
}
Log "Fabric domain deployment completed"
$DeploymentScriptOutputs = @{ domainId = $domainId; domainName = $DomainName }
    '''
  }
}

output domainId string = fabricDomainDeploymentScript.properties.outputs.domainId
output domainName string = fabricDomainDeploymentScript.properties.outputs.domainName
