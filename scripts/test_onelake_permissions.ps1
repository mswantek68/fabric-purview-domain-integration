#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick test to verify OneLake data access permissions are working after manual role configuration

.DESCRIPTION
    This script tests if the OneLake data access role you created manually in Fabric Portal
    is allowing AI Search indexers to access files

.EXAMPLE
    ./test_onelake_permissions.ps1
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

Write-ColorOutput "=== Testing OneLake Data Access Permissions ===" $Magenta

# Configuration
$searchServiceName = "aisearchswan2"
$resourceGroup = "AI_Related"

try {
    # Get AI Search admin key
    Write-ColorOutput "Getting AI Search admin key..." $Cyan
    $searchKey = az search admin-key show --service-name $searchServiceName --resource-group $resourceGroup --query primaryKey -o tsv
    $headers = @{'api-key' = $searchKey}

    # Test presentations indexer (should now work with new permissions)
    Write-ColorOutput "`nTesting presentations indexer..." $Cyan
    
    try {
        # Run the indexer
        Invoke-RestMethod -Uri "https://$searchServiceName.search.windows.net/indexers/files-documents-presentations-indexer/run?api-version=2024-05-01-preview" -Method Post -Headers $headers | Out-Null
        
        Write-ColorOutput "Waiting 30 seconds for indexer to process..." $Yellow
        Start-Sleep -Seconds 30
        
        # Check results
        $status = Invoke-RestMethod -Uri "https://$searchServiceName.search.windows.net/indexers/files-documents-presentations-indexer/status?api-version=2024-05-01-preview" -Headers $headers
        
        Write-ColorOutput "Presentations Indexer Results:" $Cyan
        Write-ColorOutput "  Status: $($status.lastResult.status)" $Cyan
        Write-ColorOutput "  Items Processed: $($status.lastResult.itemsProcessed)" $Cyan
        Write-ColorOutput "  Items Failed: $($status.lastResult.itemsFailed)" $Cyan
        
        if ($status.lastResult.itemsProcessed -gt 0) {
            Write-ColorOutput "✅ SUCCESS! OneLake data access is working!" $Green
            Write-ColorOutput "The presentations indexer found $($status.lastResult.itemsProcessed) items" $Green
            
            # Now we can create the reports data source
            Write-ColorOutput "`nPermissions are working - ready to create reports data source!" $Green
            
        } else {
            Write-ColorOutput "❌ Still getting 0 items processed" $Red
            
            if ($status.lastResult.errorMessage) {
                Write-ColorOutput "Error: $($status.lastResult.errorMessage)" $Red
            }
            
            Write-ColorOutput "This could mean:" $Yellow
            Write-ColorOutput "  1. Permissions need more time to propagate (wait 5-10 minutes)" $Yellow
            Write-ColorOutput "  2. The role configuration needs adjustment" $Yellow
            Write-ColorOutput "  3. The AI Search managed identity wasn't added correctly" $Yellow
        }
        
    } catch {
        Write-ColorOutput "❌ Failed to test presentations indexer: $($_.Exception.Message)" $Red
    }

    # Show current OneLake data sources for reference
    Write-ColorOutput "`nCurrent OneLake Data Sources:" $Cyan
    try {
        $dataSources = Invoke-RestMethod -Uri "https://$searchServiceName.search.windows.net/datasources?api-version=2024-05-01-preview" -Headers $headers
        $oneLakeDataSources = $dataSources.value | Where-Object { $_.type -eq 'onelake' }
        
        $oneLakeDataSources | ForEach-Object {
            Write-ColorOutput "  - $($_.name)" $Cyan
        }
        
    } catch {
        Write-ColorOutput "Could not list data sources" $Yellow
    }

} catch {
    Write-ColorOutput "❌ Test failed: $($_.Exception.Message)" $Red
    exit 1
}

Write-ColorOutput "`n=== Test Complete ===" $Magenta
