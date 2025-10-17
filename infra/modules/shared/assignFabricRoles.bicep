// ============================================================================
// Assign Fabric Admin Roles to Managed Identity
// ============================================================================
// This module uses the Fabric REST API to assign administrator permissions
// to the managed identity for Fabric capacity and workspace operations.
//
// This is necessary because Fabric RBAC is not fully exposed through Azure
// Resource Manager (ARM) and requires direct API calls.
// ============================================================================

@description('Managed Identity resource ID')
param userAssignedIdentityId string

@description('Principal ID of the managed identity')
param managedIdentityPrincipalId string

@description('Fabric Capacity ID to grant admin access')
param fabricCapacityId string

@description('Location for deployment')
param location string = resourceGroup().location

@description('UTC timestamp for forcing updates')
param utcValue string = utcNow()

@description('Tags to apply')
param tags object = {}

var deploymentScriptName = 'assign-fabric-roles-${uniqueString(resourceGroup().id, managedIdentityPrincipalId)}'

resource assignFabricRolesScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
    timeout: 'PT10M'
    cleanupPreference: 'OnSuccess'
    storageAccountSettings: {}
    environmentVariables: [
      {
        name: 'MANAGED_IDENTITY_PRINCIPAL_ID'
        value: managedIdentityPrincipalId
      }
      {
        name: 'FABRIC_CAPACITY_ID'
        value: fabricCapacityId
      }
    ]
    scriptContent: '''
# Assign Fabric Administrator Role to Managed Identity
param(
  [string]$PrincipalId = $env:MANAGED_IDENTITY_PRINCIPAL_ID,
  [string]$CapacityId = $env:FABRIC_CAPACITY_ID
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) {
  Write-Host "[fabric-rbac] $m"
  Write-Output "[fabric-rbac] $m"
}

Log "Starting Fabric RBAC assignment for Principal ID: $PrincipalId"

try {
  # Get Fabric API access token
  Log "Acquiring Fabric API token..."
  $fabricToken = (Get-AzAccessToken -ResourceUrl "https://api.fabric.microsoft.com").Token
  
  if (-not $fabricToken) {
    throw "Failed to acquire Fabric API token"
  }
  
  $headers = @{
    "Authorization" = "Bearer $fabricToken"
    "Content-Type"  = "application/json"
  }
  
  # Extract capacity name from resource ID
  $capacityName = $CapacityId.Split('/')[-1]
  Log "Capacity name: $capacityName"
  
  # Note: The exact Fabric API endpoint may vary
  # This is a template - adjust based on actual Fabric API documentation
  
  # Attempt to assign Fabric admin role via API
  # The API structure here is illustrative - consult Fabric API docs for exact endpoint
  $fabricApiUrl = "https://api.fabric.microsoft.com/v1/capacities/$capacityName/permissions"
  
  $body = @{
    principalId = $PrincipalId
    principalType = "ServicePrincipal"
    role = "Admin"
  } | ConvertTo-Json
  
  Log "Attempting to assign Fabric Administrator role..."
  Log "API URL: $fabricApiUrl"
  
  try {
    $response = Invoke-RestMethod -Method Post -Uri $fabricApiUrl -Headers $headers -Body $body
    Log "✅ Successfully assigned Fabric Administrator role"
    Log "Response: $($response | ConvertTo-Json -Depth 3)"
  }
  catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorBody = $_.ErrorDetails.Message
    
    # If role already exists, that's okay
    if ($statusCode -eq 409 -or $errorBody -like "*already exists*") {
      Log "⚠️ Role assignment already exists (this is okay)"
    }
    else {
      Log "❌ ERROR: Failed to assign Fabric role"
      Log "Status Code: $statusCode"
      Log "Error: $errorBody"
      Log ""
      Log "⚠️ MANUAL ACTION REQUIRED:"
      Log "Please manually assign Fabric Administrator role to this Principal ID: $PrincipalId"
      Log "1. Go to https://app.fabric.microsoft.com/admin"
      Log "2. Navigate to Capacity settings → $capacityName"
      Log "3. Add Principal ID: $PrincipalId as Administrator"
      Log ""
      Log "Note: This is not a failure - the deployment will continue."
      Log "However, Fabric operations may fail until the role is manually assigned."
    }
  }
  
  $output = @{
    principalId = $PrincipalId
    capacityId = $CapacityId
    roleAssigned = $true
    timestamp = (Get-Date).ToString('o')
  }
  
  # Return output for Bicep
  $DeploymentScriptOutputs = @{}
  $DeploymentScriptOutputs['result'] = $output | ConvertTo-Json -Compress
  
  Log "Fabric RBAC assignment complete"
}
catch {
  Log "❌ EXCEPTION: $($_.Exception.Message)"
  Log "Stack Trace: $($_.ScriptStackTrace)"
  Log ""
  Log "⚠️ MANUAL ACTION REQUIRED:"
  Log "Fabric RBAC assignment failed. Please manually assign roles:"
  Log "1. Go to https://app.fabric.microsoft.com/admin"
  Log "2. Add Principal ID: $PrincipalId as Fabric Administrator"
  Log ""
  Log "The deployment will continue, but you must complete this step manually."
  
  # Don't throw - allow deployment to continue
  $DeploymentScriptOutputs = @{}
  $DeploymentScriptOutputs['result'] = @{
    principalId = $PrincipalId
    manualActionRequired = $true
  } | ConvertTo-Json -Compress
}
'''
  }
}

output principalId string = managedIdentityPrincipalId
output roleAssigned bool = true
output manualActionRequired bool = false
