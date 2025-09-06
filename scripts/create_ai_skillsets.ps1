<#
.SYNOPSIS
  Create AI Search skillsets for enhanced document processing
.DESCRIPTION
  This script creates modular skillsets that can be applied to OneLake indexers
  for enhanced document processing including OCR, entity extraction, key phrase
  extraction, and sentiment analysis. Each skillset is atomic and reusable.
.PARAMETER SkillsetType
  Type of skillset to create: 'basic', 'ocr', 'entities', 'keyphrases', 'sentiment', 'all'
.PARAMETER SkillsetName
  Custom name for the skillset (will be generated if not provided)
.PARAMETER AISearchName
  The name of the Azure AI Search service
.PARAMETER CognitiveServicesKey
  Optional Cognitive Services key for enhanced processing
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("basic", "ocr", "entities", "keyphrases", "sentiment", "language", "comprehensive", "all")]
  [string[]]$SkillsetType,
  
  [string]$SkillsetName,
  [string]$AISearchName,
  [string]$CognitiveServicesKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m, [string]$color = "White"){ 
  Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" -ForegroundColor $color 
}
function Success([string]$m){ Log $m "Green" }
function Warn([string]$m){ Log $m "Yellow" }
function Fail([string]$m){ Log $m "Red"; exit 1 }

# Get configuration
function Get-SkillsetConfiguration {
  $config = @{}
  
  # Resolve AISearchName
  if (-not $AISearchName) {
    if (Test-Path '/tmp/azd-outputs.json') {
      try {
        $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
        $config.AISearchName = $outputs.aiSearchName.value
        Log "Found AISearchName from azd outputs: $($config.AISearchName)"
      } catch {
        Log "Could not read AISearchName from azd outputs"
      }
    }
  } else {
    $config.AISearchName = $AISearchName
  }
  
  if (-not $config.AISearchName) { Fail "AISearchName not provided and not found in azd outputs" }
  
  # Get AI Search resource configuration
  $config.aiSearchResourceGroup = 'AI_Related'
  $config.aiSearchSubscriptionId = (& az account show --query id -o tsv)
  
  return $config
}

# Get AI Search authentication
function Get-AISearchAuth($config) {
  Log "Getting AI Search authentication..."
  try {
    $keyInfo = & az search admin-key show --service-name $config.AISearchName --resource-group $config.aiSearchResourceGroup --subscription $config.aiSearchSubscriptionId --query primaryKey -o tsv 2>$null
    
    if ($keyInfo) {
      $auth = @{
        apiKey = $keyInfo
        headers = @{ 
          'Content-Type' = 'application/json'
          'api-key' = $keyInfo
        }
        endpoint = "https://$($config.AISearchName).search.windows.net"
      }
      Success "Successfully retrieved AI Search API key"
      return $auth
    } else {
      Fail "Failed to retrieve AI Search API key"
    }
  } catch {
    Fail "Exception getting API key: $($_.Exception.Message)"
  }
}

# Skillset definitions
function Get-BasicSkillset($name) {
  return @{
    name = $name
    description = "Basic text processing skillset with text splitting and merging"
    skills = @(
      @{
        "@odata.type" = "#Microsoft.Skills.Text.SplitSkill"
        name = "split-text"
        description = "Split text into chunks for processing"
        context = "/document"
        defaultLanguageCode = "en"
        textSplitMode = "pages"
        maximumPageLength = 4000
        inputs = @(
          @{ name = "text"; source = "/document/content" }
        )
        outputs = @(
          @{ name = "textItems"; targetName = "pages" }
        )
      }
      @{
        "@odata.type" = "#Microsoft.Skills.Text.MergeSkill"
        name = "merge-text"
        description = "Merge processed text chunks"
        context = "/document"
        insertPreTag = " "
        insertPostTag = " "
        inputs = @(
          @{ name = "text"; source = "/document/content" }
          @{ name = "itemsToInsert"; source = "/document/pages/*" }
        )
        outputs = @(
          @{ name = "mergedText"; targetName = "merged_content" }
        )
      }
    )
  }
}

function Get-OCRSkillset($name) {
  return @{
    name = $name
    description = "OCR skillset for extracting text from images and scanned documents"
    skills = @(
      @{
        "@odata.type" = "#Microsoft.Skills.Vision.OcrSkill"
        name = "ocr-text"
        description = "Extract text from images using OCR"
        context = "/document/normalized_images/*"
        defaultLanguageCode = "en"
        detectOrientation = $true
        inputs = @(
          @{ name = "image"; source = "/document/normalized_images/*" }
        )
        outputs = @(
          @{ name = "text"; targetName = "ocr_text" }
          @{ name = "layoutText"; targetName = "ocr_layout" }
        )
      }
      @{
        "@odata.type" = "#Microsoft.Skills.Text.MergeSkill"
        name = "merge-ocr"
        description = "Merge OCR text with document content"
        context = "/document"
        insertPreTag = " "
        insertPostTag = " "
        inputs = @(
          @{ name = "text"; source = "/document/content" }
          @{ name = "itemsToInsert"; source = "/document/normalized_images/*/ocr_text" }
        )
        outputs = @(
          @{ name = "mergedText"; targetName = "merged_content" }
        )
      }
    )
  }
}

function Get-EntitiesSkillset($name) {
  return @{
    name = $name
    description = "Entity recognition skillset for extracting people, places, organizations"
    skills = @(
      @{
        "@odata.type" = "#Microsoft.Skills.Text.V3.EntityRecognitionSkill"
        name = "entity-recognition"
        description = "Extract named entities from text"
        context = "/document"
        categories = @("Person", "Location", "Organization", "DateTime", "URL", "Email")
        defaultLanguageCode = "en"
        minimumPrecision = 0.5
        inputs = @(
          @{ name = "text"; source = "/document/content" }
          @{ name = "languageCode"; source = "/document/language" }
        )
        outputs = @(
          @{ name = "persons"; targetName = "people" }
          @{ name = "locations"; targetName = "locations" }
          @{ name = "organizations"; targetName = "organizations" }
          @{ name = "entities"; targetName = "entities" }
        )
      }
    )
  }
}

function Get-KeyPhrasesSkillset($name) {
  return @{
    name = $name
    description = "Key phrase extraction skillset"
    skills = @(
      @{
        "@odata.type" = "#Microsoft.Skills.Text.KeyPhraseExtractionSkill"
        name = "key-phrases"
        description = "Extract key phrases from text"
        context = "/document"
        defaultLanguageCode = "en"
        maxKeyPhraseCount = 50
        inputs = @(
          @{ name = "text"; source = "/document/content" }
          @{ name = "languageCode"; source = "/document/language" }
        )
        outputs = @(
          @{ name = "keyPhrases"; targetName = "keyphrases" }
        )
      }
    )
  }
}

function Get-SentimentSkillset($name) {
  return @{
    name = $name
    description = "Sentiment analysis skillset"
    skills = @(
      @{
        "@odata.type" = "#Microsoft.Skills.Text.V3.SentimentSkill"
        name = "sentiment-analysis"
        description = "Analyze sentiment of text"
        context = "/document"
        defaultLanguageCode = "en"
        inputs = @(
          @{ name = "text"; source = "/document/content" }
          @{ name = "languageCode"; source = "/document/language" }
        )
        outputs = @(
          @{ name = "sentiment"; targetName = "sentiment" }
          @{ name = "confidenceScores"; targetName = "sentiment_scores" }
        )
      }
    )
  }
}

function Get-LanguageSkillset($name) {
  return @{
    name = $name
    description = "Language detection skillset"
    skills = @(
      @{
        "@odata.type" = "#Microsoft.Skills.Text.LanguageDetectionSkill"
        name = "language-detection"
        description = "Detect language of text"
        context = "/document"
        inputs = @(
          @{ name = "text"; source = "/document/content" }
        )
        outputs = @(
          @{ name = "languageCode"; targetName = "language" }
          @{ name = "languageName"; targetName = "language_name" }
          @{ name = "score"; targetName = "language_confidence" }
        )
      }
    )
  }
}

function Get-ComprehensiveSkillset($name) {
  return @{
    name = $name
    description = "Comprehensive skillset with language detection, OCR, entities, key phrases, and sentiment"
    skills = @(
      @{
        "@odata.type" = "#Microsoft.Skills.Text.LanguageDetectionSkill"
        name = "language-detection"
        description = "Detect language of text"
        context = "/document"
        inputs = @(
          @{ name = "text"; source = "/document/content" }
        )
        outputs = @(
          @{ name = "languageCode"; targetName = "language" }
        )
      }
      @{
        "@odata.type" = "#Microsoft.Skills.Vision.OcrSkill"
        name = "ocr-text"
        description = "Extract text from images using OCR"
        context = "/document/normalized_images/*"
        defaultLanguageCode = "en"
        detectOrientation = $true
        inputs = @(
          @{ name = "image"; source = "/document/normalized_images/*" }
        )
        outputs = @(
          @{ name = "text"; targetName = "ocr_text" }
        )
      }
      @{
        "@odata.type" = "#Microsoft.Skills.Text.MergeSkill"
        name = "merge-content"
        description = "Merge OCR text with document content"
        context = "/document"
        insertPreTag = " "
        insertPostTag = " "
        inputs = @(
          @{ name = "text"; source = "/document/content" }
          @{ name = "itemsToInsert"; source = "/document/normalized_images/*/ocr_text" }
        )
        outputs = @(
          @{ name = "mergedText"; targetName = "merged_content" }
        )
      }
      @{
        "@odata.type" = "#Microsoft.Skills.Text.V3.EntityRecognitionSkill"
        name = "entity-recognition"
        description = "Extract named entities from text"
        context = "/document"
        categories = @("Person", "Location", "Organization", "DateTime")
        defaultLanguageCode = "en"
        minimumPrecision = 0.5
        inputs = @(
          @{ name = "text"; source = "/document/merged_content" }
          @{ name = "languageCode"; source = "/document/language" }
        )
        outputs = @(
          @{ name = "persons"; targetName = "people" }
          @{ name = "locations"; targetName = "locations" }
          @{ name = "organizations"; targetName = "organizations" }
        )
      }
      @{
        "@odata.type" = "#Microsoft.Skills.Text.KeyPhraseExtractionSkill"
        name = "key-phrases"
        description = "Extract key phrases from text"
        context = "/document"
        defaultLanguageCode = "en"
        maxKeyPhraseCount = 50
        inputs = @(
          @{ name = "text"; source = "/document/merged_content" }
          @{ name = "languageCode"; source = "/document/language" }
        )
        outputs = @(
          @{ name = "keyPhrases"; targetName = "keyphrases" }
        )
      }
      @{
        "@odata.type" = "#Microsoft.Skills.Text.V3.SentimentSkill"
        name = "sentiment-analysis"
        description = "Analyze sentiment of text"
        context = "/document"
        defaultLanguageCode = "en"
        inputs = @(
          @{ name = "text"; source = "/document/merged_content" }
          @{ name = "languageCode"; source = "/document/language" }
        )
        outputs = @(
          @{ name = "sentiment"; targetName = "sentiment" }
          @{ name = "confidenceScores"; targetName = "sentiment_scores" }
        )
      }
    )
  }
}

# Create skillset
function New-Skillset($auth, $skillsetDefinition) {
  $skillsetJson = $skillsetDefinition | ConvertTo-Json -Depth 20
  
  Log "Creating skillset '$($skillsetDefinition.name)'..."
  Log "Description: $($skillsetDefinition.description)"
  Log "Skills count: $($skillsetDefinition.skills.Count)"
  
  try {
    Invoke-RestMethod -Uri "$($auth.endpoint)/skillsets?api-version=2024-05-01-preview" `
      -Method Post `
      -Headers $auth.headers `
      -Body $skillsetJson | Out-Null
    
    Success "Skillset '$($skillsetDefinition.name)' created successfully"
    return $true
  } catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
      Log "Skillset '$($skillsetDefinition.name)' already exists, updating..."
      try {
        Invoke-RestMethod -Uri "$($auth.endpoint)/skillsets/$($skillsetDefinition.name)?api-version=2024-05-01-preview" `
          -Method Put `
          -Headers $auth.headers `
          -Body $skillsetJson | Out-Null
        Success "Skillset '$($skillsetDefinition.name)' updated successfully"
        return $true
      } catch {
        Warn "Failed to update skillset '$($skillsetDefinition.name)': $($_.Exception.Message)"
        return $false
      }
    } else {
      Warn "Failed to create skillset '$($skillsetDefinition.name)': $($_.Exception.Message)"
      try {
        $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
        Warn "Details: $($errorDetails.error.message)"
      } catch {
        Warn "Could not get error details"
      }
      return $false
    }
  }
}

# Main execution
Log "=== AI Search Skillsets Creation ===" "Cyan"

# Get configuration and authentication
$config = Get-SkillsetConfiguration
$auth = Get-AISearchAuth $config

Log "Configuration:"
Log "- AI Search: $($config.AISearchName)"
Log "- Skillset types: $($SkillsetType -join ', ')"

# Expand "all" to include all skillset types
if ($SkillsetType -contains "all") {
  $SkillsetType = @("basic", "ocr", "entities", "keyphrases", "sentiment", "language", "comprehensive")
}

$results = @()
foreach ($type in $SkillsetType) {
  Log "=== Creating $type skillset ===" "Cyan"
  
  # Generate skillset name if not provided
  $name = if ($SkillsetName) { "$SkillsetName-$type" } else { "onelake-$type-skillset" }
  
  # Get skillset definition based on type
  $skillsetDef = switch ($type) {
    "basic" { Get-BasicSkillset $name }
    "ocr" { Get-OCRSkillset $name }
    "entities" { Get-EntitiesSkillset $name }
    "keyphrases" { Get-KeyPhrasesSkillset $name }
    "sentiment" { Get-SentimentSkillset $name }
    "language" { Get-LanguageSkillset $name }
    "comprehensive" { Get-ComprehensiveSkillset $name }
    default { 
      Warn "Unknown skillset type: $type"
      continue
    }
  }
  
  # Create the skillset
  $success = New-Skillset $auth $skillsetDef
  
  $results += @{
    Type = $type
    Name = $name
    Success = $success
  }
}

# Create comprehensive skillset if requested specifically (not just as part of "all")
if ($SkillsetType -contains "comprehensive" -and $SkillsetType -notcontains "all") {
  Log "=== Creating comprehensive skillset ===" "Cyan"
  $comprehensiveName = if ($SkillsetName) { "$SkillsetName-comprehensive" } else { "onelake-comprehensive-skillset" }
  $comprehensiveSkillset = Get-ComprehensiveSkillset $comprehensiveName
  $success = New-Skillset $auth $comprehensiveSkillset
  
  $results += @{
    Type = "comprehensive"
    Name = $comprehensiveName
    Success = $success
  }
}

# Summary
Log "=== Skillset Creation Summary ===" "Cyan"
$successCount = ($results | Where-Object { $_.Success }).Count
$totalCount = $results.Count

foreach ($result in $results) {
  $status = if ($result.Success) { "✅" } else { "❌" }
  Log "$status $($result.Type): $($result.Name)"
}

if ($successCount -eq $totalCount) {
  Success "🎉 All skillsets created successfully!"
} else {
  Warn "⚠️  $successCount of $totalCount skillsets created successfully"
}

Log "Skillset creation completed at $(Get-Date)"
