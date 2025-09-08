# Create OneLake data source for AI Search indexing
# This script creates the OneLake data source using the correct preview API

param(
    [string]$aiSearchName = "",
    [string]$resourceGroup = "",
    [string]$subscription = "",
    [string]$workspaceId = "",
    [string]$lakehouseId = "",
    [string]$dataSourceName = "onelake-reports-datasource",
    [string]$queryPath = "Files/documents/reports"
)

# Resolve parameters from environment
if (-not $aiSearchName) { $aiSearchName = $env:aiSearchName }
if (-not $aiSearchName) { $aiSearchName = $env:AZURE_AI_SEARCH_NAME }
if (-not $resourceGroup) { $resourceGroup = $env:aiSearchResourceGroup }
if (-not $resourceGroup) { $resourceGroup = $env:AZURE_RESOURCE_GROUP_NAME }
if (-not $subscription) { $subscription = $env:aiSearchSubscriptionId }
if (-not $subscription) { $subscription = $env:AZURE_SUBSCRIPTION_ID }

# Resolve Fabric workspace and lakehouse IDs
if (-not $workspaceId) { $workspaceId = $env:FABRIC_WORKSPACE_ID }
if (-not $lakehouseId) { $lakehouseId = $env:FABRIC_LAKEHOUSE_ID }

# Try /tmp/fabric_workspace.env (from create_fabric_workspace.ps1)
if ((-not $workspaceId -or -not $lakehouseId) -and (Test-Path '/tmp/fabric_workspace.env')) {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
        if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$' -and -not $workspaceId) { $workspaceId = $Matches[1] }
        if ($_ -match '^FABRIC_LAKEHOUSE_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
        # Also try lakehouse-specific IDs (bronze, silver, gold)
        if ($_ -match '^FABRIC_LAKEHOUSE_bronze_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
    }
}

# Try dedicated lakehouse file
if ((-not $workspaceId -or -not $lakehouseId) -and (Test-Path '/tmp/fabric_lakehouses.env')) {
    Get-Content '/tmp/fabric_lakehouses.env' | ForEach-Object {
        if ($_ -match '^FABRIC_LAKEHOUSE_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
        if ($_ -match '^FABRIC_LAKEHOUSE_bronze_ID=(.+)$' -and -not $lakehouseId) { $lakehouseId = $Matches[1] }
    }
}

Write-Host "Creating OneLake data source for AI Search service: $aiSearchName"
Write-Host "================================================================="

if (-not $aiSearchName -or -not $resourceGroup -or -not $subscription -or -not $workspaceId -or -not $lakehouseId) {
    Write-Error "Missing required environment variables. Please ensure AZURE_AI_SEARCH_NAME, AZURE_RESOURCE_GROUP_NAME, AZURE_SUBSCRIPTION_ID, FABRIC_WORKSPACE_ID, and FABRIC_LAKEHOUSE_ID are set."
    exit 1
}

Write-Host "Workspace ID: $workspaceId"
Write-Host "Lakehouse ID: $lakehouseId"
Write-Host "Query Path: $queryPath"
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

# Create OneLake data source with System-Assigned Managed Identity
Write-Host "Creating OneLake data source: $dataSourceName"

# Create the data source using the working format (connection string and identity both null)
Write-Host "Creating OneLake data source using working format..."

$dataSourceBody = @{
    name = $dataSourceName
    description = "OneLake data source for document indexing"
    type = "onelake"
    credentials = @{
        connectionString = $null
    }
    container = @{
        name = $lakehouseId
        query = $null
    }
    dataChangeDetectionPolicy = @{
        '@odata.type' = '#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy'
        highWaterMarkColumnName = 'metadata_storage_last_modified'
    }
} | ConvertTo-Json -Depth 10

Write-Host ""
Write-Host "OneLake data source created successfully!"
Write-Host ""
Write-Host "⚠️  IMPORTANT: Ensure the AI Search System-Assigned Managed Identity has:"
Write-Host "   1. OneLake data access role in the Fabric workspace"
Write-Host "   2. Storage Blob Data Reader role in Azure"
