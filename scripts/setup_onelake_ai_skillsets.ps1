<#
.SYNOPSIS
  Complete automation for adding AI skillsets to OneLake indexers
.DESCRIPTION
  This script orchestrates the creation of AI skillsets and their attachment to
  existing OneLake indexers. It's designed to be run after indexers are created
  to add cognitive capabilities like OCR, entity extraction, and sentiment analysis.
.PARAMETER SkillsetType
  Type of skillset to create and attach: 'basic', 'comprehensive', or 'all'
.PARAMETER IndexerPattern
  Pattern to match indexers (default: "files-documents-*")
.PARAMETER AISearchName
  The name of the Azure AI Search service
.PARAMETER UpdateIndexes
  Whether to update index schemas to support skillset outputs
.PARAMETER TestMode
  Run in test mode (show what would be changed without making changes)
#>

[CmdletBinding()]
param(
  [ValidateSet("basic", "comprehensive", "all")]
  [string]$SkillsetType = "comprehensive",
  
  [string]$IndexerPattern = "files-documents-*",
  [string]$AISearchName,
  [switch]$UpdateIndexes,
  [switch]$TestMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m, [string]$color = "White"){ 
  Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" -ForegroundColor $color 
}
function Success([string]$m){ Log $m "Green" }
function Warn([string]$m){ Log $m "Yellow" }
function Fail([string]$m){ Log $m "Red"; exit 1 }

$testModeText = if ($TestMode) { " (TEST MODE)" } else { "" }
Log "=== OneLake AI Skillsets Complete Automation$testModeText ===" "Cyan"
Log "Skillset type: $SkillsetType"
Log "Indexer pattern: $IndexerPattern"
Log "Update indexes: $UpdateIndexes"
Log ""

# Step 1: Create skillsets
Log "=== Step 1: Creating AI Skillsets ===" "Cyan"
try {
  $skillsetArgs = @(
    "-SkillsetType", $SkillsetType
  )
  if ($AISearchName) { $skillsetArgs += @("-AISearchName", $AISearchName) }
  
  if ($TestMode) {
    Log "TEST MODE: Would create $SkillsetType skillsets" "Yellow"
  } else {
    & "$PSScriptRoot/create_ai_skillsets.ps1" @skillsetArgs
  }
  Success "Skillset creation completed"
} catch {
  Fail "Skillset creation failed: $_"
}

Log ""

# Step 2: Attach skillsets to indexers
Log "=== Step 2: Attaching Skillsets to Indexers ===" "Cyan"
try {
  $attachArgs = @(
    "-IndexerName", $IndexerPattern,
    "-SkillsetType", $SkillsetType
  )
  if ($AISearchName) { $attachArgs += @("-AISearchName", $AISearchName) }
  if ($UpdateIndexes) { $attachArgs += "-UpdateIndex" }
  if ($TestMode) { $attachArgs += "-TestMode" }
  
  & "$PSScriptRoot/attach_skillsets_to_indexers.ps1" @attachArgs
  Success "Skillset attachment completed"
} catch {
  Fail "Skillset attachment failed: $_"
}

Log ""

# Step 3: Trigger indexer runs to process with new skillsets
if (-not $TestMode) {
  Log "=== Step 3: Running Indexers with New Skillsets ===" "Cyan"
  try {
    # Get AI Search configuration
    $config = @{ AISearchName = $AISearchName }
    if (-not $config.AISearchName) {
      if (Test-Path '/tmp/azd-outputs.json') {
        $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
        $config.AISearchName = $outputs.aiSearchName.value
      }
    }
    
    if ($config.AISearchName) {
      $resourceGroup = 'AI_Related'
      $adminKey = & az search admin-key show --service-name $config.AISearchName --resource-group $resourceGroup --query primaryKey -o tsv
      $headers = @{ 'api-key' = $adminKey }
      $endpoint = "https://$($config.AISearchName).search.windows.net"
      
      # Get matching indexers and run them
      $indexers = Invoke-RestMethod -Uri "$endpoint/indexers?api-version=2024-05-01-preview" -Headers $headers
      $matchingIndexers = $indexers.value | Where-Object { $_.name -like $IndexerPattern }
      
      Log "Running $($matchingIndexers.Count) indexers..."
      foreach ($indexer in $matchingIndexers) {
        try {
          Invoke-RestMethod -Uri "$endpoint/indexers/$($indexer.name)/run?api-version=2024-05-01-preview" `
            -Method Post -Headers $headers | Out-Null
          Success "Started indexer: $($indexer.name)"
        } catch {
          Warn "Failed to start indexer $($indexer.name): $($_.Exception.Message)"
        }
      }
    } else {
      Warn "Could not determine AI Search service name, skipping indexer runs"
    }
  } catch {
    Warn "Failed to run indexers: $_"
  }
}

Log ""
Log "=== Complete Automation Summary ===" "Green"
if ($TestMode) {
  Log "🧪 TEST MODE: Simulation completed successfully!" "Yellow"
  Log "Run without -TestMode to apply changes"
} else {
  Log "🎉 AI Skillsets successfully added to OneLake indexers!"
  Log ""
  Log "Your OneLake indexers now include:"
  
  $capabilities = switch ($SkillsetType) {
    "basic" { @("Text splitting and merging") }
    "comprehensive" { @(
      "📝 Language detection",
      "🔍 OCR (text from images/scans)", 
      "👥 Entity extraction (people, places, organizations)",
      "🔑 Key phrase extraction",
      "😊 Sentiment analysis"
    )}
    "all" { @(
      "📝 Language detection",
      "🔍 OCR capabilities", 
      "👥 Entity recognition",
      "🔑 Key phrase extraction",
      "😊 Sentiment analysis",
      "🧠 And more cognitive skills"
    )}
  }
  
  $capabilities | ForEach-Object { Log "  $_" }
  
  Log ""
  Log "Next steps:"
  Log "1. Upload documents to your OneLake folders"
  Log "2. Wait for indexers to process (they run every hour)"
  Log "3. Query the enriched search indexes using the new fields"
  Log "4. Monitor indexer status in Azure portal"
}

Log "Automation completed at $(Get-Date)"
