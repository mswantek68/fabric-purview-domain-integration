@description('Creates a Purview collection using deployment script')
param purviewAccountName string
param collectionName string
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

@description('Managed Identity for deployment script execution')
param userAssignedIdentityId string

@description('Name of the shared storage account for deployment scripts')
param storageAccountName string


// Generate unique names for deployment script resources
var deploymentScriptName = 'create-purview-collection-${uniqueString(resourceGroup().id, collectionName)}'

// Deployment script to create Purview collection
resource createPurviewCollectionDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
      storageAccountKey: null
      storageAccountName: storageAccountName
    }
    environmentVariables: [
      {
        name: 'PURVIEW_ACCOUNT_NAME'
        value: purviewAccountName
      }
      {
        name: 'COLLECTION_NAME'
        value: collectionName
      }
    ]
    scriptContent: '''
# Create Purview Collection
param(
  [string]$PurviewAccountName = $env:PURVIEW_ACCOUNT_NAME,
  [string]$CollectionName = $env:COLLECTION_NAME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { 
  Write-Host "[purview-collection] $m" 
  Write-Output "[purview-collection] $m"
}

function Warn([string]$m) { 
  Write-Warning "[purview-collection] $m"
  Write-Output "[WARNING] $m"
}

function Fail([string]$m) { 
  Write-Error "[purview-collection] $m"
  throw $m
}

if (-not $PurviewAccountName) { 
  Fail 'PURVIEW_ACCOUNT_NAME is required'
}

if (-not $CollectionName) { 
  Fail 'COLLECTION_NAME is required'
}

Log "Creating Purview collection under default domain"
Log "  • Account: $PurviewAccountName"
Log "  • Collection: $CollectionName"

# Acquire Purview token
try { 
  $purviewToken = & az account get-access-token --resource https://purview.azure.net --query accessToken -o tsv 2>$null
  if (-not $purviewToken) { 
    $purviewToken = & az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv 2>$null
  }
  if (-not $purviewToken) { throw "No Purview token returned" }
} catch { 
  Fail "Failed to obtain Purview access token"
}

$endpoint = "https://$PurviewAccountName.purview.azure.com"

# Check existing collections
try {
  $allCollections = Invoke-RestMethod -Uri "$endpoint/account/collections?api-version=2019-11-01-preview" -Headers @{ Authorization = "Bearer $purviewToken" } -Method Get -ErrorAction Stop
  
  $existing = $null
  if ($allCollections.value) { 
    $existing = $allCollections.value | Where-Object { 
      $_.friendlyName -eq $CollectionName -or $_.name -eq $CollectionName 
    }
  }
  
  if ($existing) {
    Log "Collection '$CollectionName' already exists (id=$($existing.name))"
    $collectionId = $existing.name
  } else {
    Log "Creating new collection '$CollectionName' under default domain..."
    $payload = @{ 
      friendlyName = $CollectionName
      description = "Collection for $CollectionName with Fabric workspace and lakehouses" 
    } | ConvertTo-Json -Depth 4
    
    try {
      $resp = Invoke-WebRequest -Uri "$endpoint/account/collections/${CollectionName}?api-version=2019-11-01-preview" -Headers @{ Authorization = "Bearer $purviewToken"; 'Content-Type' = 'application/json' } -Method Put -Body $payload -UseBasicParsing -ErrorAction Stop
      $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
      $collectionId = $body.name
      Log "Collection '$CollectionName' created successfully (id=$collectionId)"
    } catch {
      Fail "Collection creation failed: $_"
    }
  }
} catch {
  Fail "Failed to check/create collection: $_"
}

Log "Collection '$CollectionName' (id=$collectionId) is ready under default domain"

# Set outputs for Bicep
$DeploymentScriptOutputs = @{
  collectionId = $collectionId
  collectionName = $CollectionName
}
    '''
  }
}

// Outputs
output collectionId string = createPurviewCollectionDeploymentScript.properties.outputs.collectionId
output collectionName string = createPurviewCollectionDeploymentScript.properties.outputs.collectionName
