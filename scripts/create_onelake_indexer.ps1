<#
.SYNOPSIS
  Create an Azure AI Search OneLake indexer for a specific folder in the bronze lakehouse
.DESCRIPTION
  This script creates an AI Search data source, index, and indexer using the OneLake connector
  to automatically index documents in a Fabric OneLake folder. This is the recommended approach
  for indexing documents stored in Fabric OneLake.
.PARAMETER FolderPath
  The path within the bronze lakehouse to index. Standard paths:
  - "Files/documents/contracts" - For contract documents
  - "Files/documents/reports" - For business reports  
  - "Files/documents/policies" - For policy documents
  - "Files/documents/manuals" - For user guides and manuals
.PARAMETER IndexName
  Optional custom index name. If not provided, will be generated from folder path
.PARAMETER AISearchName
  The name of the Azure AI Search service
.PARAMETER WorkspaceId
  The Fabric workspace ID containing the lakehouse
.PARAMETER LakehouseName
  The name of the bronze lakehouse (default: "bronze")
.PARAMETER ScheduleIntervalMinutes
  How often the indexer should run (default: 60 minutes)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$FolderPath,
  
  [string]$IndexName,
  [string]$AISearchName,
  [string]$WorkspaceId,
  [string]$LakehouseName = "bronze",
  [int]$ScheduleIntervalMinutes = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[onelake-indexer] $m" }
function Warn([string]$m){ Write-Warning "[onelake-indexer] $m" }
function Fail([string]$m){ Write-Error "[onelake-indexer] $m"; exit 1 }

# Resolve parameters from environment or bicep outputs
if (-not $WorkspaceId) {
  if (Test-Path '/tmp/fabric_workspace.env') {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $script:WorkspaceId = $Matches[1].Trim() }
    }
  }
}

if (-not $AISearchName) {
  if (Test-Path '/tmp/azd-outputs.json') {
    $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
    $AISearchName = $outputs.aiSearchName.value
  }
}

# Get lakehouse configuration from bicep outputs if not provided
if (-not $LakehouseName -or $LakehouseName -eq "bronze") {
  if (Test-Path '/tmp/azd-outputs.json') {
    try {
      $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
      $LakehouseName = $outputs.documentLakehouseName.value
      Log "Using document lakehouse from bicep outputs: $LakehouseName"
    } catch {
      Log "Could not read document lakehouse name from azd outputs, using: $LakehouseName"
    }
  }
}

if (-not $script:WorkspaceId) { Fail "WorkspaceId not provided and not found in environment" }
if (-not $AISearchName) { Fail "AISearchName not provided and not found in azd outputs" }

# Generate index name if not provided
if (-not $IndexName) {
  $IndexName = ($FolderPath -replace '[/\\]', '-' -replace '^-', '').ToLower()
  if (-not $IndexName) { $IndexName = "default-index" }
}

Log "Creating OneLake indexer for folder: $FolderPath"
Log "Index name: $IndexName"
Log "AI Search service: $AISearchName"
Log "Workspace ID: $script:WorkspaceId"

# Get access token for AI Search using managed identity
try {
  $searchToken = & az account get-access-token --resource https://search.azure.com --query accessToken -o tsv
  if (-not $searchToken) { Fail "Could not retrieve AI Search access token" }
} catch {
  Fail "Failed to get AI Search access token: $_"
}

# Get current subscription and resource group
$subscriptionId = (& az account show --query id -o tsv)
$resourceGroup = $env:AZURE_RESOURCE_GROUP
if (-not $resourceGroup) {
  $resourceGroup = (& az group list --query "[?contains(name, 'rg-')].name" -o tsv | Select-Object -First 1)
}

if (-not $subscriptionId -or -not $resourceGroup) {
  Fail "Could not determine subscription ID or resource group. Ensure 'az login' is completed."
}

# Determine search endpoint (support custom endpoints for private links)
$searchEndpoint = if ($env:AI_SEARCH_CUSTOM_ENDPOINT -and $env:AI_SEARCH_CUSTOM_ENDPOINT -ne "") { 
  $env:AI_SEARCH_CUSTOM_ENDPOINT.TrimEnd('/')
} else { 
  "https://$AISearchName.search.windows.net" 
}

Log "Search endpoint: $searchEndpoint"

# Create OneLake data source
$dataSourceName = "$IndexName-onelake-datasource"
$dataSource = @{
  name = $dataSourceName
  type = "onelake"
  credentials = @{
    connectionString = "ResourceId=/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Fabric/workspaces/$script:WorkspaceId/lakehouses/$LakehouseName;"
  }
  container = @{
    name = "Files"
    query = $FolderPath
  }
  dataChangeDetectionPolicy = @{
    "@odata.type" = "#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy"
    highWaterMarkColumnName = "_ts"
  }
} | ConvertTo-Json -Depth 10

Log "Creating OneLake data source '$dataSourceName'..."

try {
  $response = Invoke-RestMethod -Uri "$searchEndpoint/datasources?api-version=2023-11-01" `
    -Method Post `
    -Headers @{
      'Content-Type' = 'application/json'
      'Authorization' = "Bearer $searchToken"
    } `
    -Body $dataSource
  
  Log "Data source created successfully"
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Data source '$dataSourceName' already exists, updating..."
    try {
      $updateResponse = Invoke-RestMethod -Uri "$searchEndpoint/datasources/$dataSourceName`?api-version=2023-11-01" `
        -Method Put `
        -Headers @{
          'Content-Type' = 'application/json'
          'Authorization' = "Bearer $searchToken"
        } `
        -Body $dataSource
      Log "Data source updated successfully"
    } catch {
      Fail "Failed to update data source: $($_.Exception.Message)"
    }
  } else {
    Fail "Failed to create data source: $($_.Exception.Message)"
  }
}

# Create search index optimized for OneLake documents
$indexSchema = @{
  name = $IndexName
  fields = @(
    @{
      name = "content"
      type = "Edm.String"
      filterable = $false
      sortable = $false
      facetable = $false
      searchable = $true
      analyzer = "standard.lucene"
    }
    @{
      name = "metadata_storage_path"
      type = "Edm.String"
      filterable = $true
      sortable = $true
      facetable = $false
      searchable = $false
      key = $true
    }
    @{
      name = "metadata_storage_name"
      type = "Edm.String"
      filterable = $true
      sortable = $true
      facetable = $true
      searchable = $true
    }
    @{
      name = "metadata_storage_size"
      type = "Edm.Int64"
      filterable = $true
      sortable = $true
      facetable = $true
      searchable = $false
    }
    @{
      name = "metadata_storage_last_modified"
      type = "Edm.DateTimeOffset"
      filterable = $true
      sortable = $true
      facetable = $true
      searchable = $false
    }
    @{
      name = "metadata_content_type"
      type = "Edm.String"
      filterable = $true
      sortable = $false
      facetable = $true
      searchable = $false
    }
  )
} | ConvertTo-Json -Depth 10

Log "Creating search index '$IndexName'..."

try {
  $response = Invoke-RestMethod -Uri "$searchEndpoint/indexes?api-version=2023-11-01" `
    -Method Post `
    -Headers @{
      'Content-Type' = 'application/json'
      'Authorization' = "Bearer $searchToken"
    } `
    -Body $indexSchema
  
  Log "Index created successfully"
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Index '$IndexName' already exists, updating if needed..."
    try {
      $updateResponse = Invoke-RestMethod -Uri "$searchEndpoint/indexes/$IndexName`?api-version=2023-11-01" `
        -Method Put `
        -Headers @{
          'Content-Type' = 'application/json'
          'Authorization' = "Bearer $searchToken"
        } `
        -Body $indexSchema
      Log "Index updated successfully"
    } catch {
      Fail "Failed to update index: $($_.Exception.Message)"
    }
  } else {
    Fail "Failed to create index: $($_.Exception.Message)"
  }
}

# Create OneLake indexer
$indexerName = "$IndexName-indexer"
$indexer = @{
  name = $indexerName
  dataSourceName = $dataSourceName
  targetIndexName = $IndexName
  schedule = @{
    interval = "PT$($ScheduleIntervalMinutes)M"
  }
  parameters = @{
    batchSize = 100
    maxFailedItems = 0
    maxFailedItemsPerBatch = 0
    configuration = @{
      indexedFileNameExtensions = ".pdf,.docx,.pptx,.xlsx,.txt,.html,.json"
      excludedFileNameExtensions = ".tmp,.temp"
      dataToExtract = "contentAndMetadata"
      parsingMode = "default"
    }
  }
} | ConvertTo-Json -Depth 10

Log "Creating OneLake indexer '$indexerName' with $ScheduleIntervalMinutes minute schedule..."

try {
  $response = Invoke-RestMethod -Uri "$searchEndpoint/indexers?api-version=2023-11-01" `
    -Method Post `
    -Headers @{
      'Content-Type' = 'application/json'
      'Authorization' = "Bearer $searchToken"
    } `
    -Body $indexer
  
  Log "Indexer created successfully"
  Log "Indexer will run every $ScheduleIntervalMinutes minutes"
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Indexer '$indexerName' already exists, updating..."
    try {
      $updateResponse = Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName`?api-version=2023-11-01" `
        -Method Put `
        -Headers @{
          'Content-Type' = 'application/json'
          'Authorization' = "Bearer $searchToken"
        } `
        -Body $indexer
      Log "Indexer updated successfully"
    } catch {
      Fail "Failed to update indexer: $($_.Exception.Message)"
    }
  } else {
    Fail "Failed to create indexer: $($_.Exception.Message)"
  }
}

# Run the indexer once to start initial indexing
Log "Starting initial indexer run..."
try {
  $runResponse = Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName/run?api-version=2023-11-01" `
    -Method Post `
    -Headers @{
      'Authorization' = "Bearer $searchToken"
    }
  Log "Initial indexer run started successfully"
} catch {
  Warn "Could not start initial indexer run: $($_.Exception.Message)"
}

Log "OneLake indexer setup completed successfully!"
Log "Data source: $dataSourceName"
Log "Index: $IndexName" 
Log "Indexer: $indexerName"
Log "Schedule: Every $ScheduleIntervalMinutes minutes"
Log ""
Log "The indexer will automatically:"
Log "- Monitor the OneLake folder: $FolderPath"
Log "- Detect new and modified documents"
Log "- Extract text content and metadata"
Log "- Index documents for search"
