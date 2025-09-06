<#
.SYNOPSIS
  Test OneLake indexers with AI skillsets
.DESCRIPTION
  Quick validation that OneLake indexers are working and have AI skillsets attached
#>

[CmdletBinding()]
param(
  [string]$AISearchName,
  [switch]$RunIndexers
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
  Warn "AISearchName not provided and not found in azd outputs"
  exit 1
}

# Get authentication
$resourceGroup = 'AI_Related'
try {
  $adminKey = & az search admin-key show --service-name $AISearchName --resource-group $resourceGroup --query primaryKey -o tsv
  $headers = @{ 'Content-Type' = 'application/json'; 'api-key' = $adminKey }
  $endpoint = "https://$AISearchName.search.windows.net"
} catch {
  Warn "Could not get AI Search authentication"
  exit 1
}

Log "=== OneLake Indexer Test ===" "Cyan"
Log "AI Search: $AISearchName"
Log ""

# Check skillsets
try {
  $skillsets = Invoke-RestMethod -Uri "$endpoint/skillsets?api-version=2024-05-01-preview" -Headers $headers
  $skillsetCount = $skillsets.value.Count
  Log "📊 Skillsets found: $skillsetCount"
  
  foreach ($skillset in $skillsets.value) {
    Log "  - $($skillset.name) ($($skillset.skills.Count) skills)"
  }
} catch {
  Warn "Failed to get skillsets: $($_.Exception.Message)"
}

Log ""

# Check OneLake indexers
try {
  $indexers = Invoke-RestMethod -Uri "$endpoint/indexers?api-version=2024-05-01-preview" -Headers $headers
  $onelakeIndexers = $indexers.value | Where-Object { $_.name -like "files-documents-*" }
  
  Log "🔍 OneLake indexers found: $($onelakeIndexers.Count)"
  
  foreach ($indexer in $onelakeIndexers) {
    $skillsetStatus = if ($indexer.skillsetName) { "✅ $($indexer.skillsetName)" } else { "❌ No skillset" }
    $outputMappings = if ($indexer.outputFieldMappings -and $indexer.outputFieldMappings.Count -gt 0) { "✅ $($indexer.outputFieldMappings.Count) AI fields" } else { "❌ No AI fields" }
    
    Log "  📋 $($indexer.name)"
    Log "     Skillset: $skillsetStatus"
    Log "     AI Fields: $outputMappings"
    
    # Get indexer status
    try {
      $status = Invoke-RestMethod -Uri "$endpoint/indexers/$($indexer.name)/status?api-version=2024-05-01-preview" -Headers $headers
      $lastRun = if ($status.lastResult) { $status.lastResult.status } else { "Never run" }
      Log "     Last run: $lastRun"
      
      if ($RunIndexers -and $lastRun -ne "inProgress") {
        Log "     🚀 Starting indexer run..."
        Invoke-RestMethod -Uri "$endpoint/indexers/$($indexer.name)/run?api-version=2024-05-01-preview" -Method Post -Headers $headers | Out-Null
      }
    } catch {
      Log "     Status: Error getting status"
    }
  }
} catch {
  Warn "Failed to get indexers: $($_.Exception.Message)"
}

Log ""

# Check indexes for AI fields
try {
  $indexes = Invoke-RestMethod -Uri "$endpoint/indexes?api-version=2024-05-01-preview" -Headers $headers
  $onelakeIndexes = $indexes.value | Where-Object { $_.name -like "files-documents-*" }
  
  Log "📚 OneLake indexes found: $($onelakeIndexes.Count)"
  
  foreach ($index in $onelakeIndexes) {
    $aiFields = $index.fields | Where-Object { $_.name -in @('language', 'people', 'locations', 'organizations', 'keyphrases', 'sentiment') }
    $aiFieldNames = if ($aiFields) { ($aiFields | ForEach-Object { $_.name }) -join ', ' } else { "" }
    
    Log "  📖 $($index.name) ($($index.fields.Count) total fields)"
    if ($aiFields -and $aiFields.Count -gt 0) {
      Log "     ✅ AI fields: $aiFieldNames"
    } else {
      Log "     ❌ No AI fields found"
    }
  }
} catch {
  Warn "Failed to get indexes: $($_.Exception.Message)"
}

Log ""
Log "=== Test Summary ===" "Green"
Log "OneLake indexer test completed at $(Get-Date)"

if ($RunIndexers) {
  Log ""
  Log "🔄 Indexers have been started. Check back in a few minutes to see processed documents."
  Log "   Use: Get-Content logs/* | Select-String -Pattern 'document' to check processing"
}
