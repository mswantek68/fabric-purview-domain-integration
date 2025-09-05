<#
.SYNOPSIS
  Create an Azure AI Search OneLake indexer for a specific folder in the bronze lakehouse
.DESCRIPTION
  This script creates an AI Search data source, index, and indexer using t# Build the OneLake data source JSON
# For OneLake data sources, ResourceId should be just the workspace ID
$dataSource = @{
  name = $dataSourceName
  type = "onelake"
  credentials = @{
    connectionString = "ResourceId=$script:WorkspaceId"
  }
  container = @{
    name = $lakehouseId
    query = $FolderPath
  }
  dataChangeDetectionPolicy = @{
    "@odata.type" = "#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy"
    highWaterMarkColumnName = "_ts"
  }
} | ConvertTo-Json -Depth 10ctor
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

# Get AI Search configuration from azd outputs if not provided
$aiSearchResourceGroup = 'AI_Related'  # Default from main.bicep
$aiSearchSubscriptionId = '48ab3756-f962-40a8-b0cf-b33ddae744bb'  # Default from main.bicep

if (Test-Path '/tmp/azd-outputs.json') {
  try {
    $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
    if ($outputs.aiSearchResourceGroup) { $aiSearchResourceGroup = $outputs.aiSearchResourceGroup.value }
    if ($outputs.aiSearchSubscriptionId) { $aiSearchSubscriptionId = $outputs.aiSearchSubscriptionId.value }
    Log "Using AI Search config from azd outputs: RG=$aiSearchResourceGroup, Sub=$aiSearchSubscriptionId"
  } catch {
    Log "Using default AI Search config: RG=$aiSearchResourceGroup, Sub=$aiSearchSubscriptionId"
  }
} else {
  Log "No azd outputs found, using default AI Search config: RG=$aiSearchResourceGroup, Sub=$aiSearchSubscriptionId"
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

# Get access token for AI Search using managed identity, or fall back to API key
$searchToken = $null
$searchApiKey = $null

# Force API key authentication for now (many AI Search services default to API key auth)
# try {
#   $searchToken = & az account get-access-token --resource https://search.azure.com --query accessToken -o tsv
#   if (-not $searchToken) { 
#     Log "Could not retrieve AI Search access token, trying API key authentication..."
#     $searchToken = $null
#   }
# } catch {
#   Log "Failed to get AI Search access token, trying API key authentication..."
#   $searchToken = $null
# }

# Get API key for authentication
Log "Attempting to get AI Search API key..."
try {
  if ($aiSearchResourceGroup -and $aiSearchSubscriptionId) {
    Log "Using resource group: $aiSearchResourceGroup, subscription: $aiSearchSubscriptionId"
    $keyInfo = & az search admin-key show --service-name $AISearchName --resource-group $aiSearchResourceGroup --subscription $aiSearchSubscriptionId --query primaryKey -o tsv 2>$null
  } else {
    Log "No resource group/subscription specified, using default context"
    $keyInfo = & az search admin-key show --service-name $AISearchName --query primaryKey -o tsv 2>$null
  }
  
  if ($keyInfo) {
    $searchApiKey = $keyInfo
    Log "Successfully retrieved AI Search API key"
  } else {
    Log "Failed to retrieve API key"
  }
} catch {
  Log "Exception getting API key: $($_.Exception.Message)"
}

if (-not $searchToken -and -not $searchApiKey) {
  Fail "Could not authenticate with AI Search using either token or API key. Ensure you have permissions or the service exists."
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

# Get the actual lakehouse ID by querying the workspace
Log "Looking up lakehouse ID for '$LakehouseName'..."
try {
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
  $apiRoot = 'https://api.fabric.microsoft.com/v1'
  $lakehouses = Invoke-RestMethod -Uri "$apiRoot/workspaces/$script:WorkspaceId/lakehouses" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  
  $lakehouse = $lakehouses.value | Where-Object { 
    ($_.PSObject.Properties['displayName'] -ne $null -and $_.displayName -eq $LakehouseName) -or 
    ($_.PSObject.Properties['name'] -ne $null -and $_.name -eq $LakehouseName) 
  }
  
  if ($lakehouse) {
    $lakehouseId = $lakehouse.id
    Log "Found lakehouse ID: $lakehouseId"
  } else {
    Log "Could not find lakehouse '$LakehouseName', using name as-is"
    $lakehouseId = $LakehouseName
  }
} catch {
  Log "Could not query lakehouse ID, using name as-is: $($_.Exception.Message)"
  $lakehouseId = $LakehouseName
}

# Create OneLake data source
$dataSourceName = "$IndexName-onelake-datasource"
$dataSource = @{
  name = $dataSourceName
  type = "onelake"
  credentials = @{
    connectionString = "ResourceId=$script:WorkspaceId"
  }
  container = @{
    name = $lakehouseId
    query = $FolderPath
  }
  dataChangeDetectionPolicy = @{
    "@odata.type" = "#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy"
    highWaterMarkColumnName = "metadata_storage_last_modified"
  }
} | ConvertTo-Json -Depth 10

# Build headers for API calls
$headers = @{ 'Content-Type' = 'application/json' }
if ($searchToken) {
  $headers['Authorization'] = "Bearer $searchToken"
  Log "Using Bearer token authentication"
} elseif ($searchApiKey) {
  $headers['api-key'] = $searchApiKey
  Log "Using API key authentication"
} else {
  Fail "No authentication method available"
}

Log "Creating OneLake data source '$dataSourceName'..."
Log "Request body: $dataSource"

try {
  Invoke-RestMethod -Uri "$searchEndpoint/datasources?api-version=2024-05-01-preview" `
    -Method Post `
    -Headers $headers `
    -Body $dataSource | Out-Null
  
  Log "Data source created successfully"
} catch {
  $errorDetails = ""
  if ($_.Exception.Response) {
    try {
      $errorStream = $_.Exception.Response.GetResponseStream()
      $reader = New-Object System.IO.StreamReader($errorStream)
      $errorDetails = $reader.ReadToEnd()
      $reader.Close()
    } catch {
      $errorDetails = "Could not read error details"
    }
  }
  
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Data source '$dataSourceName' already exists, updating..."
    try {
      Invoke-RestMethod -Uri "$searchEndpoint/datasources/$dataSourceName`?api-version=2024-05-01-preview" `
        -Method Put `
        -Headers $headers `
        -Body $dataSource | Out-Null
      Log "Data source updated successfully"
    } catch {
      Fail ("Failed to update data source: " + $_.Exception.Message)
    }
  } else {
    Fail ("Failed to create data source: " + $_.Exception.Message + ". Details: " + $errorDetails)
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
  Invoke-RestMethod -Uri "$searchEndpoint/indexes?api-version=2024-05-01-preview" `
    -Method Post `
    -Headers $headers `
    -Body $indexSchema | Out-Null
  
  Log "Index created successfully"
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Index '$IndexName' already exists, updating if needed..."
    try {
      Invoke-RestMethod -Uri "$searchEndpoint/indexes/$IndexName`?api-version=2024-05-01-preview" `
        -Method Put `
        -Headers $headers `
        -Body $indexSchema | Out-Null
      Log "Index updated successfully"
    } catch {
      Fail ("Failed to update index: " + $_.Exception.Message)
    }
  } else {
    Fail ("Failed to create index: " + $_.Exception.Message)
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
  Invoke-RestMethod -Uri "$searchEndpoint/indexers?api-version=2024-05-01-preview" `
    -Method Post `
    -Headers $headers `
    -Body $indexer | Out-Null
  
  Log "Indexer created successfully"
  Log "Indexer will run every $ScheduleIntervalMinutes minutes"
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Indexer '$indexerName' already exists, updating..."
    try {
      Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName`?api-version=2024-05-01-preview" `
        -Method Put `
        -Headers $headers `
        -Body $indexer | Out-Null
      Log "Indexer updated successfully"
    } catch {
      Fail ("Failed to update indexer: " + $_.Exception.Message)
    }
  } else {
    Fail ("Failed to create indexer: " + $_.Exception.Message)
  }
}

# Run the indexer once to start initial indexing
Log "Starting initial indexer run..."
try {
  $runHeaders = @{}
  if ($searchToken) {
    $runHeaders['Authorization'] = "Bearer $searchToken"
  } elseif ($searchApiKey) {
    $runHeaders['api-key'] = $searchApiKey
  }
  
  Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName/run?api-version=2024-05-01-preview" `
    -Method Post `
    -Headers $runHeaders | Out-Null
  Log "Initial indexer run started successfully"
} catch {
  Warn ("Could not start initial indexer run: " + $_.Exception.Message)
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
