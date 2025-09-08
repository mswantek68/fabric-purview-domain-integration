# Create and run OneLake indexer for AI Search
# This script creates the indexer that processes OneLake documents

param(
    [string]$aiSearchName = "",
    [string]$resourceGroup = "",
    [string]$subscription = "",
    [string]$indexName = "onelake-documents-index",
    [string]$dataSourceName = "onelake-reports-datasource",
    [string]$skillsetName = "onelake-textonly-skillset",
    [string]$indexerName = "onelake-reports-indexer"
)

# Resolve parameters from environment
if (-not $aiSearchName) { $aiSearchName = $env:aiSearchName }
if (-not $aiSearchName) { $aiSearchName = $env:AZURE_AI_SEARCH_NAME }
if (-not $resourceGroup) { $resourceGroup = $env:aiSearchResourceGroup }
if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP_NAME }
if (-not $subscription) { $subscription = $env:aiSearchSubscriptionId }
if (-not $subscription) { $subscription = $env:AZURE_SUBSCRIPTION_ID }

Write-Host "Creating OneLake indexer for AI Search service: $aiSearchName"
Write-Host "=============================================================="

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription) {
    Write-Error "Missing required environment variables. Please ensure AZURE_AI_SEARCH_NAME, AZURE_RESOURCE_GROUP_NAME, and AZURE_SUBSCRIPTION_ID are set."
    exit 1
}

Write-Host "Index Name: $indexName"
Write-Host "Data Source: $dataSourceName"
Write-Host "Skillset: $skillsetName"
Write-Host "Indexer Name: $indexerName"
Write-Host ""

# Get API key
$apiKey = az search admin-key show --service-name $aiSearchName --resource-group $resourceGroup --subscription $subscription --query primaryKey -o tsv

if (-not $apiKey) {
    Write-Error "Failed to retrieve AI Search admin key"
    exit 1
}

$headers = @{
    'api-key' = $apiKey
    'Content-Type' = 'application/json'
}

# Use preview API version required for OneLake
$apiVersion = '2024-05-01-preview'

# Create OneLake indexer
Write-Host "Creating OneLake indexer: $indexerName"

$indexerBody = @{
    name = $indexerName
    description = "OneLake indexer for processing documents with simplified skillset"
    dataSourceName = $dataSourceName
    targetIndexName = $indexName
    skillsetName = 'onelake-textonly-skillset'  # Match the skillset created in 01_create_onelake_skillsets.ps1
    parameters = @{
        configuration = @{
            parsingMode = "default"
            dataToExtract = "contentAndMetadata"
            indexedFileNameExtensions = ".pdf,.txt,.docx"
        }
    }
    fieldMappings = @(
        @{
            sourceFieldName = "metadata_storage_path"
            targetFieldName = "id"
            mappingFunction = @{
                name = "base64Encode"
                parameters = @{
                    useHttpServerUtilityUrlTokenEncode = $false
                }
            }
        }
    )
    outputFieldMappings = @(
        @{
            sourceFieldName = "/document/chunks/*"
            targetFieldName = "content"
        }
    )
} | ConvertTo-Json -Depth 10

# Delete existing indexer if present
try {
    $deleteUrl = "https://$aiSearchName.search.windows.net/indexers/$indexerName?api-version=$apiVersion"
    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE
    Write-Host "Deleted existing indexer"
} catch {
    Write-Host "No existing indexer to delete"
}

# Create indexer
$createUrl = "https://$aiSearchName.search.windows.net/indexers?api-version=$apiVersion"

try {
    $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $indexerBody
    Write-Host "✅ Successfully created OneLake indexer: $($response.name)"
    
    # Run the indexer immediately
    Write-Host ""
    Write-Host "Running indexer..."
    $runUrl = "https://$aiSearchName.search.windows.net/indexers/$indexerName/run?api-version=$apiVersion"
    Invoke-RestMethod -Uri $runUrl -Headers $headers -Method POST
    Write-Host "✅ Indexer execution started"
    
    # Wait a moment and check status
    Write-Host ""
    Write-Host "Waiting 30 seconds before checking status..."
    Start-Sleep -Seconds 30
    
    $statusUrl = "https://$aiSearchName.search.windows.net/indexers/$indexerName/status?api-version=$apiVersion"
    $status = Invoke-RestMethod -Uri $statusUrl -Headers $headers -Method GET
    
    Write-Host ""
    Write-Host "🎯 INDEXER EXECUTION RESULTS:"
    Write-Host "=============================="
    Write-Host "Status: $($status.lastResult.status)"
    Write-Host "Items Processed: $($status.lastResult.itemsProcessed)"
    Write-Host "Items Failed: $($status.lastResult.itemsFailed)"
    
    if ($status.lastResult.errorMessage) {
        Write-Host "Error: $($status.lastResult.errorMessage)"
    }
    
    if ($status.lastResult.warnings) {
        Write-Host "Warnings:"
        $status.lastResult.warnings | ForEach-Object {
            Write-Host "  - $($_.message)"
        }
    }
    
    if ($status.lastResult.itemsProcessed -gt 0) {
        Write-Host ""
        Write-Host "🎉 SUCCESS! Processed $($status.lastResult.itemsProcessed) documents from OneLake!"
        
        # Check the search index for documents
        $searchUrl = "https://$aiSearchName.search.windows.net/indexes/$indexName/docs?api-version=$apiVersion&search=*&`$count=true&`$top=3"
        try {
            $searchResults = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
            Write-Host "Total documents in search index: $($searchResults.'@odata.count')"
            
            if ($searchResults.value.Count -gt 0) {
                Write-Host ""
                Write-Host "Sample indexed documents:"
                $searchResults.value | ForEach-Object {
                    Write-Host "  - $($_.metadata_storage_name)"
                }
            }
        } catch {
            Write-Host "Could not retrieve search results: $($_.Exception.Message)"
        }
    } else {
        Write-Host ""
        Write-Host "⚠️  No documents were processed. This may indicate:"
        Write-Host "   1. Permission issues with AI Search accessing OneLake"
        Write-Host "   2. No documents found in the specified path"
        Write-Host "   3. Authentication problems with the managed identity"
    }
    
} catch {
    Write-Error "Failed to create OneLake indexer: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "OneLake indexer setup completed!"
