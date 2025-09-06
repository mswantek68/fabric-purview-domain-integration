<#
.SYNOPSIS
  Attach AI skillsets to existing OneLake indexers
.DESCRIPTION
  This script updates existing OneLake indexers to use AI skillsets for enhanced
  document processing. It can attach skillsets to specific indexers or all indexers
  matching a pattern. The script is atomic and modular - it only updates what's needed.
.PARAMETER IndexerName
  Specific indexer name to update (supports wildcards like "files-documents-*")
.PARAMETER SkillsetName
  Name of the skillset to attach
.PARAMETER SkillsetType
  Type of skillset to attach (will find matching skillset automatically)
.PARAMETER AISearchName
  The name of the Azure AI Search service
.PARAMETER UpdateIndex
  Whether to also update the index schema to include skillset outputs
.PARAMETER TestMode
  Run in test mode (show what would be changed without making changes)
#>

[CmdletBinding()]
param(
  [string]$IndexerName = "files-documents-*",
  [string]$SkillsetName,
  [ValidateSet("basic", "ocr", "entities", "keyphrases", "sentiment", "language", "comprehensive")]
  [string]$SkillsetType = "comprehensive",
  [string]$AISearchName,
  [switch]$UpdateIndex,
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

# Get configuration and authentication (reuse from skillset script)
function Get-Configuration {
  $config = @{}
  
  if (-not $AISearchName) {
    if (Test-Path '/tmp/azd-outputs.json') {
      try {
        $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
        $config.AISearchName = $outputs.aiSearchName.value
      } catch {
        Log "Could not read AISearchName from azd outputs"
      }
    }
  } else {
    $config.AISearchName = $AISearchName
  }
  
  if (-not $config.AISearchName) { Fail "AISearchName not provided and not found in azd outputs" }
  
  $config.aiSearchResourceGroup = 'AI_Related'
  $config.aiSearchSubscriptionId = (& az account show --query id -o tsv)
  
  return $config
}

function Get-AISearchAuth($config) {
  try {
    $keyInfo = & az search admin-key show --service-name $config.AISearchName --resource-group $config.aiSearchResourceGroup --query primaryKey -o tsv
    
    return @{
      headers = @{ 'Content-Type' = 'application/json'; 'api-key' = $keyInfo }
      endpoint = "https://$($config.AISearchName).search.windows.net"
    }
  } catch {
    Fail "Failed to get AI Search authentication: $($_.Exception.Message)"
  }
}

# Get matching indexers
function Get-MatchingIndexers($auth, $pattern) {
  try {
    $indexers = Invoke-RestMethod -Uri "$($auth.endpoint)/indexers?api-version=2024-05-01-preview" -Headers $auth.headers
    
    if ($pattern -eq "*") {
      return $indexers.value
    }
    
    # Convert PowerShell wildcard to regex
    $regexPattern = $pattern -replace '\*', '.*' -replace '\?', '.'
    return $indexers.value | Where-Object { $_.name -match $regexPattern }
  } catch {
    Fail "Failed to get indexers: $($_.Exception.Message)"
  }
}

# Get available skillsets
function Get-AvailableSkillsets($auth) {
  try {
    $skillsets = Invoke-RestMethod -Uri "$($auth.endpoint)/skillsets?api-version=2024-05-01-preview" -Headers $auth.headers
    return $skillsets.value
  } catch {
    Fail "Failed to get skillsets: $($_.Exception.Message)"
  }
}

# Find skillset by type or name
function Find-Skillset($skillsets, $skillsetName, $skillsetType) {
  if ($skillsetName) {
    return $skillsets | Where-Object { $_.name -eq $skillsetName } | Select-Object -First 1
  }
  
  # Find by type (look for naming pattern)
  $pattern = ".*$skillsetType.*"
  return $skillsets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
}

# Get enhanced index fields for skillset outputs
function Get-EnhancedIndexFields($skillsetType) {
  $baseFields = @(
    @{ name = "content"; type = "Edm.String"; searchable = $true; filterable = $false; facetable = $false }
    @{ name = "metadata_storage_path"; type = "Edm.String"; key = $true; searchable = $false }
    @{ name = "metadata_storage_name"; type = "Edm.String"; searchable = $true; filterable = $true }
    @{ name = "metadata_storage_size"; type = "Edm.Int64"; filterable = $true; facetable = $true }
    @{ name = "metadata_storage_last_modified"; type = "Edm.DateTimeOffset"; filterable = $true; sortable = $true }
  )
  
  $enhancedFields = switch ($skillsetType) {
    "language" {
      @(
        @{ name = "language"; type = "Edm.String"; filterable = $true; facetable = $true; searchable = $false }
        @{ name = "language_name"; type = "Edm.String"; filterable = $true; facetable = $true }
      )
    }
    "entities" {
      @(
        @{ name = "people"; type = "Collection(Edm.String)"; searchable = $true; filterable = $true; facetable = $true }
        @{ name = "locations"; type = "Collection(Edm.String)"; searchable = $true; filterable = $true; facetable = $true }
        @{ name = "organizations"; type = "Collection(Edm.String)"; searchable = $true; filterable = $true; facetable = $true }
      )
    }
    "keyphrases" {
      @(
        @{ name = "keyphrases"; type = "Collection(Edm.String)"; searchable = $true; filterable = $true; facetable = $true }
      )
    }
    "sentiment" {
      @(
        @{ name = "sentiment"; type = "Edm.String"; filterable = $true; facetable = $true; searchable = $false }
        @{ name = "sentiment_scores"; type = "Edm.ComplexType"; filterable = $false; facetable = $false; searchable = $false }
      )
    }
    "ocr" {
      @(
        @{ name = "merged_content"; type = "Edm.String"; searchable = $true; filterable = $false }
      )
    }
    "comprehensive" {
      @(
        @{ name = "language"; type = "Edm.String"; filterable = $true; facetable = $true }
        @{ name = "merged_content"; type = "Edm.String"; searchable = $true; filterable = $false }
        @{ name = "people"; type = "Collection(Edm.String)"; searchable = $true; filterable = $true; facetable = $true }
        @{ name = "locations"; type = "Collection(Edm.String)"; searchable = $true; filterable = $true; facetable = $true }
        @{ name = "organizations"; type = "Collection(Edm.String)"; searchable = $true; filterable = $true; facetable = $true }
        @{ name = "keyphrases"; type = "Collection(Edm.String)"; searchable = $true; filterable = $true; facetable = $true }
        @{ name = "sentiment"; type = "Edm.String"; filterable = $true; facetable = $true }
      )
    }
    default { @() }
  }
  
  return $baseFields + $enhancedFields
}

# Update index schema
function Update-IndexSchema($auth, $indexName, $skillsetType) {
  if (-not $UpdateIndex) {
    Log "Skipping index update (use -UpdateIndex to enable)"
    return $true
  }
  
  Log "Updating index schema for '$indexName' to support $skillsetType outputs..."
  
  try {
    # Get current index
    $currentIndex = Invoke-RestMethod -Uri "$($auth.endpoint)/indexes/$indexName`?api-version=2024-05-01-preview" -Headers $auth.headers
    
    # Get enhanced fields
    $enhancedFields = Get-EnhancedIndexFields $skillsetType
    
    # Merge with existing fields (avoid duplicates)
    $existingFieldNames = $currentIndex.fields | ForEach-Object { $_.name }
    $newFields = $enhancedFields | Where-Object { $_.name -notin $existingFieldNames }
    
    if ($newFields.Count -eq 0) {
      Success "Index '$indexName' already has all required fields"
      return $true
    }
    
    Log "Adding $($newFields.Count) new fields to index '$indexName'"
    
    if ($TestMode) {
      Log "TEST MODE: Would add fields: $($newFields | ForEach-Object { $_.name } | Join-String ', ')" "Yellow"
      return $true
    }
    
    # Update index with new fields
    $updatedIndex = @{
      name = $currentIndex.name
      fields = $currentIndex.fields + $newFields
    }
    
    $indexJson = $updatedIndex | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "$($auth.endpoint)/indexes/$indexName`?api-version=2024-05-01-preview" `
      -Method Put -Headers $auth.headers -Body $indexJson | Out-Null
    
    Success "Index '$indexName' updated with enhanced fields"
    return $true
  } catch {
    Warn "Failed to update index '$indexName': $($_.Exception.Message)"
    return $false
  }
}

# Update indexer with skillset
function Update-IndexerWithSkillset($auth, $indexer, $skillset) {
  Log "Updating indexer '$($indexer.name)' with skillset '$($skillset.name)'..."
  
  # Create updated indexer definition
  $updatedIndexer = @{
    name = $indexer.name
    dataSourceName = $indexer.dataSourceName
    targetIndexName = $indexer.targetIndexName
    skillsetName = $skillset.name
    schedule = $indexer.schedule
    parameters = $indexer.parameters
    fieldMappings = $indexer.fieldMappings
    outputFieldMappings = @(
      # Map skillset outputs to index fields based on skillset type
      @{ sourceFieldName = "/document/language"; targetFieldName = "language" }
      @{ sourceFieldName = "/document/merged_content"; targetFieldName = "merged_content" }
      @{ sourceFieldName = "/document/people"; targetFieldName = "people" }
      @{ sourceFieldName = "/document/locations"; targetFieldName = "locations" }
      @{ sourceFieldName = "/document/organizations"; targetFieldName = "organizations" }
      @{ sourceFieldName = "/document/keyphrases"; targetFieldName = "keyphrases" }
      @{ sourceFieldName = "/document/sentiment"; targetFieldName = "sentiment" }
    )
  }
  
  # Filter output mappings based on what fields exist in the target index
  try {
    $targetIndex = Invoke-RestMethod -Uri "$($auth.endpoint)/indexes/$($indexer.targetIndexName)?api-version=2024-05-01-preview" -Headers $auth.headers
    $indexFieldNames = $targetIndex.fields | ForEach-Object { $_.name }
    
    $updatedIndexer.outputFieldMappings = $updatedIndexer.outputFieldMappings | Where-Object { 
      $_.targetFieldName -in $indexFieldNames 
    }
    
    Log "Configured $($updatedIndexer.outputFieldMappings.Count) output field mappings"
  } catch {
    Warn "Could not validate target index fields, using all mappings"
  }
  
  if ($TestMode) {
    Log "TEST MODE: Would update indexer '$($indexer.name)' with skillset '$($skillset.name)'" "Yellow"
    return $true
  }
  
  try {
    $indexerJson = $updatedIndexer | ConvertTo-Json -Depth 20
    Invoke-RestMethod -Uri "$($auth.endpoint)/indexers/$($indexer.name)?api-version=2024-05-01-preview" `
      -Method Put -Headers $auth.headers -Body $indexerJson | Out-Null
    
    Success "Indexer '$($indexer.name)' updated with skillset '$($skillset.name)'"
    return $true
  } catch {
    Warn "Failed to update indexer '$($indexer.name)': $($_.Exception.Message)"
    return $false
  }
}

# Main execution
$testModeText = if ($TestMode) { " (TEST MODE)" } else { "" }
Log "=== Attach Skillsets to OneLake Indexers$testModeText ===" "Cyan"

# Get configuration and authentication
$config = Get-Configuration
$auth = Get-AISearchAuth $config

# Get matching indexers
$indexers = Get-MatchingIndexers $auth $IndexerName
if ($indexers.Count -eq 0) {
  Fail "No indexers found matching pattern: $IndexerName"
}

Log "Found $($indexers.Count) matching indexers:"
$indexers | ForEach-Object { Log "  - $($_.name)" }

# Get available skillsets
$skillsets = Get-AvailableSkillsets $auth
Log "Available skillsets: $($skillsets.Count)"
$skillsets | ForEach-Object { Log "  - $($_.name)" }

# Find target skillset
$targetSkillset = Find-Skillset $skillsets $SkillsetName $SkillsetType
if (-not $targetSkillset) {
  Fail "Could not find skillset. Name: '$SkillsetName', Type: '$SkillsetType'"
}

Success "Using skillset: $($targetSkillset.name)"

# Update each indexer
$results = @()
foreach ($indexer in $indexers) {
  Log "=== Processing indexer: $($indexer.name) ===" "Cyan"
  
  # Update index schema if requested
  $indexUpdated = Update-IndexSchema $auth $indexer.targetIndexName $SkillsetType
  
  # Update indexer with skillset
  $indexerUpdated = Update-IndexerWithSkillset $auth $indexer $targetSkillset
  
  $results += @{
    IndexerName = $indexer.name
    IndexName = $indexer.targetIndexName
    SkillsetName = $targetSkillset.name
    IndexUpdated = $indexUpdated
    IndexerUpdated = $indexerUpdated
    Success = $indexUpdated -and $indexerUpdated
  }
}

# Summary
Log "=== Skillset Attachment Summary$testModeText ===" "Cyan"
$successCount = ($results | Where-Object { $_.Success }).Count
$totalCount = $results.Count

foreach ($result in $results) {
  $status = if ($result.Success) { "✅" } else { "❌" }
  Log "$status $($result.IndexerName) -> $($result.SkillsetName)"
  if ($UpdateIndex) {
    $indexStatus = if ($result.IndexUpdated) { "✅" } else { "❌" }
    Log "    Index: $indexStatus $($result.IndexName)"
  }
}

if ($successCount -eq $totalCount) {
  Success "🎉 All indexers updated successfully!"
  if (-not $TestMode) {
    Log ""
    Log "Next steps:"
    Log "1. Run the indexers to process documents with AI skills"
    Log "2. Test search queries using the new enriched fields"
    Log "3. Monitor indexer execution for any errors"
  }
} else {
  Warn "⚠️  $successCount of $totalCount indexers updated successfully"
}

Log "Skillset attachment completed at $(Get-Date)"
