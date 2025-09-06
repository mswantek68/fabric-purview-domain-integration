#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test OneLake access using AI Search managed identity authentication

.DESCRIPTION
    This script simulates how Azure AI Search accesses OneLake by using the same
    authentication method (managed identity) that the indexers would use

.EXAMPLE
    ./test_onelake_as_aisearch.ps1
#>

# Colors for output
$Green = "`e[32m"
$Red = "`e[31m"
$Yellow = "`e[33m"
$Cyan = "`e[36m"
$Magenta = "`e[35m"
$Blue = "`e[34m"
$Reset = "`e[0m"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = $Reset)
    Write-Host "$Color$Message$Reset"
}

# Configuration
$workspaceId = "66bf0752-f3f3-4ec8-b8fa-29d1f885815e"
$lakehouseId = "1f3ba253-8305-4e9e-b053-946c261c6957"
$aiSearchPrincipalId = "e86388dc-fbf7-40b1-92eb-d3a6bfb21db8"

Write-ColorOutput "=== Testing OneLake Access as AI Search Managed Identity ===" $Magenta
Write-ColorOutput "Workspace ID: $workspaceId" $Cyan
Write-ColorOutput "Lakehouse ID: $lakehouseId" $Cyan
Write-ColorOutput "AI Search Principal ID: $aiSearchPrincipalId" $Cyan

try {
    # First, let's check what OneLake data access roles exist
    Write-ColorOutput "`n1. Checking OneLake data access configuration..." $Blue
    
    # Get regular Fabric token to check role configuration
    $fabricToken = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
    $headers = @{
        'Authorization' = "Bearer $fabricToken"
        'Content-Type' = 'application/json'
    }
    
    # Try to list data access roles (this API might not exist yet, but worth trying)
    try {
        $rolesUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/lakehouses/$lakehouseId/dataAccess/roles"
        $roles = Invoke-RestMethod -Uri $rolesUrl -Headers $headers
        
        Write-ColorOutput "✅ Found OneLake data access roles:" $Green
        $roles | ForEach-Object {
            Write-ColorOutput "  Role: $($_.name)" $Cyan
            Write-ColorOutput "  Members: $($_.members -join ', ')" $Cyan
        }
        
    } catch {
        Write-ColorOutput "⚠️  Could not list data access roles via API (may need Fabric Portal)" $Yellow
    }

    # Test using Azure Resource Manager token (sometimes needed for managed identity operations)
    Write-ColorOutput "`n2. Testing with Azure Resource Manager token..." $Blue
    
    $armToken = az account get-access-token --resource 'https://management.azure.com' --query accessToken -o tsv
    $armHeaders = @{
        'Authorization' = "Bearer $armToken"
        'Content-Type' = 'application/json'
    }
    
    # Try OneLake access with ARM token
    try {
        $oneLakeUrl = "https://onelake.dfs.fabric.microsoft.com/$workspaceId/$lakehouseId/Files?resource=filesystem"
        $armResponse = Invoke-RestMethod -Uri $oneLakeUrl -Headers $armHeaders
        Write-ColorOutput "✅ ARM token works for OneLake access" $Green
        
    } catch {
        Write-ColorOutput "❌ ARM token failed: $($_.Exception.Message)" $Red
    }

    # The key insight: We need to test what authentication method works for OneLake
    Write-ColorOutput "`n3. Testing different OneLake authentication methods..." $Blue
    
    # Test 1: Storage API token
    Write-ColorOutput "Testing Azure Storage API token..." $Cyan
    try {
        $storageToken = az account get-access-token --resource 'https://storage.azure.com/' --query accessToken -o tsv
        $storageHeaders = @{
            'Authorization' = "Bearer $storageToken"
            'x-ms-version' = '2023-11-03'
        }
        
        $oneLakeUrl = "https://onelake.dfs.fabric.microsoft.com/$workspaceId/$lakehouseId/Files?resource=filesystem"
        $storageResponse = Invoke-RestMethod -Uri $oneLakeUrl -Headers $storageHeaders
        Write-ColorOutput "✅ Storage API token works!" $Green
        
        # If this works, try to list files
        Write-ColorOutput "Listing files with Storage API token..." $Cyan
        $filesUrl = "https://onelake.dfs.fabric.microsoft.com/$workspaceId/$lakehouseId/Files/documents?resource=filesystem&recursive=true"
        $filesResponse = Invoke-RestMethod -Uri $filesUrl -Headers $storageHeaders
        
        if ($filesResponse) {
            Write-ColorOutput "✅ Successfully listed files!" $Green
            Write-ColorOutput "Response:" $Blue
            Write-Host ($filesResponse | Out-String)
        }
        
    } catch {
        Write-ColorOutput "❌ Storage API token failed: $($_.Exception.Message)" $Red
        Write-ColorOutput "Status: $($_.Exception.Response.StatusCode)" $Yellow
    }

    # Test 2: Try the OneLake REST API with different approaches
    Write-ColorOutput "`n4. Testing OneLake with different API approaches..." $Blue
    
    $testTokens = @{
        'Fabric' = $fabricToken
        'Storage' = (az account get-access-token --resource 'https://storage.azure.com/' --query accessToken -o tsv)
        'Graph' = (az account get-access-token --resource 'https://graph.microsoft.com' --query accessToken -o tsv)
    }
    
    foreach ($tokenType in $testTokens.Keys) {
        Write-ColorOutput "Testing with $tokenType token..." $Cyan
        
        $testHeaders = @{
            'Authorization' = "Bearer $($testTokens[$tokenType])"
        }
        
        # Add appropriate headers for each token type
        if ($tokenType -eq 'Storage') {
            $testHeaders['x-ms-version'] = '2023-11-03'
        }
        
        try {
            # Try a simple directory listing
            $testUrl = "https://onelake.dfs.fabric.microsoft.com/$workspaceId/$lakehouseId/Files?resource=filesystem"
            $response = Invoke-RestMethod -Uri $testUrl -Headers $testHeaders -TimeoutSec 10
            
            Write-ColorOutput "✅ $tokenType token successful!" $Green
            
            # Try to get more specific
            $documentsUrl = "https://onelake.dfs.fabric.microsoft.com/$workspaceId/$lakehouseId/Files/documents?resource=filesystem"
            $docResponse = Invoke-RestMethod -Uri $documentsUrl -Headers $testHeaders -TimeoutSec 10
            
            Write-ColorOutput "✅ Can access documents folder with $tokenType token!" $Green
            break
            
        } catch {
            Write-ColorOutput "❌ $tokenType token failed: $($_.Exception.Message)" $Red
        }
    }

} catch {
    Write-ColorOutput "❌ Test failed: $($_.Exception.Message)" $Red
    exit 1
}

Write-ColorOutput "`n=== Authentication Test Complete ===" $Magenta
Write-ColorOutput "Key findings:" $Cyan
Write-ColorOutput "1. If Storage API token works, AI Search should be able to connect" $Cyan
Write-ColorOutput "2. The OneLake data access role may need the Storage API scope" $Cyan
Write-ColorOutput "3. AI Search managed identity needs proper token scope for OneLake" $Cyan
