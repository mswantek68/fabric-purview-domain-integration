<#
.SYNOPSIS
  Conditionally set up AI Search integration if AI services are deployed
.DESCRIPTION
  This script checks if AI Search and AI Foundry are deployed as part of the infrastructure
  and automatically configures RBAC and indexers if conditions are met.
.PARAMETER Force
  Force setup even if conditions are not automatically detected
#>

[CmdletBinding()]
param(
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Log([string]$m) { Write-Host "[ai-search-auto] $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Warning "[ai-search-auto] $m" }
function Fail([string]$m) { Write-Error "[ai-search-auto] $m"; exit 1 }

try {
  Log "Checking for AI Search auto-setup conditions..."

  # Check if azd outputs are available
  if (-not (Test-Path '/tmp/azd-outputs.json')) {
    Log "No azd outputs found, skipping AI Search setup"
    exit 0
  }

  $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json

  # Check if AI service names are provided
  $aiSearchName = $outputs.aiSearchName.value
  $aiFoundryName = $outputs.aiFoundryName.value
  
  if (-not $aiSearchName -or -not $aiFoundryName) {
    Log "AI service names not configured, skipping AI Search setup"
    Log "To enable: provide aiSearchName and aiFoundryName parameters"
    exit 0
  }

  # Check if execution managed identity principal ID is available
  $principalId = $outputs.executionManagedIdentityPrincipalId.value
  
  if (-not $principalId -and -not $Force) {
    Log "Execution managed identity principal ID not provided, skipping RBAC setup"
    Log "To enable: provide executionManagedIdentityPrincipalId parameter or use -Force"
    Log "You can run AI Search setup manually later"
    exit 0
  }

  Log "✅ AI Search auto-setup conditions met!"
  Log "  AI Search: $aiSearchName"
  Log "  AI Foundry: $aiFoundryName"
  if ($principalId) { Log "  Principal ID: $principalId" }

  # Auto-setup RBAC if principal ID is available
  if ($principalId) {
    Log ""
    Log "🔐 Setting up RBAC permissions automatically..."
    
    try {
      & "$PSScriptRoot/setup_ai_services_rbac.ps1" `
        -ExecutionManagedIdentityPrincipalId $principalId `
        -AISearchName $aiSearchName `
        -AIFoundryName $aiFoundryName
      
      Log "✅ RBAC configuration completed automatically"
    } catch {
      Warn "Automatic RBAC setup failed: $_"
      Log "You can run RBAC setup manually later with:"
      Log "  ./scripts/setup_ai_services_rbac.ps1 -ExecutionManagedIdentityPrincipalId '$principalId' -AISearchName '$aiSearchName' -AIFoundryName '$aiFoundryName'"
    }
  }

  # Check if lakehouses exist before setting up indexers
  if (-not (Test-Path '/tmp/fabric_workspace.env')) {
    Warn "Fabric workspace not found, skipping indexer setup"
    exit 0
  }

  # Setup OneLake indexers automatically
  Log ""
  Log "📋 Setting up OneLake indexers automatically..."
  
  try {
    & "$PSScriptRoot/setup_document_indexers.ps1" -Categories "all"
    Log "✅ OneLake indexers created successfully"
    Log "📁 Upload documents to lakehouse folders - indexers will process them automatically"
  } catch {
    Warn "Automatic indexer setup failed: $_"
    Log "You can run indexer setup manually later:"
    Log "  ./scripts/setup_document_indexers.ps1 -Categories 'all'"
  }

  Log ""
  Log "🎉 AI Search auto-setup completed successfully!"
  
} catch {
  Warn "AI Search auto-setup encountered an error: $_"
  Log "You can run AI Search setup manually later"
  exit 0  # Don't fail the deployment
}
