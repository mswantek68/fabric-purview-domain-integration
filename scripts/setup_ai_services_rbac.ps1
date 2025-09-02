<#
.SYNOPSIS
  Configure RBAC permissions for managed identities to access AI Search and AI Foundry services
.DESCRIPTION
  This script assigns the necessary RBAC roles to managed identities for accessing AI Search and AI Foundry services.
  Supports cross-subscription scenarios and handles different authentication patterns.
.PARAMETER ExecutionManagedIdentityPrincipalId
  Principal ID of the managed identity that will execute AI Search operations
.PARAMETER AISearchName
  Name of the AI Search service
.PARAMETER AISearchSubscriptionId
  Subscription ID where AI Search is deployed (optional)
.PARAMETER AISearchResourceGroup
  Resource group where AI Search is deployed (optional)
.PARAMETER AIFoundryName
  Name of the AI Foundry service
.PARAMETER AIFoundrySubscriptionId
  Subscription ID where AI Foundry is deployed (optional)
.PARAMETER AIFoundryResourceGroup
  Resource group where AI Foundry is deployed (optional)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$ExecutionManagedIdentityPrincipalId,
  
  [Parameter(Mandatory=$true)]
  [string]$AISearchName,
  
  [string]$AISearchSubscriptionId,
  [string]$AISearchResourceGroup,
  
  [Parameter(Mandatory=$true)]
  [string]$AIFoundryName,
  
  [string]$AIFoundrySubscriptionId,
  [string]$AIFoundryResourceGroup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Role definitions
$searchContributorRole = "7ca78c08-252a-4471-8644-bb5ff32d4ba0"  # Search Service Contributor
$cognitiveServicesContributorRole = "25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68"  # Cognitive Services Contributor

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARN") { "Yellow" } else { "Green" })
}

function Get-CurrentContext {
  $currentSub = & az account show --query id -o tsv 2>$null
  $currentRg = $env:AZURE_RESOURCE_GROUP
  if (-not $currentRg) {
    try {
      $currentRg = & az configure --list-defaults --query "[?name=='group'].value" -o tsv 2>$null
    } catch {
      $currentRg = $null
    }
  }
  return @{ SubscriptionId = $currentSub; ResourceGroup = $currentRg }
}

function Set-SubscriptionContext {
  param([string]$SubscriptionId)
  if ($SubscriptionId -and $SubscriptionId -ne "") {
    Write-Log "Switching to subscription: $SubscriptionId"
    & az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to switch to subscription $SubscriptionId"
    }
  }
}

function Get-ResourceId {
  param(
    [string]$ResourceName,
    [string]$ResourceType,
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [hashtable]$CurrentContext
  )
  
  $targetSub = if ($SubscriptionId -and $SubscriptionId -ne "") { $SubscriptionId } else { $CurrentContext.SubscriptionId }
  $targetRg = if ($ResourceGroup -and $ResourceGroup -ne "") { $ResourceGroup } else { $CurrentContext.ResourceGroup }
  
  if (-not $targetSub -or -not $targetRg) {
    throw "Cannot determine subscription ID or resource group for $ResourceName"
  }
  
  return "/subscriptions/$targetSub/resourceGroups/$targetRg/providers/$ResourceType/$ResourceName"
}

function Assign-RoleIfNeeded {
  param(
    [string]$PrincipalId,
    [string]$RoleDefinitionId,
    [string]$Scope,
    [string]$ServiceName
  )
  
  Write-Log "Checking RBAC assignment for $ServiceName..."
  
  # Check if assignment already exists
  $existingAssignment = & az role assignment list --assignee $PrincipalId --role $RoleDefinitionId --scope $Scope --query "[0].id" -o tsv 2>$null
  
  if ($existingAssignment) {
    Write-Log "RBAC assignment already exists for $ServiceName" "INFO"
    return
  }
  
  Write-Log "Creating RBAC assignment for $ServiceName..."
  & az role assignment create --assignee $PrincipalId --role $RoleDefinitionId --scope $Scope
  
  if ($LASTEXITCODE -eq 0) {
    Write-Log "Successfully assigned role for $ServiceName" "INFO"
  } else {
    Write-Log "Failed to assign role for $ServiceName" "ERROR"
    throw "RBAC assignment failed for $ServiceName"
  }
}

try {
  Write-Log "Starting RBAC configuration for AI services..."
  
  # Get current context
  $currentContext = Get-CurrentContext
  Write-Log "Current context: Subscription=$($currentContext.SubscriptionId), ResourceGroup=$($currentContext.ResourceGroup)"
  
  # Store original subscription
  $originalSubscription = $currentContext.SubscriptionId
  
  # Configure AI Search RBAC
  Write-Log "Configuring AI Search RBAC..."
  Set-SubscriptionContext -SubscriptionId $AISearchSubscriptionId
  
  $searchResourceId = Get-ResourceId -ResourceName $AISearchName -ResourceType "Microsoft.Search/searchServices" -SubscriptionId $AISearchSubscriptionId -ResourceGroup $AISearchResourceGroup -CurrentContext $currentContext
  Write-Log "AI Search Resource ID: $searchResourceId"
  
  Assign-RoleIfNeeded -PrincipalId $ExecutionManagedIdentityPrincipalId -RoleDefinitionId $searchContributorRole -Scope $searchResourceId -ServiceName "AI Search"
  
  # Configure AI Foundry RBAC
  Write-Log "Configuring AI Foundry RBAC..."
  Set-SubscriptionContext -SubscriptionId $AIFoundrySubscriptionId
  
  $foundryResourceId = Get-ResourceId -ResourceName $AIFoundryName -ResourceType "Microsoft.CognitiveServices/accounts" -SubscriptionId $AIFoundrySubscriptionId -ResourceGroup $AIFoundryResourceGroup -CurrentContext $currentContext
  Write-Log "AI Foundry Resource ID: $foundryResourceId"
  
  Assign-RoleIfNeeded -PrincipalId $ExecutionManagedIdentityPrincipalId -RoleDefinitionId $cognitiveServicesContributorRole -Scope $foundryResourceId -ServiceName "AI Foundry"
  
  # Restore original subscription
  if ($originalSubscription) {
    Set-SubscriptionContext -SubscriptionId $originalSubscription
  }
  
  Write-Log "RBAC configuration completed successfully!" "INFO"
  
} catch {
  Write-Log "Error during RBAC configuration: $($_.Exception.Message)" "ERROR"
  
  # Restore original subscription on error
  if ($originalSubscription) {
    try { Set-SubscriptionContext -SubscriptionId $originalSubscription } catch { }
  }
  
  throw
}
