#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Create reports OneLake data source and indexer step by step

.DESCRIPTION
    Simple script to create the reports data source and indexer with error handling

.EXAMPLE
    ./create_reports_indexer.ps1
#>

# Colors for output
$Green = "`e[32m"
$Red = "`e[31m"
$Yellow = "`e[33m"
$Cyan = "`e[36m"
$Magenta = "`e[35m"
$Reset = "`e[0m"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = $Reset)
    Write-Host "$Color$Message$Reset"
}

Write-ColorOutput "=== Creating Reports OneLake Data Source and Indexer ===" $Magenta

try {
    # Get AI Search admin key
    $key = az search admin-key show --service-name 'aisearchswan2' --resource-group 'AI_Related' --query primaryKey -o tsv
    $headers = @{'api-key' = $key}

    # Step 1: Verify deletion
    Write-ColorOutput "`n1. Checking current status..." $Cyan
    
    $dataSourceExists = $false
    $indexerExists = $false
    
    try {
        $ds = Invoke-RestMethod -Uri 'https://aisearchswan2.search.windows.net/datasources/files-documents-reports-onelake-datasource?api-version=2024-05-01-preview' -Headers $headers
        Write-ColorOutput "⚠️  Data source still exists" $Yellow
        $dataSourceExists = $true
    } catch {
        Write-ColorOutput "✅ Data source confirmed deleted" $Green
    }

    try {
        $indexer = Invoke-RestMethod -Uri 'https://aisearchswan2.search.windows.net/indexers/files-documents-reports-indexer?api-version=2024-05-01-preview' -Headers $headers
        Write-ColorOutput "⚠️  Indexer still exists" $Yellow
        $indexerExists = $true
    } catch {
        Write-ColorOutput "✅ Indexer confirmed deleted" $Green
    }

    # Step 2: Create data source if it doesn't exist
    if (-not $dataSourceExists) {
        Write-ColorOutput "`n2. Creating reports data source..." $Cyan
        
        # Try the simple approach first
        $reportsDataSource = @{
            name = 'files-documents-reports-onelake-datasource'
            type = 'onelake'
            container = @{
                name = '1f3ba253-8305-4e9e-b053-946c261c6957'
                query = 'Files/documents/reports'
            }
            credentials = @{
                connectionString = $null
            }
        } | ConvertTo-Json -Depth 10

        try {
            $dsResult = Invoke-RestMethod -Uri 'https://aisearchswan2.search.windows.net/datasources?api-version=2024-05-01-preview' -Method Post -Headers $headers -Body $reportsDataSource -ContentType 'application/json'
            
            Write-ColorOutput "✅ Data source created successfully!" $Green
            Write-ColorOutput "  Name: $($dsResult.name)" $Cyan
            $dataSourceExists = $true
            
        } catch {
            Write-ColorOutput "❌ Data source creation failed: $($_.Exception.Message)" $Red
            
            # Try alternative approach - copy from working data source
            Write-ColorOutput "Trying to copy from working presentations data source..." $Yellow
            
            try {
                $workingDS = Invoke-RestMethod -Uri 'https://aisearchswan2.search.windows.net/datasources/files-documents-presentations-onelake-datasource?api-version=2024-05-01-preview' -Headers $headers
                
                # Modify for reports
                $workingDS.name = 'files-documents-reports-onelake-datasource'
                $workingDS.container.query = 'Files/documents/reports'
                
                # Remove read-only properties
                $workingDS.PSObject.Properties.Remove('@odata.etag')
                $workingDS.PSObject.Properties.Remove('@odata.context')
                
                $copyBody = $workingDS | ConvertTo-Json -Depth 10
                
                $dsResult = Invoke-RestMethod -Uri 'https://aisearchswan2.search.windows.net/datasources?api-version=2024-05-01-preview' -Method Post -Headers $headers -Body $copyBody -ContentType 'application/json'
                
                Write-ColorOutput "✅ Data source created by copying working template!" $Green
                $dataSourceExists = $true
                
            } catch {
                Write-ColorOutput "❌ Template copy also failed: $($_.Exception.Message)" $Red
                Write-ColorOutput "Manual creation in Azure Portal may be required" $Yellow
            }
        }
    }

    # Step 3: Create indexer if data source exists
    if ($dataSourceExists -and -not $indexerExists) {
        Write-ColorOutput "`n3. Creating reports indexer..." $Cyan
        
        $reportsIndexer = @{
            name = 'files-documents-reports-indexer'
            dataSourceName = 'files-documents-reports-onelake-datasource'
            targetIndexName = 'documents-index'
            parameters = @{
                batchSize = 10
                maxFailedItems = 100
                maxFailedItemsPerBatch = 100
                configuration = @{
                    indexedFileNameExtensions = '.pdf,.docx,.doc,.txt,.pptx,.ppt'
                    excludedFileNameExtensions = '.json'
                    dataToExtract = 'contentAndMetadata'
                    parsingMode = 'default'
                }
            }
        } | ConvertTo-Json -Depth 10

        try {
            $indexerResult = Invoke-RestMethod -Uri 'https://aisearchswan2.search.windows.net/indexers?api-version=2024-05-01-preview' -Method Post -Headers $headers -Body $reportsIndexer -ContentType 'application/json'
            
            Write-ColorOutput "✅ Indexer created successfully!" $Green
            Write-ColorOutput "  Name: $($indexerResult.name)" $Cyan
            Write-ColorOutput "  Data Source: $($indexerResult.dataSourceName)" $Cyan
            $indexerExists = $true
            
        } catch {
            Write-ColorOutput "❌ Indexer creation failed: $($_.Exception.Message)" $Red
        }
    }

    # Step 4: Test the indexer if it exists
    if ($indexerExists) {
        Write-ColorOutput "`n4. Testing the reports indexer..." $Cyan
        
        try {
            # Run the indexer
            Invoke-RestMethod -Uri 'https://aisearchswan2.search.windows.net/indexers/files-documents-reports-indexer/run?api-version=2024-05-01-preview' -Method Post -Headers $headers | Out-Null
            
            Write-ColorOutput "Waiting 30 seconds for indexing..." $Yellow
            Start-Sleep -Seconds 30
            
            # Check results
            $status = Invoke-RestMethod -Uri 'https://aisearchswan2.search.windows.net/indexers/files-documents-reports-indexer/status?api-version=2024-05-01-preview' -Headers $headers
            
            Write-ColorOutput "`nIndexer Results:" $Cyan
            Write-ColorOutput "  Status: $($status.lastResult.status)" $Cyan
            Write-ColorOutput "  Items Processed: $($status.lastResult.itemsProcessed)" $Cyan
            Write-ColorOutput "  Items Failed: $($status.lastResult.itemsFailed)" $Cyan
            Write-ColorOutput "  Duration: $([DateTime]$status.lastResult.endTime - [DateTime]$status.lastResult.startTime)" $Cyan
            
            if ($status.lastResult.itemsProcessed -gt 0) {
                Write-ColorOutput "`n🎉 SUCCESS! Reports indexer found and processed $($status.lastResult.itemsProcessed) files!" $Green
            } else {
                Write-ColorOutput "`n❌ Indexer found 0 items" $Red
                
                if ($status.lastResult.errors -and $status.lastResult.errors.Count -gt 0) {
                    Write-ColorOutput "Errors:" $Red
                    $status.lastResult.errors | ForEach-Object {
                        Write-ColorOutput "  - $($_.errorMessage)" $Red
                    }
                } else {
                    Write-ColorOutput "No errors reported - may be a permission propagation delay" $Yellow
                }
            }
            
        } catch {
            Write-ColorOutput "❌ Failed to run indexer: $($_.Exception.Message)" $Red
        }
    }

    # Summary
    Write-ColorOutput "`n=== Summary ===" $Magenta
    if ($dataSourceExists) {
        Write-ColorOutput "✅ Data source: Created" $Green
    } else {
        Write-ColorOutput "❌ Data source: Failed to create" $Red
    }
    
    if ($indexerExists) {
        Write-ColorOutput "✅ Indexer: Created" $Green
    } else {
        Write-ColorOutput "❌ Indexer: Failed to create" $Red
    }

} catch {
    Write-ColorOutput "❌ Script failed: $($_.Exception.Message)" $Red
    exit 1
}
