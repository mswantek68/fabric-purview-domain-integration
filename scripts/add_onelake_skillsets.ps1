<#
.SYNOPSIS
  Add working AI skillsets to existing OneLake indexers
.DESCRIPTION
  This script creates a text-only AI skillset and attaches it to existing OneLake indexers.
  It's designed to work reliably with OneLake data sources without OCR complications.
.PARAMETER AISearchName
  The name of the Azure AI Search service
.PARAMETER IndexerPattern
  Pattern to match indexers (default: "files-documents-*")
#>

[CmdletBinding()]
param(
  [string]$AISearchName,
  [string]$IndexerPattern = "*-documents-*"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m, [string]$color = "White"){ 
  Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" -ForegroundColor $color 
}
function Success([string]$m){ Log $m "Green" }
function Warn([string]$m){ Log $m "Yellow" }

# Get configuration
if (-not $AISearchName) {
  if (Test-Path '/tmp/azd-outputs.json') {
    try {
      $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
      $AISearchName = $outputs.aiSearchName.value
    } catch {
      Warn "Could not read AISearchName from azd outputs"
    }
  }
}

if (-not $AISearchName) { 
  Warn "AISearchName not provided and not found in azd outputs - skipping skillset setup"
  exit 0
}

# Get authentication
$resourceGroup = 'AI_Related'
try {
  $adminKey = & az search admin-key show --service-name $AISearchName --resource-group $resourceGroup --query primaryKey -o tsv
  $headers = @{ 'Content-Type' = 'application/json'; 'api-key' = $adminKey }
  $endpoint = "https://$AISearchName.search.windows.net"
} catch {
  Warn "Could not get AI Search authentication - skipping skillset setup"
  exit 0
}

Log "=== Adding AI Skillsets to OneLake Indexers ===" "Cyan"
Log "AI Search: $AISearchName"

# Create text-only skillset if it doesn't exist
$skillsetName = 'onelake-textonly-skillset'
try {
  $skillsets = Invoke-RestMethod -Uri "$endpoint/skillsets?api-version=2024-05-01-preview" -Headers $headers
  $existingSkillset = $skillsets.value | Where-Object { $_.name -eq $skillsetName }
  
  if (-not $existingSkillset) {
    Log "Creating text-only skillset..."
    
    $skillset = @{
      name = $skillsetName
      description = 'Text-only skillset for OneLake documents - entities, key phrases, sentiment, language'
      skills = @(
        @{
          '@odata.type' = '#Microsoft.Skills.Text.LanguageDetectionSkill'
          name = 'language-detection'
          context = '/document'
          inputs = @( @{ name = 'text'; source = '/document/content' } )
          outputs = @( @{ name = 'languageCode'; targetName = 'language' } )
        }
        @{
          '@odata.type' = '#Microsoft.Skills.Text.V3.EntityRecognitionSkill'
          name = 'entity-recognition'
          context = '/document'
          categories = @('Person', 'Location', 'Organization', 'DateTime')
          defaultLanguageCode = 'en'
          minimumPrecision = 0.5
          inputs = @(
            @{ name = 'text'; source = '/document/content' }
            @{ name = 'languageCode'; source = '/document/language' }
          )
          outputs = @(
            @{ name = 'persons'; targetName = 'people' }
            @{ name = 'locations'; targetName = 'locations' }
            @{ name = 'organizations'; targetName = 'organizations' }
          )
        }
        @{
          '@odata.type' = '#Microsoft.Skills.Text.KeyPhraseExtractionSkill'
          name = 'key-phrases'
          context = '/document'
          defaultLanguageCode = 'en'
          maxKeyPhraseCount = 50
          inputs = @(
            @{ name = 'text'; source = '/document/content' }
            @{ name = 'languageCode'; source = '/document/language' }
          )
          outputs = @( @{ name = 'keyPhrases'; targetName = 'keyphrases' } )
        }
        @{
          '@odata.type' = '#Microsoft.Skills.Text.V3.SentimentSkill'
          name = 'sentiment-analysis'
          context = '/document'
          defaultLanguageCode = 'en'
          inputs = @(
            @{ name = 'text'; source = '/document/content' }
            @{ name = 'languageCode'; source = '/document/language' }
          )
          outputs = @( @{ name = 'sentiment'; targetName = 'sentiment' } )
        }
      )
    } | ConvertTo-Json -Depth 20
    
    Invoke-RestMethod -Uri "$endpoint/skillsets?api-version=2024-05-01-preview" -Method Post -Headers $headers -Body $skillset | Out-Null
    Success "Skillset '$skillsetName' created"
  } else {
    Success "Skillset '$skillsetName' already exists"
  }
} catch {
  Warn "Failed to create skillset: $($_.Exception.Message)"
  exit 1
}

# Get matching indexers
try {
  $indexers = Invoke-RestMethod -Uri "$endpoint/indexers?api-version=2024-05-01-preview" -Headers $headers
  $matchingIndexers = $indexers.value | Where-Object { $_.name -like $IndexerPattern }
  
  if ($matchingIndexers.Count -eq 0) {
    Log "No indexers found matching pattern: $IndexerPattern"
    exit 0
  }
  
  Log "Found $($matchingIndexers.Count) matching indexers"
} catch {
  Warn "Failed to get indexers: $($_.Exception.Message)"
  exit 1
}

# Update each indexer to use the skillset
$successCount = 0
foreach ($indexer in $matchingIndexers) {
  try {
    # Skip if already has skillset
    if ($indexer.skillsetName) {
      Success "Indexer '$($indexer.name)' already has skillset: $($indexer.skillsetName)"
      $successCount++
      continue
    }
    
    Log "Updating indexer: $($indexer.name)"
    
    # Update indexer with skillset
    $updatedIndexer = @{
      name = $indexer.name
      dataSourceName = $indexer.dataSourceName
      targetIndexName = $indexer.targetIndexName
      skillsetName = $skillsetName
      schedule = $indexer.schedule
      parameters = $indexer.parameters
      fieldMappings = @()
      outputFieldMappings = @(
        @{ sourceFieldName = '/document/language'; targetFieldName = 'language' }
        @{ sourceFieldName = '/document/people'; targetFieldName = 'people' }
        @{ sourceFieldName = '/document/locations'; targetFieldName = 'locations' }
        @{ sourceFieldName = '/document/organizations'; targetFieldName = 'organizations' }
        @{ sourceFieldName = '/document/keyphrases'; targetFieldName = 'keyphrases' }
        @{ sourceFieldName = '/document/sentiment'; targetFieldName = 'sentiment' }
      )
    } | ConvertTo-Json -Depth 20
    
    Invoke-RestMethod -Uri "$endpoint/indexers/$($indexer.name)?api-version=2024-05-01-preview" -Method Put -Headers $headers -Body $updatedIndexer | Out-Null
    Success "✅ Updated indexer: $($indexer.name)"
    $successCount++
    
  } catch {
    Warn "Failed to update indexer '$($indexer.name)': $($_.Exception.Message)"
  }
}

Log ""
Log "=== Skillset Setup Summary ===" "Green"
Log "Successfully updated: $successCount of $($matchingIndexers.Count) indexers"

if ($successCount -gt 0) {
  Log ""
  Log "🎉 AI skillsets are now active! Your OneLake indexers will extract:"
  Log "  📝 Language detection"
  Log "  👥 Entities (people, places, organizations)"
  Log "  🔑 Key phrases"
  Log "  😊 Sentiment analysis"
  Log ""
  Log "Documents will be processed with AI skills on the next indexer run"
}

Log "Skillset setup completed at $(Get-Date)"
