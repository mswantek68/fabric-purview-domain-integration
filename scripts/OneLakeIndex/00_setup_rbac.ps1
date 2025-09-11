# OneLake AI Search RBAC Setup
# Sets up managed identity permissions for OneLake indexing

[CmdletBinding()]
param(
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Log([string]$m) { Write-Host "[onelake-rbac] $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Warning "[onelake-rbac] $m" }

Log "=================================================================="
Log "Setting up RBAC permissions for OneLake AI Search integration"
Log "=================================================================="

try {
  Log "Checking for AI Search deployment outputs..."

  # Get azd environment values
  $azdEnvValues = azd env get-values 2>$null
  if (-not $azdEnvValues) {
    Log "No azd outputs found, skipping RBAC setup"
    exit 0
  }

  # Parse environment variables
  $env_vars = @{}
  foreach ($line in $azdEnvValues) {
    if ($line -match '^(.+?)=(.*)$') {
      $env_vars[$matches[1]] = $matches[2].Trim('"')
    }
  }

  # Extract required values
  $aiSearchName = $env_vars['aiSearchName']
  $aiSearchResourceGroup = $env_vars['aiSearchResourceGroup'] 
  $aiSearchSubscriptionId = $env_vars['aiSearchSubscriptionId']
  $aiFoundryName = $env_vars['aiFoundryName']

  if (-not $aiSearchName -or -not $aiSearchResourceGroup) {
    Log "Missing AI Search details, skipping RBAC setup"
    Log "aiSearchName: $aiSearchName"
    Log "aiSearchResourceGroup: $aiSearchResourceGroup"
    exit 0
  }

  # Get AI Search managed identity principal ID directly from Azure
  Log "Getting AI Search managed identity principal ID..."
  try {
    $aiSearchResource = az search service show --name $aiSearchName --resource-group $aiSearchResourceGroup --subscription $aiSearchSubscriptionId --query "identity.principalId" -o tsv 2>$null
    if (-not $aiSearchResource -or $aiSearchResource -eq "null") {
      Log "AI Search service does not have managed identity enabled"
      Log "Please enable system-assigned managed identity on AI Search service: $aiSearchName"
      exit 0
    }
    $principalId = $aiSearchResource.Trim()
    Log "Found AI Search managed identity: $principalId"
  } catch {
    Warn "Failed to get AI Search managed identity: $($_.Exception.Message)"
    exit 0
  }

  Log "✅ RBAC setup conditions met!"
  Log "  AI Search: $aiSearchName"
  Log "  AI Foundry: $aiFoundryName"
  if ($principalId) { Log "  Principal ID: $principalId" }

  # Setup RBAC permissions
  if ($principalId) {
    Log ""
    Log "🔐 Setting up RBAC permissions for OneLake indexing..."
    
    try {
      & "$PSScriptRoot/../setup_ai_services_rbac.ps1" `
        -ExecutionManagedIdentityPrincipalId $principalId `
        -AISearchName $aiSearchName `
        -AIFoundryName $aiFoundryName `
        -AISearchResourceGroup $aiSearchResourceGroup
      
      Log "✅ RBAC configuration completed successfully"
      Log "✅ Managed identity can now access AI Search and AI Foundry"
      Log "✅ OneLake indexing permissions are configured"
    } catch {
      Warn "RBAC setup failed: $_"
      Log "You can run RBAC setup manually later with:"
      Log "  ./scripts/setup_ai_services_rbac.ps1 -ExecutionManagedIdentityPrincipalId '$principalId' -AISearchName '$aiSearchName' -AIFoundryName '$aiFoundryName'"
      throw
    }
  }

  Log ""
  Log "📋 RBAC Setup Summary:"
  Log "✅ Managed identity has AI Search access"
  Log "✅ Managed identity has AI Foundry access"
  Log "✅ OneLake indexing will work with proper authentication"
  Log ""
  Log "Next: Run the OneLake skillset, data source, and indexer scripts"

} catch {
  Warn "RBAC setup encountered an error: $_"
  Log "This may prevent OneLake indexing from working properly"
  Log "Check the error above and retry if needed"
  throw
}
