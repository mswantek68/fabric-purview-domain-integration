@description('Assigns a Fabric workspace to a domain using deployment script')
param workspaceName string
param domainName string
param capacityId string
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

@description('Managed Identity for deployment script execution')
param userAssignedIdentityId string

@description('Name of the shared storage account for deployment scripts')
param storageAccountName string

@description('Storage account key for deployment scripts')
@secure()
param storageAccountKey string



// Generate unique names for deployment script resources
var deploymentScriptName = 'assign-domain-${uniqueString(resourceGroup().id, workspaceName, domainName)}'

// Deployment script to assign workspace to domain
resource assignDomainDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
        name: 'FABRIC_WORKSPACE_NAME'
        value: workspaceName
      }
      {
        name: 'FABRIC_DOMAIN_NAME'
        value: domainName
      }
      {
        name: 'FABRIC_CAPACITY_ID'
        value: capacityId
      }
    ]
    scriptContent: '''
# Assign Fabric Workspace to Domain
param(
  [string]$WorkspaceName = $env:FABRIC_WORKSPACE_NAME,
  [string]$DomainName = $env:FABRIC_DOMAIN_NAME,
  [string]$CapacityId = $env:FABRIC_CAPACITY_ID
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { 
  Write-Host "[assign-domain] $m" 
  Write-Output "[assign-domain] $m"
}

function Warn([string]$m) { 
  Write-Warning "[assign-domain] $m"
  Write-Output "[WARNING] $m"
}

function Fail([string]$m) { 
  Write-Error "[assign-domain] $m"
  throw $m
}

if (-not $WorkspaceName) { Fail 'FABRIC_WORKSPACE_NAME is required' }
if (-not $DomainName) { Fail 'FABRIC_DOMAIN_NAME is required' }
if (-not $CapacityId) { Fail 'FABRIC_CAPACITY_ID is required' }

Log "Assigning workspace '$WorkspaceName' to domain '$DomainName'"

# Acquire tokens
try { 
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
  if (-not $accessToken) { throw "No Power BI token returned" }
} catch { 
  Fail "Failed to obtain Power BI API token"
}

try { 
  $fabricToken = & az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv 
  if (-not $fabricToken) { throw "No Fabric token returned" }
} catch { 
  Fail "Failed to obtain Fabric API token"
}

$apiFabricRoot = 'https://api.fabric.microsoft.com/v1'
$apiPbiRoot = 'https://api.powerbi.com/v1.0/myorg'

# Find domain ID via Power BI admin domains
$domainId = $null
try {
  $domainsResponse = Invoke-RestMethod -Uri "$apiPbiRoot/admin/domains" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  if ($domainsResponse.domains) {
    $domain = $domainsResponse.domains | Where-Object { $_.displayName -eq $DomainName }
    if ($domain) { $domainId = $domain.objectId }
  }
} catch { 
  Warn 'Admin domains API not available. Cannot proceed with automatic assignment.'
  $DeploymentScriptOutputs = @{
    domainAssigned = $false
    message = 'Manual assignment required via Fabric Admin Portal'
  }
  return
}

if (-not $domainId) { 
  Fail "Domain '$DomainName' not found. Create it first." 
}

# Resolve capacity GUID
$capacityGuid = $null
$capName = ($CapacityId -split '/')[-1]
Log "Deriving Fabric capacity GUID for name: $capName"

# Try Fabric API first
try {
  $caps = Invoke-RestMethod -Uri "$apiFabricRoot/capacities" -Headers @{ Authorization = "Bearer $fabricToken" } -Method Get -ErrorAction Stop
  if ($caps.value) {
    $match = $caps.value | Where-Object { $_.displayName -eq $capName } | Select-Object -First 1
    if ($match) { 
      $capacityGuid = $match.id
      Log "Found capacity via Fabric API: $capacityGuid"
    }
  }
} catch {
  Log "Fabric API failed: $($_.Exception.Message)"
}

# Try Power BI API if Fabric API failed
if (-not $capacityGuid) {
  try {
    $caps = Invoke-RestMethod -Uri "$apiPbiRoot/admin/capacities" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    if ($caps.value) {
      $match = $caps.value | Where-Object { 
        ($_.displayName -eq $capName) -or ($_.name -eq $capName) 
      } | Select-Object -First 1
      if ($match) { 
        $capacityGuid = $match.id
        Log "Found capacity via Power BI API: $capacityGuid"
      }
    }
  } catch {
    Log "Power BI API also failed: $($_.Exception.Message)"
  }
}

if (-not $capacityGuid) {
  Fail "Could not resolve capacity GUID from '$CapacityId'"
}

# Find the workspace ID
$workspaceId = $null
try {
  $groups = Invoke-RestMethod -Uri "$apiPbiRoot/groups?top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  if ($groups.value) {
    $workspace = $groups.value | Where-Object { $_.name -eq $WorkspaceName }
    if ($workspace) { $workspaceId = $workspace.id }
  }
} catch { }

if (-not $workspaceId) { 
  Fail "Workspace '$WorkspaceName' not found." 
}

Log "Found workspace ID: $workspaceId"
Log "Found domain ID: $domainId"
Log "Found capacity GUID: $capacityGuid"

# Assign workspaces by capacities
$assignPayload = @{ capacitiesIds = @($capacityGuid) } | ConvertTo-Json -Depth 4
$assignUrl = "$apiFabricRoot/admin/domains/$domainId/assignWorkspacesByCapacities"

try {
  $assignResp = Invoke-WebRequest -Uri $assignUrl -Headers @{ Authorization = "Bearer $fabricToken"; 'Content-Type' = 'application/json' } -Method Post -Body $assignPayload -UseBasicParsing -ErrorAction Stop
  $statusCode = [int]$assignResp.StatusCode
  
  if ($statusCode -eq 200 -or $statusCode -eq 202) { 
    Log "Successfully assigned workspaces on capacity '$capName' to domain '$DomainName' (HTTP $statusCode)."
    $DeploymentScriptOutputs = @{
      domainAssigned = $true
      domainId = $domainId
      workspaceId = $workspaceId
      capacityGuid = $capacityGuid
    }
  } else { 
    Warn "Domain assignment failed (HTTP $statusCode)."
    $DeploymentScriptOutputs = @{
      domainAssigned = $false
      message = "Manual assignment required via Fabric Admin Portal"
    }
  }
} catch {
  Warn "Domain assignment failed: $_"
  $DeploymentScriptOutputs = @{
    domainAssigned = $false
    message = "Manual assignment required via Fabric Admin Portal"
  }
}
    '''
  }
}

// Outputs
output domainAssigned bool = assignDomainDeploymentScript.properties.outputs.domainAssigned
output domainId string = assignDomainDeploymentScript.properties.outputs.?domainId ?? ''
output workspaceId string = assignDomainDeploymentScript.properties.outputs.?workspaceId ?? ''
