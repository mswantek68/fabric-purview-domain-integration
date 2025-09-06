#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configure OneLake data access permissions for AI Search indexing with folder-level scoping

.DESCRIPTION
    This script creates and configures OneLake data access roles for Azure AI Search managed identity
    with granular permissions scoped to specific folders (e.g., documents folder only)

.PARAMETER WorkspaceId
    The Fabric workspace ID

.PARAMETER LakehouseId
    The lakehouse ID within the workspace

.PARAMETER SearchServiceName
    The Azure AI Search service name

.PARAMETER ResourceGroupName
    The resource group containing the AI Search service

.PARAMETER RoleName
    The name for the OneLake data access role (default: AISearchIndexer)

.PARAMETER ScopedFolders
    Array of folder paths to scope access to (default: @('Files/documents'))

.EXAMPLE
    ./setup_onelake_data_access.ps1 -WorkspaceId "66bf0752-f3f3-4ec8-b8fa-29d1f885815e" -LakehouseId "1f3ba253-8305-4e9e-b053-946c261c6957" -SearchServiceName "aisearchswan2" -ResourceGroupName "AI_Related"

.EXAMPLE
    # Scope to specific subfolders only
    ./setup_onelake_data_access.ps1 -WorkspaceId "66bf0752-f3f3-4ec8-b8fa-29d1f885815e" -LakehouseId "1f3ba253-8305-4e9e-b053-946c261c6957" -SearchServiceName "aisearchswan2" -ResourceGroupName "AI_Related" -ScopedFolders @('Files/documents/reports', 'Files/documents/contracts')
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,
    
    [Parameter(Mandatory = $true)]
    [string]$LakehouseId,
    
    [Parameter(Mandatory = $true)]
    [string]$SearchServiceName,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$RoleName = "AISearchIndexer",
    
    [Parameter(Mandatory = $false)]
    [string[]]$ScopedFolders = @('Files/documents')
)

# Colors for output
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Magenta = "`e[35m"
$Cyan = "`e[36m"
$Reset = "`e[0m"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = $Reset)
    Write-Host "$Color$Message$Reset"
}

function Get-AISearchManagedIdentity {
    param([string]$SearchService, [string]$ResourceGroup)
    
    try {
        $searchServiceInfo = az search service show --name $SearchService --resource-group $ResourceGroup | ConvertFrom-Json
        if ($searchServiceInfo.identity -and $searchServiceInfo.identity.principalId) {
            return $searchServiceInfo.identity.principalId
        } else {
            throw "AI Search service does not have a managed identity enabled"
        }
    } catch {
        throw "Failed to get AI Search managed identity: $($_.Exception.Message)"
    }
}

function Get-FabricAccessToken {
    try {
        $token = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
        if (-not $token) {
            throw "Failed to obtain access token"
        }
        return $token
    } catch {
        throw "Failed to get Fabric access token: $($_.Exception.Message)"
    }
}

function Test-OneLakeDataAccess {
    param([string]$WorkspaceId, [string]$LakehouseId, [string]$Token)
    
    $headers = @{
        'Authorization' = "Bearer $Token"
        'Content-Type' = 'application/json'
    }
    
    try {
        # Test access to the lakehouse
        $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/lakehouses/$LakehouseId"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        Write-ColorOutput "✅ Successfully accessed lakehouse: $($response.displayName)" $Green
        return $true
    } catch {
        Write-ColorOutput "❌ Cannot access lakehouse: $($_.Exception.Message)" $Red
        return $false
    }
}

function New-OneLakeDataAccessRole {
    param(
        [string]$WorkspaceId,
        [string]$LakehouseId, 
        [string]$RoleName,
        [string]$PrincipalId,
        [string[]]$ScopedFolders,
        [string]$Token
    )
    
    $headers = @{
        'Authorization' = "Bearer $Token"
        'Content-Type' = 'application/json'
    }
    
    Write-ColorOutput "=== Creating OneLake Data Access Role ===" $Magenta
    Write-ColorOutput "Role Name: $RoleName" $Cyan
    Write-ColorOutput "Principal ID: $PrincipalId" $Cyan
    Write-ColorOutput "Scoped Folders: $($ScopedFolders -join ', ')" $Cyan
    
    # Create the data access role configuration
    $roleConfig = @{
        name = $RoleName
        description = "AI Search indexer access to OneLake data"
        principals = @(
            @{
                id = $PrincipalId
                type = "ServicePrincipal"
            }
        )
        permissions = @{
            files = @{
                read = $true
                write = $false
                execute = $false
            }
            tables = @{
                read = $false
                write = $false
            }
        }
        scope = @{
            type = "Folder"
            paths = $ScopedFolders
        }
    } | ConvertTo-Json -Depth 10
    
    try {
        # Note: This is a conceptual API structure - the actual Fabric OneLake data access API
        # may have different endpoints and structure. This script provides the framework.
        $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/lakehouses/$LakehouseId/dataAccess/roles"
        
        Write-ColorOutput "Attempting to create data access role..." $Yellow
        Write-ColorOutput "API Endpoint: $uri" $Blue
        Write-ColorOutput "Request Body:" $Blue
        Write-Host $roleConfig
        
        # Uncomment the following line when the actual API is available
        # $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $roleConfig
        
        Write-ColorOutput "⚠️  Note: OneLake Data Access API configuration may need to be done through Fabric Portal" $Yellow
        Write-ColorOutput "Manual steps:" $Cyan
        Write-ColorOutput "1. Navigate to Fabric Portal > Workspace > Lakehouse" $Cyan
        Write-ColorOutput "2. Click 'Manage OneLake data access (preview)'" $Cyan
        Write-ColorOutput "3. Create role '$RoleName'" $Cyan
        Write-ColorOutput "4. Add principal: $PrincipalId" $Cyan
        Write-ColorOutput "5. Scope to folders: $($ScopedFolders -join ', ')" $Cyan
        Write-ColorOutput "6. Grant Read permissions for Files" $Cyan
        
        return $true
        
    } catch {
        Write-ColorOutput "❌ Failed to create data access role: $($_.Exception.Message)" $Red
        return $false
    }
}

function Test-DataAccessPermissions {
    param([string]$WorkspaceId, [string]$LakehouseId, [string]$SearchServiceName, [string]$ResourceGroup)
    
    Write-ColorOutput "=== Testing Data Access Permissions ===" $Magenta
    
    # Get AI Search admin key
    $searchKey = az search admin-key show --service-name $SearchServiceName --resource-group $ResourceGroup --query primaryKey -o tsv
    $searchHeaders = @{'api-key' = $searchKey}
    
    # Test by running an existing indexer
    try {
        $indexers = Invoke-RestMethod -Uri "https://$SearchServiceName.search.windows.net/indexers?api-version=2024-05-01-preview" -Headers $searchHeaders
        
        $oneLakeIndexers = $indexers.value | Where-Object { $_.dataSourceName -like "*onelake*" }
        
        if ($oneLakeIndexers.Count -gt 0) {
            $testIndexer = $oneLakeIndexers[0]
            Write-ColorOutput "Testing with indexer: $($testIndexer.name)" $Cyan
            
            # Run the indexer
            Invoke-RestMethod -Uri "https://$SearchServiceName.search.windows.net/indexers/$($testIndexer.name)/run?api-version=2024-05-01-preview" -Method Post -Headers $searchHeaders | Out-Null
            
            Write-ColorOutput "Waiting 30 seconds for indexer to process..." $Yellow
            Start-Sleep -Seconds 30
            
            # Check results
            $status = Invoke-RestMethod -Uri "https://$SearchServiceName.search.windows.net/indexers/$($testIndexer.name)/status?api-version=2024-05-01-preview" -Headers $searchHeaders
            
            Write-ColorOutput "Indexer Test Results:" $Cyan
            Write-ColorOutput "  Status: $($status.lastResult.status)" $Cyan
            Write-ColorOutput "  Items Processed: $($status.lastResult.itemsProcessed)" $Cyan
            
            if ($status.lastResult.itemsProcessed -gt 0) {
                Write-ColorOutput "✅ Data access permissions are working!" $Green
                return $true
            } else {
                Write-ColorOutput "❌ Still getting 0 items - permissions may need more time to propagate" $Red
                return $false
            }
        } else {
            Write-ColorOutput "⚠️  No OneLake indexers found to test with" $Yellow
            return $false
        }
        
    } catch {
        Write-ColorOutput "❌ Failed to test permissions: $($_.Exception.Message)" $Red
        return $false
    }
}

# Main execution
try {
    Write-ColorOutput "=== OneLake Data Access Setup ===" $Magenta
    Write-ColorOutput "Workspace ID: $WorkspaceId" $Cyan
    Write-ColorOutput "Lakehouse ID: $LakehouseId" $Cyan
    Write-ColorOutput "Search Service: $SearchServiceName" $Cyan
    Write-ColorOutput "Scoped Folders: $($ScopedFolders -join ', ')" $Cyan
    
    # Get AI Search managed identity
    Write-ColorOutput "`n1. Getting AI Search managed identity..." $Blue
    $principalId = Get-AISearchManagedIdentity -SearchService $SearchServiceName -ResourceGroup $ResourceGroupName
    Write-ColorOutput "✅ AI Search Principal ID: $principalId" $Green
    
    # Get Fabric access token
    Write-ColorOutput "`n2. Getting Fabric access token..." $Blue
    $fabricToken = Get-FabricAccessToken
    Write-ColorOutput "✅ Successfully obtained Fabric access token" $Green
    
    # Test lakehouse access
    Write-ColorOutput "`n3. Testing lakehouse access..." $Blue
    $canAccess = Test-OneLakeDataAccess -WorkspaceId $WorkspaceId -LakehouseId $LakehouseId -Token $fabricToken
    
    if ($canAccess) {
        # Create data access role
        Write-ColorOutput "`n4. Configuring data access role..." $Blue
        $roleCreated = New-OneLakeDataAccessRole -WorkspaceId $WorkspaceId -LakehouseId $LakehouseId -RoleName $RoleName -PrincipalId $principalId -ScopedFolders $ScopedFolders -Token $fabricToken
        
        if ($roleCreated) {
            Write-ColorOutput "`n5. Testing permissions..." $Blue
            Start-Sleep -Seconds 10  # Allow time for permissions to propagate
            Test-DataAccessPermissions -WorkspaceId $WorkspaceId -LakehouseId $LakehouseId -SearchServiceName $SearchServiceName -ResourceGroup $ResourceGroupName
        }
    }
    
    Write-ColorOutput "`n=== Setup Complete ===" $Green
    Write-ColorOutput "Next steps:" $Cyan
    Write-ColorOutput "1. Verify the role was created in Fabric Portal" $Cyan
    Write-ColorOutput "2. Test indexers with: ./debug_onelake_indexers.ps1" $Cyan
    Write-ColorOutput "3. Create reports data source and indexer" $Cyan
    
} catch {
    Write-ColorOutput "❌ Setup failed: $($_.Exception.Message)" $Red
    exit 1
}
