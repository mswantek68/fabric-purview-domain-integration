# Create OneLake indexer using the CORRECT preview API version
# Following Microsoft documentation exactly

param(
    [string]$aiSearchName = "aisearchswan2",
    [string]$resourceGroup = "AI_Related", 
    [string]$subscription = "48ab3756-f962-40a8-b0cf-b33ddae744bb",
    [string]$workspaceId = "66bf0752-f3f3-4ec8-b8fa-29d1f885815e",
    [string]$lakehouseId = "1f3ba253-8305-4e9e-b053-946c261c6957"
)

Write-Host "Creating OneLake indexer with PREVIEW API version (2024-05-01-preview)"
Write-Host "======================================================================"

# Get API key
$apiKey = az search admin-key show --service-name $aiSearchName --resource-group $resourceGroup --subscription $subscription --query primaryKey -o tsv

$headers = @{
    'api-key' = $apiKey
    'Content-Type' = 'application/json'
}

# Use the REQUIRED preview API version for OneLake
$apiVersion = '2024-05-01-preview'

Write-Host "Using API version: $apiVersion"
Write-Host ""

# 1. Create OneLake data source with SAMI (no identity field as per docs)
Write-Host "1. Creating OneLake data source with SAMI..."

$dataSourceBody = @{
    name = "reports-onelake-preview"
    description = "OneLake data source using preview API and SAMI"
    type = "onelake" 
    credentials = @{
        connectionString = "ResourceId=$workspaceId"
    }
    container = @{
        name = $lakehouseId
        query = "Files/documents/reports"
    }
    dataChangeDetectionPolicy = @{
        '@odata.type' = '#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy'
        highWaterMarkColumnName = 'metadata_storage_last_modified'
    }
} | ConvertTo-Json -Depth 10

# Delete existing if present
try {
    $deleteUrl = "https://$aiSearchName.search.windows.net/datasources/reports-onelake-preview?api-version=$apiVersion"
    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE
    Write-Host "Deleted existing data source"
} catch {
    Write-Host "No existing data source to delete"
}

# Create data source with preview API
$createUrl = "https://$aiSearchName.search.windows.net/datasources?api-version=$apiVersion"

try {
    $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $dataSourceBody
    Write-Host "✅ SUCCESS! OneLake data source created with preview API"
    Write-Host "Data source name: $($response.name)"
    
    # Test the connection
    Write-Host ""
    Write-Host "2. Testing connection..."
    try {
        $testUrl = "https://$aiSearchName.search.windows.net/datasources/reports-onelake-preview/test?api-version=$apiVersion"
        Invoke-RestMethod -Uri $testUrl -Headers $headers -Method POST
        Write-Host "✅ Connection test PASSED!"
        
        # 3. Create indexer with preview API
        Write-Host ""
        Write-Host "3. Creating indexer with preview API..."
        
        $indexerBody = @{
            name = "reports-onelake-preview-indexer"
            dataSourceName = "reports-onelake-preview"
            targetIndexName = "reports-index"
            skillsetName = "onelake-textonly-skillset"
        } | ConvertTo-Json -Depth 10
        
        # Delete existing indexer
        try {
            $deleteIndexerUrl = "https://$aiSearchName.search.windows.net/indexers/reports-onelake-preview-indexer?api-version=$apiVersion"
            Invoke-RestMethod -Uri $deleteIndexerUrl -Headers $headers -Method DELETE
            Write-Host "Deleted existing indexer"
        } catch {
            Write-Host "No existing indexer to delete"
        }
        
        $indexerUrl = "https://$aiSearchName.search.windows.net/indexers?api-version=$apiVersion"
        $indexerResponse = Invoke-RestMethod -Uri $indexerUrl -Headers $headers -Method POST -Body $indexerBody
        
        Write-Host "✅ Indexer created with preview API!"
        Write-Host "Indexer name: $($indexerResponse.name)"
        
        # 4. Run the indexer
        Write-Host ""
        Write-Host "4. Running indexer..."
        $runUrl = "https://$aiSearchName.search.windows.net/indexers/reports-onelake-preview-indexer/run?api-version=$apiVersion"
        Invoke-RestMethod -Uri $runUrl -Headers $headers -Method POST
        Write-Host "Indexer triggered! Waiting 30 seconds for processing..."
        
        Start-Sleep -Seconds 30
        
        # 5. Check results
        Write-Host ""
        Write-Host "5. Checking indexer results..."
        $statusUrl = "https://$aiSearchName.search.windows.net/indexers/reports-onelake-preview-indexer/status?api-version=$apiVersion"
        $status = Invoke-RestMethod -Uri $statusUrl -Headers $headers -Method GET
        
        Write-Host ""
        Write-Host "🎯 PREVIEW API INDEXER RESULTS:"
        Write-Host "================================"
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
            Write-Host "🎉 SUCCESS! Preview API found and processed $($status.lastResult.itemsProcessed) documents!"
            
            # Check the search index
            $searchUrl = "https://$aiSearchName.search.windows.net/indexes/reports-index/docs?api-version=$apiVersion&search=*&`$count=true"
            $searchResults = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
            Write-Host "Total documents in search index: $($searchResults.'@odata.count')"
            
            if ($searchResults.'@odata.count' -gt 0) {
                Write-Host ""
                Write-Host "Sample documents found:"
                $searchResults.value | Select-Object -First 5 | ForEach-Object {
                    Write-Host "  - $($_.metadata_storage_name)"
                }
            }
        } else {
            Write-Host ""
            Write-Host "❌ Still processing 0 items even with preview API"
            Write-Host "This suggests a deeper authentication or permission issue"
        }
        
    } catch {
        Write-Host "❌ Connection test failed: $($_.Exception.Message)"
    }
    
} catch {
    Write-Host "❌ Failed to create OneLake data source with preview API"
    Write-Host "Error: $($_.Exception.Message)"
    
    # Get detailed error
    if ($_.Exception.Response) {
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $errorBody = $reader.ReadToEnd()
            Write-Host ""
            Write-Host "Detailed error:"
            Write-Host $errorBody
            
            $errorObj = $errorBody | ConvertFrom-Json
            if ($errorObj.error) {
                Write-Host ""
                Write-Host "Error code: $($errorObj.error.code)"
                Write-Host "Error message: $($errorObj.error.message)"
            }
        } catch {
            Write-Host "Could not parse error details"
        }
    }
}

Write-Host ""
Write-Host "Script completed. If successful, the OneLake indexer should now be working!"
