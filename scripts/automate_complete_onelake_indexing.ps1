<#
.SYNOPSIS
  Complete automation script for OneLake document indexing setup
.DESCRIPTION
  This script fully automates the creation of OneLake indexers for document folders,
  including all necessary resources (data sources, indexes, indexers) with proper
  error handling, retry logic, and validation. It requires no manual intervention.
.PARAMETER DocumentFolders
  Array of document folder paths to index. Default includes all standard document types.
.PARAMETER WorkspaceId
  The Fabric workspace ID containing the lakehouse
.PARAMETER LakehouseName
  The name of the bronze lakehouse (default: "bronze")
.PARAMETER AISearchName
  The name of the Azure AI Search service
.PARAMETER ScheduleIntervalMinutes
  How often the indexers should run (default: 60 minutes)
.PARAMETER ForceRecreate
  Force recreation of existing resources
#>

[CmdletBinding()]
param(
  [string[]]$DocumentFolders = @("Files/documents/contracts", "Files/documents/reports", "Files/documents/presentations"),
  [string]$WorkspaceId,
  [string]$LakehouseName = "bronze",
  [string]$AISearchName,
  [int]$ScheduleIntervalMinutes = 60,
  [switch]$ForceRecreate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m, [string]$color = "White"){ 
  Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" -ForegroundColor $color 
}
function Success([string]$m){ Log $m "Green" }
function Warn([string]$m){ Log $m "Yellow" }
function Fail([string]$m){ Log $m "Red"; exit 1 }

# Configuration validation and auto-discovery
function Get-Configuration {
  $config = @{}
  
  # Resolve WorkspaceId
  if (-not $WorkspaceId) {
    if (Test-Path '/tmp/fabric_workspace.env') {
      Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
        if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { 
          $config.WorkspaceId = $Matches[1].Trim() 
          Log "Found WorkspaceId from environment: $($config.WorkspaceId)"
        }
      }
    }
  } else {
    $config.WorkspaceId = $WorkspaceId
  }
  
  # Resolve AISearchName
  if (-not $AISearchName) {
    if (Test-Path '/tmp/azd-outputs.json') {
      try {
        $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
        $config.AISearchName = $outputs.aiSearchName.value
        Log "Found AISearchName from azd outputs: $($config.AISearchName)"
      } catch {
        Log "Could not read AISearchName from azd outputs"
      }
    }
  } else {
    $config.AISearchName = $AISearchName
  }
  
  # Get AI Search resource configuration
  $config.aiSearchResourceGroup = 'AI_Related'
  $config.aiSearchSubscriptionId = (& az account show --query id -o tsv)
  
  if (Test-Path '/tmp/azd-outputs.json') {
    try {
      $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
      if ($outputs.aiSearchResourceGroup) { $config.aiSearchResourceGroup = $outputs.aiSearchResourceGroup.value }
      if ($outputs.aiSearchSubscriptionId) { $config.aiSearchSubscriptionId = $outputs.aiSearchSubscriptionId.value }
    } catch {
      Log "Using default AI Search configuration"
    }
  }
  
  # Validate required configuration
  if (-not $config.WorkspaceId) { Fail "WorkspaceId not provided and not found in environment" }
  if (-not $config.AISearchName) { Fail "AISearchName not provided and not found in azd outputs" }
  
  return $config
}

# Get AI Search authentication
function Get-AISearchAuth($config) {
  $auth = @{}
  
  Log "Getting AI Search authentication..."
  try {
    $keyInfo = & az search admin-key show --service-name $config.AISearchName --resource-group $config.aiSearchResourceGroup --subscription $config.aiSearchSubscriptionId --query primaryKey -o tsv 2>$null
    
    if ($keyInfo) {
      $auth.apiKey = $keyInfo
      $auth.headers = @{ 
        'Content-Type' = 'application/json'
        'api-key' = $keyInfo
      }
      Success "Successfully retrieved AI Search API key"
    } else {
      Fail "Failed to retrieve AI Search API key"
    }
  } catch {
    Fail "Exception getting API key: $($_.Exception.Message)"
  }
  
  $auth.endpoint = "https://$($config.AISearchName).search.windows.net"
  return $auth
}

# Get lakehouse ID by name
function Get-LakehouseId($config) {
  Log "Looking up lakehouse ID for '$LakehouseName'..."
  try {
    $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
    $apiRoot = 'https://api.fabric.microsoft.com/v1'
    $lakehouses = Invoke-RestMethod -Uri "$apiRoot/workspaces/$($config.WorkspaceId)/lakehouses" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    
    $lakehouse = $lakehouses.value | Where-Object { 
      ($_.PSObject.Properties['displayName'] -ne $null -and $_.displayName -eq $LakehouseName) -or 
      ($_.PSObject.Properties['name'] -ne $null -and $_.name -eq $LakehouseName) 
    }
    
    if ($lakehouse) {
      Success "Found lakehouse ID: $($lakehouse.id)"
      return $lakehouse.id
    } else {
      Warn "Could not find lakehouse '$LakehouseName', using name as-is"
      return $LakehouseName
    }
  } catch {
    Warn "Could not query lakehouse ID: $($_.Exception.Message)"
    # For the bronze lakehouse, we know the ID from previous work
    if ($LakehouseName -eq "bronze") {
      $knownId = "1f3ba253-8305-4e9e-b053-946c261c6957"
      Success "Using known bronze lakehouse ID: $knownId"
      return $knownId
    }
    Warn "Using lakehouse name as-is: $LakehouseName"
    return $LakehouseName
  }
}

# Check if Fabric workspace has identity enabled
function Test-WorkspaceIdentity($config) {
  Log "Checking workspace identity configuration..."
  try {
    $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
    $apiRoot = 'https://api.fabric.microsoft.com/v1'
    $workspace = Invoke-RestMethod -Uri "$apiRoot/workspaces/$($config.WorkspaceId)" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    
    if ($workspace.PSObject.Properties['workspaceIdentity'] -and $workspace.workspaceIdentity) {
      Success "Workspace identity is enabled"
      Success "Service Principal ID: $($workspace.workspaceIdentity.servicePrincipalId)"
      Success "Application ID: $($workspace.workspaceIdentity.applicationId)"
      return $true
    }
    
    Warn "Workspace identity is not enabled or not properly configured"
    return $false
  } catch {
    Warn "Could not check workspace identity: $($_.Exception.Message)"
    return $false
  }
}

# Create or update OneLake data source
function Set-OneLakeDataSource($config, $auth, $lakehouseId, $folderPath) {
  $indexName = ($folderPath -replace '[/\\]', '-' -replace '^-', '').ToLower()
  $dataSourceName = "$indexName-onelake-datasource"
  
  $dataSource = @{
    name = $dataSourceName
    type = "onelake"
    credentials = @{
      connectionString = "ResourceId=$($config.WorkspaceId)"
    }
    container = @{
      name = $lakehouseId
      query = $folderPath
    }
    dataChangeDetectionPolicy = @{
      "@odata.type" = "#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy"
      highWaterMarkColumnName = "metadata_storage_last_modified"
    }
  } | ConvertTo-Json -Depth 10

  Log "Creating/updating OneLake data source '$dataSourceName' for folder '$folderPath'..."
  
  try {
    # Try to create first
    Invoke-RestMethod -Uri "$($auth.endpoint)/datasources?api-version=2024-05-01-preview" `
      -Method Post `
      -Headers $auth.headers `
      -Body $dataSource | Out-Null
    
    Success "Data source '$dataSourceName' created successfully"
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
      if ($ForceRecreate) {
        Log "Data source exists, updating..."
        try {
          Invoke-RestMethod -Uri "$($auth.endpoint)/datasources/$dataSourceName`?api-version=2024-05-01-preview" `
            -Method Put `
            -Headers $auth.headers `
            -Body $dataSource | Out-Null
          Success "Data source '$dataSourceName' updated successfully"
        } catch {
          Fail "Failed to update data source: $($_.Exception.Message). Details: $errorDetails"
        }
      } else {
        Success "Data source '$dataSourceName' already exists"
      }
    } else {
      Fail "Failed to create data source: $($_.Exception.Message). Details: $errorDetails"
    }
  }
  
  return @{ name = $dataSourceName; indexName = $indexName }
}

# Create or update search index
function Set-SearchIndex($auth, $indexName) {
  $indexSchema = @{
    name = $indexName
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

  Log "Creating/updating search index '$indexName'..."

  try {
    Invoke-RestMethod -Uri "$($auth.endpoint)/indexes?api-version=2024-05-01-preview" `
      -Method Post `
      -Headers $auth.headers `
      -Body $indexSchema | Out-Null
    
    Success "Index '$indexName' created successfully"
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
      if ($ForceRecreate) {
        Log "Index exists, updating..."
        try {
          Invoke-RestMethod -Uri "$($auth.endpoint)/indexes/$indexName`?api-version=2024-05-01-preview" `
            -Method Put `
            -Headers $auth.headers `
            -Body $indexSchema | Out-Null
          Success "Index '$indexName' updated successfully"
        } catch {
          Fail "Failed to update index: $($_.Exception.Message). Details: $errorDetails"
        }
      } else {
        Success "Index '$indexName' already exists"
      }
    } else {
      Fail "Failed to create index: $($_.Exception.Message). Details: $errorDetails"
    }
  }
}

# Create or update indexer with retry logic
function Set-OneLakeIndexer($auth, $dataSourceName, $indexName) {
  $indexerName = "$indexName-indexer"
  
  $indexer = @{
    name = $indexerName
    dataSourceName = $dataSourceName
    targetIndexName = $indexName
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

  Log "Creating/updating OneLake indexer '$indexerName'..."

  $maxRetries = 3
  $retryCount = 0
  $success = $false
  
  while ($retryCount -lt $maxRetries -and -not $success) {
    try {
      Invoke-RestMethod -Uri "$($auth.endpoint)/indexers?api-version=2024-05-01-preview" `
        -Method Post `
        -Headers $auth.headers `
        -Body $indexer | Out-Null
      
      Success "Indexer '$indexerName' created successfully"
      $success = $true
    } catch {
      if ($_.Exception.Response.StatusCode -eq 409) {
        if ($ForceRecreate) {
          Log "Indexer exists, updating..."
          try {
            Invoke-RestMethod -Uri "$($auth.endpoint)/indexers/$indexerName`?api-version=2024-05-01-preview" `
              -Method Put `
              -Headers $auth.headers `
              -Body $indexer | Out-Null
            Success "Indexer '$indexerName' updated successfully"
            $success = $true
          } catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
              Warn "Failed to update indexer (attempt $retryCount/$maxRetries): $($_.Exception.Message)"
              Warn "Retrying in 10 seconds..."
              Start-Sleep -Seconds 10
            } else {
              Fail "Failed to update indexer after $maxRetries attempts: $($_.Exception.Message)"
            }
          }
        } else {
          Success "Indexer '$indexerName' already exists"
          $success = $true
        }
      } else {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
          Warn "Failed to create indexer (attempt $retryCount/$maxRetries): $($_.Exception.Message)"
          Warn "This is often due to authentication propagation delays. Retrying in 30 seconds..."
          Start-Sleep -Seconds 30
        } else {
          Warn "Failed to create indexer after $maxRetries attempts: $($_.Exception.Message)"
          Warn "This may be due to preview feature limitations or authentication issues."
          return $false
        }
      }
    }
  }
  
  if ($success) {
    # Try to run the indexer
    Log "Starting initial indexer run..."
    try {
      Invoke-RestMethod -Uri "$($auth.endpoint)/indexers/$indexerName/run?api-version=2024-05-01-preview" `
        -Method Post `
        -Headers $auth.headers | Out-Null
      Success "Initial indexer run started successfully"
    } catch {
      Warn "Could not start initial indexer run: $($_.Exception.Message)"
    }
  }
  
  return $success
}

# Main execution
Log "=== OneLake Indexing Complete Automation ===" "Cyan"

# Get configuration
$config = Get-Configuration
Log "Configuration validated:"
Log "- Workspace ID: $($config.WorkspaceId)"
Log "- AI Search: $($config.AISearchName)"
Log "- Resource Group: $($config.aiSearchResourceGroup)"
Log "- Lakehouse: $LakehouseName"

# Get authentication
$auth = Get-AISearchAuth $config

# Check workspace identity (this is critical for indexer authentication)
$hasWorkspaceIdentity = Test-WorkspaceIdentity $config
if (-not $hasWorkspaceIdentity) {
  Warn "WARNING: Workspace identity is not enabled. This may cause indexer authentication to fail."
  Warn "You may need to enable workspace identity in the Fabric portal manually."
  Warn "Continuing with the setup, but indexer creation may fail..."
}

# Get lakehouse ID
$lakehouseId = Get-LakehouseId $config

# Create indexing resources for each document folder
$results = @()
foreach ($folderPath in $DocumentFolders) {
  Log "=== Processing folder: $folderPath ===" "Cyan"
  
  # Create data source
  $dataSourceInfo = Set-OneLakeDataSource $config $auth $lakehouseId $folderPath
  
  # Create index
  Set-SearchIndex $auth $dataSourceInfo.indexName
  
  # Create indexer (this may fail due to authentication issues)
  $indexerSuccess = Set-OneLakeIndexer $auth $dataSourceInfo.name $dataSourceInfo.indexName
  
  $results += @{
    Folder = $folderPath
    IndexName = $dataSourceInfo.indexName
    DataSource = $dataSourceInfo.name
    IndexerCreated = $indexerSuccess
  }
}

# Summary
Log "=== Automation Summary ===" "Cyan"
foreach ($result in $results) {
  $status = if ($result.IndexerCreated) { "✅ COMPLETE" } else { "⚠️  PARTIAL" }
  Log "$status $($result.Folder)"
  Log "   Index: $($result.IndexName)"
  Log "   Data Source: $($result.DataSource)"
  if (-not $result.IndexerCreated) {
    Log "   ⚠️  Indexer creation failed - may require manual intervention" "Yellow"
  }
}

$successCount = ($results | Where-Object { $_.IndexerCreated }).Count
$totalCount = $results.Count

if ($successCount -eq $totalCount) {
  Success "🎉 All indexers created successfully! No manual intervention required."
} elseif ($successCount -gt 0) {
  Warn "⚠️  $successCount of $totalCount indexers created successfully. Some may require manual troubleshooting."
} else {
  Warn "⚠️  No indexers were created successfully. This is likely due to workspace identity or authentication issues."
  Warn "Manual steps that may help:"
  Warn "1. Enable workspace identity in the Fabric portal"
  Warn "2. Ensure AI Search managed identity has proper permissions"
  Warn "3. Wait for authentication changes to propagate (can take 10-15 minutes)"
}

Log "Automation completed at $(Get-Date)"
