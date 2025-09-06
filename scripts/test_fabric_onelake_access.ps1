#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test OneLake file access using Fabric APIs directly

.DESCRIPTION
    This script uses Microsoft Fabric APIs to directly test file access in OneLake
    before attempting to use Azure AI Search indexers

.EXAMPLE
    ./test_fabric_onelake_access.ps1
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

Write-ColorOutput "=== Testing OneLake Access with Fabric APIs ===" $Magenta
Write-ColorOutput "Workspace ID: $workspaceId" $Cyan
Write-ColorOutput "Lakehouse ID: $lakehouseId" $Cyan

try {
    # Get Fabric access token
    Write-ColorOutput "`n1. Getting Fabric access token..." $Blue
    $fabricToken = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
    
    if (-not $fabricToken) {
        throw "Failed to get Fabric access token"
    }
    Write-ColorOutput "✅ Successfully obtained Fabric access token" $Green

    $headers = @{
        'Authorization' = "Bearer $fabricToken"
        'Content-Type' = 'application/json'
    }

    # Test workspace access
    Write-ColorOutput "`n2. Testing workspace access..." $Blue
    try {
        $workspace = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId" -Headers $headers
        Write-ColorOutput "✅ Workspace access successful: $($workspace.displayName)" $Green
    } catch {
        Write-ColorOutput "❌ Cannot access workspace: $($_.Exception.Message)" $Red
        throw "Workspace access failed"
    }

    # Test lakehouse access
    Write-ColorOutput "`n3. Testing lakehouse access..." $Blue
    try {
        $lakehouse = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/lakehouses/$lakehouseId" -Headers $headers
        Write-ColorOutput "✅ Lakehouse access successful: $($lakehouse.displayName)" $Green
    } catch {
        Write-ColorOutput "❌ Cannot access lakehouse: $($_.Exception.Message)" $Red
        throw "Lakehouse access failed"
    }

    # List files in the lakehouse using OneLake API
    Write-ColorOutput "`n4. Testing OneLake file listing..." $Blue
    
    # OneLake uses a different endpoint pattern
    $oneLakeBaseUrl = "https://onelake.dfs.fabric.microsoft.com"
    
    # Try to list files in the root Files directory
    Write-ColorOutput "Testing Files directory access..." $Cyan
    try {
        $filesUrl = "$oneLakeBaseUrl/$workspaceId/$lakehouseId/Files?resource=filesystem&recursive=false"
        $filesResponse = Invoke-RestMethod -Uri $filesUrl -Headers $headers
        Write-ColorOutput "✅ Successfully accessed Files directory" $Green
        
        # Parse the response (OneLake returns directory listing in a specific format)
        Write-ColorOutput "Files directory contents:" $Cyan
        if ($filesResponse) {
            Write-Host $filesResponse
        }
        
    } catch {
        Write-ColorOutput "❌ Cannot list Files directory: $($_.Exception.Message)" $Red
        Write-ColorOutput "Status: $($_.Exception.Response.StatusCode)" $Yellow
    }

    # Try alternative OneLake API endpoints
    Write-ColorOutput "`n5. Testing alternative OneLake endpoints..." $Blue
    
    # Try the path-based approach
    $pathUrls = @(
        "$oneLakeBaseUrl/$workspaceId/$lakehouseId/Files",
        "$oneLakeBaseUrl/$workspaceId/$lakehouseId/Files/documents",
        "$oneLakeBaseUrl/$workspaceId/$lakehouseId/Files/documents/reports"
    )
    
    foreach ($url in $pathUrls) {
        $path = $url -replace ".*Files", "Files"
        Write-ColorOutput "Testing path: $path" $Cyan
        
        try {
            # Try different query parameters
            $testUrls = @(
                "$url?resource=filesystem",
                "$url?recursive=true",
                "$url?directory",
                $url
            )
            
            $success = $false
            foreach ($testUrl in $testUrls) {
                try {
                    $response = Invoke-RestMethod -Uri $testUrl -Headers $headers
                    Write-ColorOutput "✅ Success with: $($testUrl -replace '.*(\?.*)', '$1')" $Green
                    if ($response) {
                        Write-ColorOutput "Response content:" $Blue
                        Write-Host ($response | Out-String).Substring(0, [Math]::Min(($response | Out-String).Length, 500))
                    }
                    $success = $true
                    break
                } catch {
                    # Continue to next URL
                }
            }
            
            if (-not $success) {
                Write-ColorOutput "❌ All attempts failed for $path" $Red
            }
            
        } catch {
            Write-ColorOutput "❌ Failed to access $path" $Red
        }
    }

    # Test if we can access files directly (if we know specific file names)
    Write-ColorOutput "`n6. Testing direct file access..." $Blue
    
    # Try to access a known file
    $testFiles = @(
        "Files/documents/reports/FY25 Fabric Workshop.pdf",
        "Files/documents/reports/simpletest.txt"
    )
    
    foreach ($filePath in $testFiles) {
        Write-ColorOutput "Testing file: $filePath" $Cyan
        try {
            $fileUrl = "$oneLakeBaseUrl/$workspaceId/$lakehouseId/$filePath"
            $fileHeaders = $headers.Clone()
            $fileHeaders['Range'] = 'bytes=0-1023'  # Just get first 1KB to test access
            
            $fileResponse = Invoke-RestMethod -Uri $fileUrl -Headers $fileHeaders -Method Head
            Write-ColorOutput "✅ Can access file: $filePath" $Green
            
        } catch {
            Write-ColorOutput "❌ Cannot access file: $filePath" $Red
            Write-ColorOutput "   Error: $($_.Exception.Message)" $Yellow
        }
    }

} catch {
    Write-ColorOutput "❌ Test failed: $($_.Exception.Message)" $Red
    Write-ColorOutput "This indicates a fundamental access issue with OneLake or Fabric APIs" $Yellow
    exit 1
}

Write-ColorOutput "`n=== Fabric API Test Complete ===" $Magenta
Write-ColorOutput "If files were found, the issue is with Azure AI Search OneLake connector" $Cyan
Write-ColorOutput "If no files found, the issue is with OneLake data access permissions" $Cyan
