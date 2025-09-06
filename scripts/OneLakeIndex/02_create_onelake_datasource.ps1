# Create OneLake data source for AI Search indexing
# This script creates the OneLake data source using the correct preview API

param(
    [string]$aiSearchName = $env:AZURE_AI_SEARCH_NAME,
    [string]$resourceGroup = $env:AZURE_RESOURCE_GROUP_NAME,
    [string]$subscription = $env:AZURE_SUBSCRIPTION_ID,
    [string]$workspaceId = $env:FABRIC_WORKSPACE_ID,
    [string]$lakehouseId = $env:FABRIC_LAKEHOUSE_ID,
    [string]$dataSourceName = "onelake-reports-datasource",
    [string]$queryPath = "Files/documents/reports"
)

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

$dataSourceBody = @{
    name = $dataSourceName
    description = "OneLake data source for document indexing"
    type = "onelake"
    credentials = @{
        connectionString = "ResourceId=$workspaceId"
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

# Delete existing data source if present
try {
    $deleteUrl = "https://$aiSearchName.search.windows.net/datasources/$dataSourceName?api-version=$apiVersion"
    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE
    Write-Host "Deleted existing data source"
} catch {
    Write-Host "No existing data source to delete"
}

# Create data source
$createUrl = "https://$aiSearchName.search.windows.net/datasources?api-version=$apiVersion"

try {
    $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $dataSourceBody
    Write-Host "✅ Successfully created OneLake data source: $($response.name)"
    Write-Host "Data source type: $($response.type)"
    Write-Host "Container: $($response.container.name)"
    Write-Host "Query path: $($response.container.query)"
} catch {
    Write-Error "Failed to create OneLake data source: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "OneLake data source created successfully!"
Write-Host ""
Write-Host "⚠️  IMPORTANT: Ensure the AI Search System-Assigned Managed Identity has:"
Write-Host "   1. OneLake data access role in the Fabric workspace"
Write-Host "   2. Storage Blob Data Reader role in Azure"
