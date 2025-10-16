@description('Creates a Microsoft Fabric workspace using deployment script')
param workspaceName string
param capacityId string
param adminUPNs string = ''
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

@description('Managed Identity for deployment script execution')
param userAssignedIdentityId string

@description('Name of the shared storage account for deployment scripts')
param storageAccountName string


// Generate unique names for deployment script resources
var deploymentScriptName = 'deploy-fabric-workspace-${uniqueString(resourceGroup().id, workspaceName)}'

// Deployment script to create Fabric workspace
resource fabricWorkspaceDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
    }
    environmentVariables: [
      {
        name: 'FABRIC_WORKSPACE_NAME'
        value: workspaceName
      }
      {
        name: 'FABRIC_CAPACITY_ID'
        value: capacityId
      }
      {
        name: 'FABRIC_ADMIN_UPNS'
        value: adminUPNs
      }
    ]
    scriptContent: '''
# Fabric Workspace Creation Script
param(
  [string]$WorkspaceName = $env:FABRIC_WORKSPACE_NAME,
  [string]$CapacityId = $env:FABRIC_CAPACITY_ID,
  [string]$AdminUPNs = $env:FABRIC_ADMIN_UPNS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { 
  Write-Host "[fabric-workspace] $m" 
  Write-Output "[fabric-workspace] $m"
}

if (-not $WorkspaceName) { 
  Write-Error "FABRIC_WORKSPACE_NAME is required"
  throw "FABRIC_WORKSPACE_NAME is required"
}

Log "Starting Fabric workspace creation for: $WorkspaceName"

# Acquire tokens
try { 
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
  if (-not $accessToken) { throw "No token returned" }
} catch { 
  Write-Error "Failed to obtain access token for Fabric API"
  throw "Failed to obtain access token for Fabric API"
}

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'

# Check if workspace already exists
try {
  $workspaces = Invoke-RestMethod -Uri "$apiRoot/groups" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  $existingWorkspace = $null
  if ($workspaces.value) { 
    $existingWorkspace = $workspaces.value | Where-Object { $_.name -eq $WorkspaceName }
  }
  
  if ($existingWorkspace) {
    $workspaceId = $existingWorkspace.id
    Log "Workspace '$WorkspaceName' already exists with ID: $workspaceId"
  } else {
    $workspaceId = $null
  }
} catch {
  Write-Error "Failed to check existing workspaces: $_"
  throw "Failed to check existing workspaces: $_"
}

# Resolve capacity GUID if capacity ARM id given
$capacityGuid = $null
if ($CapacityId) {
  $capName = ($CapacityId -split '/')[-1]
  Log "Resolving capacity GUID for: $capName"
  
  try { 
    $caps = Invoke-RestMethod -Uri "$apiRoot/admin/capacities" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    if ($caps.value) { 
      foreach ($cap in $caps.value) {
        $capDisplayName = if ($cap.PSObject.Properties['displayName']) { $cap.displayName } else { '' }
        $capName2 = if ($cap.PSObject.Properties['name']) { $cap.name } else { '' }
        
        if ($capDisplayName -eq $capName -or $capName2 -eq $capName) {
          $capacityGuid = $cap.id
          Log "Found capacity '$capDisplayName' with GUID: $capacityGuid"
          break
        }
      }
    }
    
    if (-not $capacityGuid) {
      Write-Error "Capacity '$capName' not found"
      throw "Capacity '$capName' not found"
    }
  } catch { 
    Write-Error "Failed to resolve capacity GUID: $_"
    throw "Failed to resolve capacity GUID: $_"
  }
}

# Create workspace if it doesn't exist
if (-not $workspaceId) {
  Log "Creating Fabric workspace '$WorkspaceName'..."
  $createPayload = @{ name = $WorkspaceName; type = 'Workspace' } | ConvertTo-Json -Depth 4
  try {
    $resp = Invoke-WebRequest -Uri "$apiRoot/groups?workspaceV2=true" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body $createPayload -UseBasicParsing -ErrorAction Stop
    $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    $workspaceId = $body.id
    Log "Created workspace with ID: $workspaceId"
  } catch { 
    Write-Error "Workspace creation failed: $_"
    throw "Workspace creation failed: $_"
  }
}

# Assign to capacity if provided
if ($capacityGuid -and $workspaceId) {
  try {
    Log "Assigning workspace to capacity GUID: $capacityGuid"
    $assignResp = Invoke-WebRequest -Uri "$apiRoot/groups/$workspaceId/AssignToCapacity" -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body (@{ capacityId = $capacityGuid } | ConvertTo-Json) -UseBasicParsing -ErrorAction Stop
    Log "Capacity assignment completed"
  } catch { 
    Write-Error "Capacity assignment failed: $_"
    throw "Capacity assignment failed: $_"
  }
}

Log "Fabric workspace deployment completed"

# Set outputs for Bicep
$DeploymentScriptOutputs = @{
  workspaceId = $workspaceId
  workspaceName = $WorkspaceName
  capacityId = $capacityGuid
}
    '''
  }
}

// Outputs
output workspaceId string = fabricWorkspaceDeploymentScript.properties.outputs.workspaceId
output workspaceName string = fabricWorkspaceDeploymentScript.properties.outputs.workspaceName
output capacityId string = fabricWorkspaceDeploymentScript.properties.outputs.capacityId
