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

  # Check if azd outputs are available via azd env or environment variables
  $outputs = $null
  
  # Try to get values from azd environment
  try {
    # Create a mock outputs object from azd env and environment variables
    $outputs = @{
      aiSearchName = @{ value = $null }
      aiFoundryName = @{ value = $null }
      executionManagedIdentityPrincipalId = @{ value = $null }
    }
    
    # Try azd env get-values first
    try {
      $aiSearchName = & azd env get-value aiSearchName 2>$null
      $aiFoundryName = & azd env get-value aiFoundryName 2>$null
      $principalId = & azd env get-value executionManagedIdentityPrincipalId 2>$null
      
      if ($aiSearchName) { $outputs.aiSearchName.value = $aiSearchName }
      if ($aiFoundryName) { $outputs.aiFoundryName.value = $aiFoundryName }
      if ($principalId) { $outputs.executionManagedIdentityPrincipalId.value = $principalId }
    } catch {
      Log "Could not get values from azd env, trying environment variables"
    }
    
    # Fallback to environment variables
    if (-not $outputs.aiSearchName.value -and $env:aiSearchName) { $outputs.aiSearchName.value = $env:aiSearchName }
    if (-not $outputs.aiFoundryName.value -and $env:aiFoundryName) { $outputs.aiFoundryName.value = $env:aiFoundryName }
    if (-not $outputs.executionManagedIdentityPrincipalId.value -and $env:executionManagedIdentityPrincipalId) { 
      $outputs.executionManagedIdentityPrincipalId.value = $env:executionManagedIdentityPrincipalId 
    }
    
  } catch {
    Log "Could not retrieve configuration values"
  }
  
  # Fallback to reading azd-outputs.json if it exists
  if (-not $outputs -and (Test-Path '/tmp/azd-outputs.json')) {
    try {
      $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
    } catch {
      Log "Could not read azd outputs file"
    }
  }
  
  if (-not $outputs) {
    Log "No configuration available, skipping AI Search setup"
    exit 0
  }

  # Check if AI service names are provided
  $aiSearchName = $outputs.aiSearchName.value
  $aiFoundryName = $outputs.aiFoundryName.value
  # Attempt to capture custom endpoint for AI Search if provided in env/outputs
  try {
    $aiSearchCustomEndpoint = & azd env get-value aiSearchCustomEndpoint 2>$null
    if ($aiSearchCustomEndpoint -and $aiSearchCustomEndpoint -ne '') {
      $env:AI_SEARCH_CUSTOM_ENDPOINT = $aiSearchCustomEndpoint.TrimEnd('/')
      Log "Using custom AI Search endpoint: $env:AI_SEARCH_CUSTOM_ENDPOINT"
    }
  } catch { }
  
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
      Warn "Automatic RBAC setup failed: $($_.Exception.Message)"
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
  
  # Get workspace ID for indexer configuration
  $workspaceId = $null
  if (Test-Path '/tmp/fabric_workspace.env') {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $script:workspaceId = $Matches[1].Trim() }
    }
  }
  
  try {
    & "$PSScriptRoot/setup_document_indexers.ps1" `
      -Categories "all" `
      -AISearchName $AISearchName `
      -WorkspaceId $workspaceId `
      -LakehouseName "bronze"
      
    Log "✅ OneLake indexers created successfully"
    Log "📁 Upload documents to lakehouse folders - indexers will process them automatically"
  } catch {
    Warn "Automatic indexer setup failed: $($_.Exception.Message)"
    Log "You can run indexer setup manually later:"
    Log "  ./scripts/setup_document_indexers.ps1 -Categories 'all' -AISearchName '$AISearchName'"
  }

  # If indexer setup succeeded but OneLake datasource creation fails due to unsupported connector, provide fallback guidance
  if (Test-Path '/tmp/onelake_connector_unsupported.flag') {
    Warn "OneLake connector not available on this Search service. You can enable preview or use a push ingestion fallback."
    Log  "Fallback (manual): ./scripts/push_documents_to_search.ps1 -FolderPath 'Files/documents/manuals' -AISearchName '$AISearchName'"
  }

  Log ""
  Log "🎉 AI Search auto-setup completed successfully!"
  
} catch {
  Warn "AI Search auto-setup encountered an error: $($_.Exception.Message)"
  Log "You can run AI Search setup manually later"
  exit 0  # Don't fail the deployment
}
