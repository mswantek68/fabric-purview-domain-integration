<#
.SYNOPSIS
  Set up AI Search OneLake indexers for standard document categories
.DESCRIPTION
  This script creates OneLake indexers for the standard document folder structure
  in the bronze lakehouse. It sets up indexes for contracts, reports, policies, and manuals.
.PARAMETER Categories
  Document categories to set up indexers for. Options: contracts, reports, policies, manuals, all
.PARAMETER ScheduleIntervalMinutes
  How often the indexers should run (default: 60 minutes)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("contracts", "reports", "policies", "manuals", "all")]
  [string[]]$Categories,
  
  [int]$ScheduleIntervalMinutes = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[setup-document-indexers] $m" }

# Get document configuration from bicep outputs if available
$documentBaseFolderPath = "Files/documents"
$documentCategoriesConfig = @{}

if (Test-Path '/tmp/azd-outputs.json') {
  try {
    $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
    $documentBaseFolderPath = $outputs.documentBaseFolderPath.value
    $categoriesJson = $outputs.documentCategories.value | ConvertFrom-Json
    
    # Convert JSON to PowerShell hashtable with full configuration
    foreach ($category in $categoriesJson.PSObject.Properties) {
      $categoryName = $category.Name
      $folderName = $category.Value
      $documentCategoriesConfig[$categoryName] = @{
        FolderPath = "$documentBaseFolderPath/$folderName"
        IndexName = "$categoryName-index"
        Description = "Documents in the $categoryName category"
      }
    }
    
    Log "Using document configuration from bicep outputs:"
    Log "Base folder: $documentBaseFolderPath"
    Log "Categories: $($documentCategoriesConfig.Keys -join ', ')"
  } catch {
    Log "Could not read document configuration from azd outputs, using defaults"
  }
}

# Fallback to default configuration if bicep outputs not available
if ($documentCategoriesConfig.Count -eq 0) {
  $documentCategoriesConfig = @{
    "contracts" = @{
      FolderPath = "Files/documents/contracts"
      IndexName = "contracts-index"
      Description = "Contract documents and legal agreements"
    }
    "reports" = @{
      FolderPath = "Files/documents/reports" 
      IndexName = "reports-index"
      Description = "Business reports and analytics"
    }
    "policies" = @{
      FolderPath = "Files/documents/policies"
      IndexName = "policies-index" 
      Description = "Policy and procedure documents"
    }
    "manuals" = @{
      FolderPath = "Files/documents/manuals"
      IndexName = "manuals-index"
      Description = "User guides and technical manuals"
    }
  }
}

# Expand "all" to include all categories
if ($Categories -contains "all") {
  $Categories = $documentCategoriesConfig.Keys
}

Log "Setting up OneLake indexers for document categories: $($Categories -join ', ')"
Log "Schedule: Every $ScheduleIntervalMinutes minutes"

$successCount = 0
$failureCount = 0

foreach ($category in $Categories) {
  if ($documentCategoriesConfig.ContainsKey($category)) {
    $config = $documentCategoriesConfig[$category]
    
    Log ""
    Log "Setting up indexer for: $category"
    Log "Folder: $($config.FolderPath)"
    Log "Index: $($config.IndexName)"
    
    try {
      & "$PSScriptRoot/create_onelake_indexer.ps1" `
        -FolderPath $config.FolderPath `
        -IndexName $config.IndexName `
        -ScheduleIntervalMinutes $ScheduleIntervalMinutes
      
      Log "✅ Successfully set up indexer for $category"
      $successCount++
      
    } catch {
      Log "❌ Failed to set up indexer for $category: $_"
      $failureCount++
    }
  } else {
    Log "❌ Unknown category: $category"
    $failureCount++
  }
  
  # Small delay between indexer creations
  Start-Sleep -Seconds 2
}

Log ""
Log "Setup completed: $successCount successful, $failureCount failed"

if ($successCount -gt 0) {
  Log ""
  Log "📋 Next steps:"
  Log "1. Upload documents to the bronze lakehouse folders:"
  foreach ($category in $Categories) {
    if ($documentCategoriesConfig.ContainsKey($category)) {
      Log "   - $($documentCategoriesConfig[$category].FolderPath)"
    }
  }
  Log "2. Indexers will automatically detect and index new documents"
  Log "3. Connect indexes to AI Foundry using:"
  Log "   ./scripts/connect_search_to_ai_foundry.ps1 -IndexName <index-name>"
}
