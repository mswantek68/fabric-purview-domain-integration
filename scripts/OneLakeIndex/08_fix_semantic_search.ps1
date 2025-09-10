#!/usr/bin/env pwsh

Write-Host "🔧 Adding Semantic Search Configuration to AI Search Index" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

# Get admin key
Write-Host "📋 Getting AI Search admin key..."
$adminKey = (az search admin-key show --service-name 'aisearchswan2' --resource-group 'AI_Related' --output json | ConvertFrom-Json).primaryKey

$headers = @{
    'api-key' = $adminKey
    'Content-Type' = 'application/json'
}

# Get current index definition
Write-Host "📋 Getting current index definition..."
$currentIndex = Invoke-RestMethod -Uri "https://aisearchswan2.search.windows.net/indexes/swantest-ws06-documents?api-version=2024-03-01-preview" -Headers $headers -Method Get

Write-Host "Current index: $($currentIndex.name)"
Write-Host "Current fields: $($currentIndex.fields.Count)"

# Create proper semantic configuration using actual field names
Write-Host "🔧 Creating semantic configuration..."

# Create the semantic configuration object
$semanticConfigurations = @(
    @{
        name = 'default'
        prioritizedFields = @{
            titleField = @{
                fieldName = 'title'
            }
            contentFields = @(
                @{ fieldName = 'content' }
            )
            keywordFields = @(
                @{ fieldName = 'file_name' }
            )
        }
    }
)

# Create the index update object with semantic configuration
$indexUpdate = @{
    name = $currentIndex.name
    fields = $currentIndex.fields
    semanticConfigurations = $semanticConfigurations
}

# Preserve any existing properties
if ($currentIndex.suggesters) { 
    $indexUpdate.suggesters = $currentIndex.suggesters 
    Write-Host "✅ Preserved suggesters"
}
if ($currentIndex.analyzers) { 
    $indexUpdate.analyzers = $currentIndex.analyzers 
    Write-Host "✅ Preserved analyzers"
}
if ($currentIndex.charFilters) { 
    $indexUpdate.charFilters = $currentIndex.charFilters 
    Write-Host "✅ Preserved charFilters"
}
if ($currentIndex.tokenizers) { 
    $indexUpdate.tokenizers = $currentIndex.tokenizers 
    Write-Host "✅ Preserved tokenizers"
}
if ($currentIndex.tokenFilters) { 
    $indexUpdate.tokenFilters = $currentIndex.tokenFilters 
    Write-Host "✅ Preserved tokenFilters"
}
if ($currentIndex.scoringProfiles) { 
    $indexUpdate.scoringProfiles = $currentIndex.scoringProfiles 
    Write-Host "✅ Preserved scoringProfiles"
}
if ($currentIndex.corsOptions) { 
    $indexUpdate.corsOptions = $currentIndex.corsOptions 
    Write-Host "✅ Preserved corsOptions"
}

$indexJson = $indexUpdate | ConvertTo-Json -Depth 10

Write-Host "📤 Updating index with semantic configuration..."
try {
    $response = Invoke-RestMethod -Uri "https://aisearchswan2.search.windows.net/indexes/swantest-ws06-documents?api-version=2024-03-01-preview" -Headers $headers -Method Put -Body $indexJson
    Write-Host "✅ Index updated successfully!" -ForegroundColor Green
    Write-Host "Semantic configuration name: $($response.semanticConfigurations[0].name)"
    Write-Host "Title field: $($response.semanticConfigurations[0].prioritizedFields.titleField.fieldName)"
    Write-Host "Content fields: $($response.semanticConfigurations[0].prioritizedFields.contentFields[0].fieldName)"
    Write-Host "Keyword fields: $($response.semanticConfigurations[0].prioritizedFields.keywordFields[0].fieldName)"
    
    Write-Host ""
    Write-Host "🎯 Chat Playground should now work with semantic search!" -ForegroundColor Green
    Write-Host "Try your chat again in AI Foundry."
    
} catch {
    Write-Host "❌ Error updating index: $($_.Exception.Message)" -ForegroundColor Red
    
    # Get detailed error message
    if ($_.Exception.Response) {
        try {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorContent = $reader.ReadToEnd()
            Write-Host "Error details: $errorContent" -ForegroundColor Red
        } catch {
            Write-Host "Could not read error details" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "✅ Semantic search configuration script completed!" -ForegroundColor Green
