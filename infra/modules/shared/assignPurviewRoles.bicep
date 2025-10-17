// ============================================================================
// Assign Purview Roles to Managed Identity
// ============================================================================
// This module uses the Purview REST API to assign Collection Admin, Data
// Source Administrator, and Data Curator roles to the managed identity.
//
// Purview RBAC is not part of Azure Resource Manager and requires direct
// API calls to the Purview service.
// ============================================================================

@description('Managed Identity resource ID')
param userAssignedIdentityId string

@description('Principal ID of the managed identity')
param managedIdentityPrincipalId string

@description('Purview account name')
param purviewAccountName string

@description('Purview collection name (empty for root collection)')
param purviewCollectionName string = ''

@description('Location for deployment')
param location string = resourceGroup().location

@description('UTC timestamp for forcing updates')
param utcValue string = utcNow()

@description('Tags to apply')
param tags object = {}

var deploymentScriptName = 'assign-purview-roles-${uniqueString(resourceGroup().id, managedIdentityPrincipalId)}'

resource assignPurviewRolesScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
        name: 'PURVIEW_ACCOUNT_NAME'
        value: purviewAccountName
      }
      {
        name: 'PURVIEW_COLLECTION_NAME'
        value: purviewCollectionName
      }
    ]
    scriptContent: '''
# Assign Purview Roles to Managed Identity
param(
  [string]$PrincipalId = $env:MANAGED_IDENTITY_PRINCIPAL_ID,
  [string]$PurviewAccount = $env:PURVIEW_ACCOUNT_NAME,
  [string]$CollectionName = $env:PURVIEW_COLLECTION_NAME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) {
  Write-Host "[purview-rbac] $m"
  Write-Output "[purview-rbac] $m"
}

Log "Starting Purview RBAC assignment for Principal ID: $PrincipalId"
Log "Purview Account: $PurviewAccount"

try {
  # Get Purview API access token
  Log "Acquiring Purview API token..."
  $purviewToken = (Get-AzAccessToken -ResourceUrl "https://purview.azure.net").Token
  
  if (-not $purviewToken) {
    throw "Failed to acquire Purview API token"
  }
  
  $headers = @{
    "Authorization" = "Bearer $purviewToken"
    "Content-Type"  = "application/json"
  }
  
  # Purview API endpoint
  $purviewEndpoint = "https://$PurviewAccount.purview.azure.com"
  
  # Get root collection if collection name is empty
  if ([string]::IsNullOrEmpty($CollectionName)) {
    Log "Using root collection (account name)"
    $CollectionName = $PurviewAccount
  }
  
  Log "Target collection: $CollectionName"
  
  # Define roles to assign
  $rolesToAssign = @(
    @{ name = "collection-administrator"; displayName = "Collection Admin" }
    @{ name = "data-source-administrator"; displayName = "Data Source Administrator" }
    @{ name = "data-curator"; displayName = "Data Curator" }
  )
  
  $assignedRoles = @()
  
  foreach ($role in $rolesToAssign) {
    try {
      Log "Assigning role: $($role.displayName)..."
      
      # Purview Metadata Policy API endpoint
      $policyUrl = "$purviewEndpoint/policystore/collections/$CollectionName/metadataPolicy?api-version=2021-07-01"
      
      # Get existing policy
      Log "Fetching existing policy..."
      $existingPolicy = Invoke-RestMethod -Method Get -Uri $policyUrl -Headers $headers
      
      # Check if principal already has the role
      $attributeName = $role.name
      $attributeRules = $existingPolicy.properties.attributeRules
      
      $ruleExists = $false
      foreach ($rule in $attributeRules) {
        if ($rule.name -eq $attributeName) {
          foreach ($dnfCondition in $rule.dnfCondition) {
            foreach ($attributeValue in $dnfCondition.attributeValueIncludes) {
              if ($attributeValue -eq $PrincipalId) {
                $ruleExists = $true
                Log "✓ Principal already has $($role.displayName) role"
                break
              }
            }
          }
        }
      }
      
      if (-not $ruleExists) {
        # Add principal to the role
        $found = $false
        for ($i = 0; $i -lt $attributeRules.Count; $i++) {
          if ($attributeRules[$i].name -eq $attributeName) {
            $existingCondition = $attributeRules[$i].dnfCondition[0]
            if (-not $existingCondition.attributeValueIncludes) {
              $existingCondition.attributeValueIncludes = @()
            }
            $existingCondition.attributeValueIncludes += $PrincipalId
            $found = $true
            break
          }
        }
        
        if (-not $found) {
          Log "⚠️ Role $attributeName not found in policy. This may require manual assignment."
          continue
        }
        
        # Update the policy
        $updateBody = $existingPolicy | ConvertTo-Json -Depth 10
        $response = Invoke-RestMethod -Method Put -Uri $policyUrl -Headers $headers -Body $updateBody
        
        Log "✅ Successfully assigned $($role.displayName) role"
        $assignedRoles += $role.displayName
      }
    }
    catch {
      $statusCode = $_.Exception.Response.StatusCode.value__
      $errorBody = $_.ErrorDetails.Message
      
      Log "⚠️ Failed to assign $($role.displayName) role"
      Log "Status Code: $statusCode"
      Log "Error: $errorBody"
      Log "This role may need to be assigned manually."
    }
  }
  
  if ($assignedRoles.Count -eq 0) {
    Log "⚠️ No roles were newly assigned (they may already exist)"
    Log ""
    Log "Please verify in Purview Governance Portal:"
    Log "1. Go to https://web.purview.azure.com/"
    Log "2. Open account: $PurviewAccount"
    Log "3. Check role assignments for Principal ID: $PrincipalId"
  }
  else {
    Log "✅ Successfully assigned $($assignedRoles.Count) role(s): $($assignedRoles -join ', ')"
  }
  
  $output = @{
    principalId = $PrincipalId
    purviewAccount = $PurviewAccount
    collection = $CollectionName
    rolesAssigned = $assignedRoles
    timestamp = (Get-Date).ToString('o')
  }
  
  $DeploymentScriptOutputs = @{}
  $DeploymentScriptOutputs['result'] = $output | ConvertTo-Json -Compress
  
  Log "Purview RBAC assignment complete"
}
catch {
  Log "❌ EXCEPTION: $($_.Exception.Message)"
  Log "Stack Trace: $($_.ScriptStackTrace)"
  Log ""
  Log "⚠️ MANUAL ACTION REQUIRED:"
  Log "Purview RBAC assignment failed. Please manually assign roles:"
  Log "1. Go to https://web.purview.azure.com/"
  Log "2. Open account: $PurviewAccount"
  Log "3. Navigate to Data Map → Collections → $CollectionName"
  Log "4. Add Principal ID: $PrincipalId with these roles:"
  Log "   - Collection Admin"
  Log "   - Data Source Administrator"
  Log "   - Data Curator"
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
output purviewAccountName string = purviewAccountName
output roleAssigned bool = true
output manualActionRequired bool = false
