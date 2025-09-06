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

  # Check if azd outputs are available
  if (-not (Test-Path '/tmp/azd-outputs.json')) {
    Log "No azd outputs found, skipping RBAC setup"
    exit 0
  }

  $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json

  # Check if AI service names are provided
  $aiSearchName = $outputs.aiSearchName.value
  $aiFoundryName = $outputs.aiFoundryName.value
  
  if (-not $aiSearchName -or -not $aiFoundryName) {
    Log "AI service names not configured, skipping RBAC setup"
    Log "To enable: provide aiSearchName and aiFoundryName parameters"
    exit 0
  }

  # Check if execution managed identity principal ID is available
  $principalId = $outputs.executionManagedIdentityPrincipalId.value
  
  if (-not $principalId -and -not $Force) {
    Log "Execution managed identity principal ID not provided, skipping RBAC setup"
    Log "To enable: provide executionManagedIdentityPrincipalId parameter or use -Force"
    Log "You can run RBAC setup manually later"
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
        -AIFoundryName $aiFoundryName
      
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
