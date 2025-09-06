<#
.SYNOPSIS
  Post-provision orchestration for OneLake folder virtualization and OneLake indexer setup
.DESCRIPTION
  This script is intended to be run as a postprovision hook (via azure.yaml). It will:
  - Read azd outputs and environment files to discover workspace, lakehouse and AI Search/Foundry names
  - Virtualize document folders in the document lakehouse by creating a small README placeholder file
  - Optionally configure RBAC for the execution managed identity to access AI Search and AI Foundry
  - Create OneLake indexers for the standard document categories
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[postprovision-onelake] $m" }
function Warn([string]$m){ Write-Warning "[postprovision-onelake] $m" }
function Fail([string]$m){ Write-Error "[postprovision-onelake] $m"; exit 1 }

# Attempt to read azd outputs if present
$azdOutputs = $null
if (Test-Path '/tmp/azd-outputs.json') {
  try { $azdOutputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json } catch { $azdOutputs = $null }
}

# Workspace id detection
$workspaceId = $env:WORKSPACE_ID
if ((-not $workspaceId) -and (Test-Path '/tmp/fabric_workspace.env')) {
  Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
    if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $workspaceId = $Matches[1].Trim() }
  }
}

if (-not $workspaceId -and $azdOutputs -and $azdOutputs.fabricWorkspaceId) {
  $workspaceId = $azdOutputs.fabricWorkspaceId.value
}

# Lakehouse name
$documentLakehouseName = 'bronze'
if ($azdOutputs -and $azdOutputs.documentLakehouseName) { $documentLakehouseName = $azdOutputs.documentLakehouseName.value }

# AI Search / Foundry / principal outputs
$aiSearchName = $null; $aiFoundryName = $null; $execMsiPrincipalId = $null
if ($azdOutputs) {
  if ($azdOutputs.aiSearchName) { $aiSearchName = $azdOutputs.aiSearchName.value }
  if ($azdOutputs.aiFoundryName) { $aiFoundryName = $azdOutputs.aiFoundryName.value }
  if ($azdOutputs.executionManagedIdentityPrincipalId) { $execMsiPrincipalId = $azdOutputs.executionManagedIdentityPrincipalId.value }
}

Log "WorkspaceId: $workspaceId"
Log "Document lakehouse: $documentLakehouseName"
if ($aiSearchName) { Log "AI Search: $aiSearchName" }
if ($aiFoundryName) { Log "AI Foundry: $aiFoundryName" }
if ($execMsiPrincipalId) { Log "Execution managed identity principal ID: $execMsiPrincipalId" }

if (-not $workspaceId) { Warn 'WorkspaceId not found; virtualization and indexer creation may fail; supply WORKSPACE_ID env var or ensure /tmp/fabric_workspace.env exists' }

# Folders to virtualize
$foldersToVirtualize = @(
  'Files/documents',
  'Files/documents/contracts',
  'Files/documents/reports',
  'Files/documents/policies',
  'Files/documents/manuals'
)

# Prepare readme content
$readme = @"
Placeholder used to virtualize the OneLake folder so users can see it in the UI.
Upload documents to this folder to enable OneLake indexing.
"@

foreach ($f in $foldersToVirtualize) {
  try {
    Log "Virtualizing: $f"
    & "$PSScriptRoot/virtualize_onelake_folder.ps1" -WorkspaceId $workspaceId -LakehouseName $documentLakehouseName -FolderPath $f -Content $readme
  } catch {
    $msg = $_.Exception.Message
    Warn "Virtualization failed for $f`: $msg"
  }
}

# If execution MSI principal id present and AI search/foundry provided, attempt RBAC setup
if ($execMsiPrincipalId -and $aiSearchName -and $aiFoundryName) {
  try {
    Log "Configuring RBAC for execution managed identity on AI Search and AI Foundry..."
    & "$PSScriptRoot/setup_ai_services_rbac.ps1" -ExecutionManagedIdentityPrincipalId $execMsiPrincipalId -AISearchName $aiSearchName -AIFoundryName $aiFoundryName
    Log "RBAC configured successfully"
  } catch {
    Warn "RBAC configuration failed: $_"
  }
} else {
  Log "Skipping automatic RBAC: missing principal ID or AI service names"
}

# Create indexers for all categories using the working approach
try {
  Log "Creating document indexers (all categories) with working OneLake indexer method..."
  
  # Use the proven working approach that handles all the edge cases
  $documentFolders = @("Files/documents/contracts", "Files/documents/reports", "Files/documents/presentations")
  
  foreach ($folder in $documentFolders) {
    $folderName = ($folder -split '/')[-1]  # Get last part (contracts, reports, etc.)
    Log "Setting up indexer for: $folderName"
    
    try {
      & "$PSScriptRoot/create_onelake_indexer.ps1" `
        -FolderPath $folder `
        -IndexName "files-documents-$folderName" `
        -WorkspaceId $workspaceId `
        -AISearchName $aiSearchName `
        -LakehouseName $documentLakehouseName `
        -ScheduleIntervalMinutes 60
      
      Log "✅ Successfully created indexer for $folderName"
    } catch {
      Log "⚠️ Failed to create indexer for $folderName`: $_"
    }
    
    Start-Sleep -Seconds 2  # Brief pause between creations
  }
  
  Log "OneLake indexing automation completed"
} catch {
  Warn "OneLake indexer setup failed: $_"
}

# Add AI skillsets for enhanced document processing
try {
  Log "Adding AI skillsets to OneLake indexers..."
  
  # Use simple skillset addition script
  & "$PSScriptRoot/add_onelake_skillsets.ps1" -AISearchName $aiSearchName
  
  Log "✅ AI skillsets added successfully"
} catch {
  Warn "AI skillset setup failed: $_"
  Log "OneLake indexers will still work for basic document search"
}

Log "Post-provision OneLake indexing orchestration finished"
exit 0
