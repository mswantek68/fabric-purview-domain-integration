@description('Creates a Microsoft Fabric domain using deployment script')
param domainName string
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

@description('Managed Identity for deployment script execution')
param userAssignedIdentityId string

// Generate unique names for deployment script resources
var deploymentScriptName = 'deploy-fabric-domain-${uniqueString(resourceGroup().id, domainName)}'
var storageAccountName = 'stfabdom${uniqueString(resourceGroup().id, domainName)}'

// Storage account for deployment script
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Deployment script to create Fabric domain
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
      storageAccountName: storageAccount.name
      storageAccountKey: storageAccount.listKeys().keys[0].value
    }
    environmentVariables: [
      {
        name: 'FABRIC_DOMAIN_NAME'
        value: domainName
      }
    ]
    scriptContent: '''
# Fabric Domain Creation Script
param(
  [string]$DomainName = $env:FABRIC_DOMAIN_NAME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { 
  Write-Host "[fabric-domain] $m" 
  Write-Output "[fabric-domain] $m"
}
function Warn([string]$m) { 
  Write-Warning "[fabric-domain] $m"
  Write-Output "[WARNING] $m"
}
function Fail([string]$m) { 
  Write-Error "[fabric-domain] $m"
  Write-Output "[ERROR] $m"
  throw $m
}

if (-not $DomainName) { 
  Fail 'FABRIC_DOMAIN_NAME is required'
}

Log "Starting Fabric domain creation for: $DomainName"

# Acquire tokens
try { 
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
  if (-not $accessToken) { throw "No Power BI token returned" }
} catch { 
  Fail "Failed to obtain Power BI API token (ensure managed identity has Fabric Admin permissions)"
}

try { 
  $fabricToken = & az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv 
  if (-not $fabricToken) { throw "No Fabric token returned" }
} catch { 
  Fail "Failed to obtain Fabric API token (ensure managed identity has Fabric Admin permissions)"
}

$apiFabricRoot = 'https://api.fabric.microsoft.com/v1'

# Check if domain already exists
try {
  $domains = Invoke-RestMethod -Uri "$apiFabricRoot/governance/domains" -Headers @{ Authorization = "Bearer $fabricToken" } -Method Get -ErrorAction Stop
  $domainId = $null
  
  if ($domains -and $domains.value) { 
    $existingDomain = $domains.value | Where-Object { $_.displayName -eq $DomainName -or $_.name -eq $DomainName }
    if ($existingDomain) { 
      $domainId = $existingDomain.id 
      Log "Domain '$DomainName' already exists with ID: $domainId"
    }
  }
} catch {
  Fail "Failed to check existing domains: $_"
}

# Create domain if it doesn't exist
if (-not $domainId) {
  Log "Creating Fabric domain '$DomainName'..."
  try {
    $payload = @{ displayName = $DomainName } | ConvertTo-Json -Depth 4
    $resp = Invoke-WebRequest -Uri "$apiFabricRoot/admin/domains" -Method Post -Headers @{ Authorization = "Bearer $fabricToken"; 'Content-Type' = 'application/json' } -Body $payload -UseBasicParsing -ErrorAction Stop
    $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    $domainId = $body.id
    Log "Created domain with ID: $domainId"
  } catch { 
    Fail "Domain creation failed: $_"
  }
}

Log "Fabric domain deployment completed"

# Set outputs for Bicep
$DeploymentScriptOutputs = @{
  domainId = $domainId
  domainName = $DomainName
}
    '''
  }
}

// Outputs
output domainId string = fabricDomainDeploymentScript.properties.outputs.domainId
output domainName string = fabricDomainDeploymentScript.properties.outputs.domainName
