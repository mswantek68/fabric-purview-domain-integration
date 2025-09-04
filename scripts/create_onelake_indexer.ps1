<#
.SYNOPSIS
  Create an Azure AI Search OneLake indexer for a specific folder in the bronze lakehouse
.DESCRIPTION
  This script creates an AI Search data source, index, and indexer using the OneLake connector
  to automatically index documents in a Fabric OneLake folder.
.PARAMETER FolderPath
  The path within the lakehouse to index, e.g. "Files/documents/manuals"
.PARAMETER IndexName
  Optional custom index name. If not provided, will be generated from folder path
.PARAMETER AISearchName
  The name of the Azure AI Search service
.PARAMETER WorkspaceId
  The Fabric workspace ID containing the lakehouse (GUID)
.PARAMETER LakehouseName
  The name of the lakehouse (default: "bronze")
.PARAMETER ScheduleIntervalMinutes
  How often the indexer should run (default: 60 minutes)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string]$FolderPath,
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

# Resolve parameters from environment or azd outputs
if (-not $WorkspaceId) {
  if (Test-Path '/tmp/fabric_workspace.env') {
    Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
      if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $script:WorkspaceId = $Matches[1].Trim() }
    }
  }
}
if (-not $AISearchName) {
  if (Test-Path '/tmp/azd-outputs.json') {
    try { $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json; $AISearchName = $outputs.aiSearchName.value } catch {}
  }
}
if (-not $LakehouseName -or $LakehouseName -eq 'bronze') {
  if (Test-Path '/tmp/azd-outputs.json') {
    try { $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json; if ($outputs.documentLakehouseName.value) { $LakehouseName = $outputs.documentLakehouseName.value; Log "Using document lakehouse from bicep outputs: $LakehouseName" } } catch {}
  }
}

if (-not $script:WorkspaceId) { Fail "WorkspaceId not provided and not found in environment" }
if (-not $AISearchName) { Fail "AISearchName not provided and not found in azd outputs" }

# Generate index name if not provided
if (-not $IndexName) {
  $IndexName = ($FolderPath -replace '[/\\]', '-' -replace '^-', '').ToLower()
  if (-not $IndexName) { $IndexName = 'default-index' }
}

Log "Creating OneLake indexer for folder: $FolderPath"
Log "Index name: $IndexName"
Log "AI Search service: $AISearchName"
Log "Workspace ID: $script:WorkspaceId"

# Resolve Lakehouse ID (container.name must be the Lakehouse ID GUID per docs)
if ($LakehouseName -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
  $lakehouseId = $LakehouseName
} else {
  try {
    $fabricToken = & az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
    if (-not $fabricToken) { Fail 'Could not retrieve Fabric access token' }
    $fabricHeaders = @{ 'Authorization' = "Bearer $fabricToken"; 'Content-Type' = 'application/json' }
    $lhResp = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$script:WorkspaceId/lakehouses" -Headers $fabricHeaders -Method Get
    $lakehouse = $lhResp.value | Where-Object { $_.displayName -ieq $LakehouseName } | Select-Object -First 1
    if (-not $lakehouse) { Fail "Lakehouse '$LakehouseName' not found in workspace $script:WorkspaceId" }
    $lakehouseId = $lakehouse.id
  } catch { Fail "Failed to resolve lakehouse ID: $($_.Exception.Message)" }
}

# Resolve subscription and resource group holding the Fabric workspace
$subscriptionId = $null; $resourceGroup = $null
try {
  $fwJson = & az resource list --resource-type Microsoft.Fabric/workspaces -o json 2>$null
  if ($fwJson -and $fwJson -ne '[]') {
    $fwList = $fwJson | ConvertFrom-Json
    $fw = $fwList | Where-Object { $_.name -ieq $script:WorkspaceId -or $_.id -match [Regex]::Escape($script:WorkspaceId) } | Select-Object -First 1
    if ($fw) { $subscriptionId = ($fw.id -split '/')[2]; $resourceGroup = $fw.resourceGroup }
  }
} catch {}
if (-not $subscriptionId -or -not $resourceGroup) {
  try { $envText = & azd env get-values 2>$null; if ($envText) { foreach ($line in ($envText -split "`n")) { if (-not $subscriptionId -and $line -match '^AZURE_SUBSCRIPTION_ID=(.+)$') { $subscriptionId = $Matches[1].Trim() }; if (-not $resourceGroup -and $line -match '^AZURE_RESOURCE_GROUP=(.+)$') { $resourceGroup = $Matches[1].Trim() } } } } catch {}
}
if (-not $subscriptionId) { try { $subscriptionId = (& az account show --query id -o tsv) } catch {} }
if (-not $resourceGroup) { try { $resourceGroup = (& az group list -o tsv --query "[0].name") } catch {} }
if ($subscriptionId) { $subscriptionId = $subscriptionId.Trim().Trim('"') }
if ($resourceGroup) { $resourceGroup = $resourceGroup.Trim().Trim('"') }
if (-not $subscriptionId -or -not $resourceGroup) { Fail 'Could not determine subscription/resource group for Fabric workspace' }

# Determine search endpoint and authentication
$searchEndpoint = if ($env:AI_SEARCH_CUSTOM_ENDPOINT -and $env:AI_SEARCH_CUSTOM_ENDPOINT -ne '') { $env:AI_SEARCH_CUSTOM_ENDPOINT.TrimEnd('/') } else { "https://$AISearchName.search.windows.net" }
Log "Search endpoint: $searchEndpoint"

try {
  $searchResJson = & az resource list --resource-type Microsoft.Search/searchServices --name $AISearchName -o json --query "[0]"
  if (-not $searchResJson -or $searchResJson -eq 'null') { Fail "AI Search service '$AISearchName' not found in current context" }
  $searchRes = $searchResJson | ConvertFrom-Json
  $searchRg = $searchRes.resourceGroup
  $disableLocalAuth = & az search service show --resource-group $searchRg --name $AISearchName --query disableLocalAuth -o tsv
  $adminKey = $null
  if ($disableLocalAuth -ne 'true') { $adminKey = & az search admin-key show --resource-group $searchRg --service-name $AISearchName --query primaryKey -o tsv }
  $identityType = & az search service show --resource-group $searchRg --name $AISearchName --query identity.type -o tsv 2>$null
  if (-not $identityType -or $identityType -eq 'None') {
    Log 'Enabling system-assigned managed identity on AI Search service...'
    & az search service update --resource-group $searchRg --name $AISearchName --assign-identity system | Out-Null
    Start-Sleep -Seconds 3
  }
  $aadToken = $null; try { $aadToken = & az account get-access-token --resource https://search.azure.com --query accessToken -o tsv } catch {}
  if (-not $adminKey -and -not $aadToken) { Fail 'Could not acquire either admin key or AAD token for AI Search' }
  $activeHeaders = if ($adminKey) { @{ 'Content-Type' = 'application/json'; 'api-key' = $adminKey } } else { @{ 'Content-Type' = 'application/json'; 'Authorization' = "Bearer $aadToken" } }
} catch { Fail "Failed to prepare AI Search auth: $($_.Exception.Message)" }

# Create OneLake data source
$dataSourceName = "$IndexName-onelake-datasource"
$workspaceArmId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Fabric/workspaces/$($script:WorkspaceId)"
$tenantId = $null; try { $tenantId = & az account show --query tenantId -o tsv 2>$null } catch {}
Log "Using Fabric workspace ARM ResourceId: $workspaceArmId"
if ($tenantId) { Log "TenantId: $tenantId" }

$connAttempts = @()
$connAttempts += "WorkspaceId=$($script:WorkspaceId);OneLakeEndpoint=https://onelake.dfs.fabric.microsoft.com" + ($(if($tenantId){";TenantId=$tenantId"} else {""}))
$connAttempts += "ResourceId=/workspaces/$($script:WorkspaceId);OneLakeEndpoint=https://onelake.dfs.fabric.microsoft.com" + ($(if($tenantId){";TenantId=$tenantId"} else {""}))
$connAttempts += "ResourceId=$workspaceArmId" + ($(if($tenantId){";TenantId=$tenantId"} else {""}))
$connAttempts += "ResourceId=$workspaceArmId;OneLakeEndpoint=https://onelake.dfs.fabric.microsoft.com" + ($(if($tenantId){";TenantId=$tenantId"} else {""}))

$createdDs = $false
$attemptErrors = @()
foreach ($conn in $connAttempts) {
  foreach ($withIdentity in @($false,$true)) {
    $dataSourceHash = [ordered]@{
      name = $dataSourceName
      type = 'onelake'
      credentials = @{ connectionString = $conn }
      container = @{ name = $lakehouseId; query = "$FolderPath" }
    }
    if ($withIdentity) { $dataSourceHash.identity = @{ type = 'SystemAssigned' } }
    $dataSource = $dataSourceHash | ConvertTo-Json -Depth 10
    $idFlag = if ($withIdentity) { 'w/identity' } else { 'no-identity' }
    Log "Creating OneLake data source '$dataSourceName' variant: $idFlag connectionString: $conn"
    try {
      Invoke-RestMethod -Uri "$searchEndpoint/datasources?api-version=2024-05-01-preview" -Method Post -Headers $activeHeaders -Body $dataSource | Out-Null
      Log 'Data source created successfully'
      $createdDs = $true
      break
    } catch {
      $code = $null; $body = $null
      try { $code = [int]$_.Exception.Response.StatusCode; $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $body = $sr.ReadToEnd() } catch {}
      $summary = "HTTP $code | variant=$idFlag | msg=$body"
      $attemptErrors += $summary
      Warn "Create failed. $summary"
      # continue inner loop
    }
  }
  if ($createdDs) { break }
}

if (-not $createdDs) {
  Log 'All connection string variants failed.'
  $attemptErrors | ForEach-Object { Warn $_ }
  $tempFile = "/tmp/datasource_last_attempt.json"
  $dataSource | Out-File -FilePath $tempFile -Encoding UTF8
  $curlResult = if ($activeHeaders['api-key']) { & curl -s -X POST "$searchEndpoint/datasources?api-version=2024-05-01-preview" -H "Content-Type: application/json" -H "api-key: $($activeHeaders['api-key'])" -d "@$tempFile" 2>&1 } else { & curl -s -X POST "$searchEndpoint/datasources?api-version=2024-05-01-preview" -H "Content-Type: application/json" -H "Authorization: $($activeHeaders['Authorization'])" -d "@$tempFile" 2>&1 }
  Warn "Final curl response: $curlResult"

  $gating = $false
  if ($attemptErrors -match 'DataIdentity' -or $attemptErrors -match 'abstract class' -or $curlResult -match 'DataIdentity') { $gating = $true }

  if ($gating) {
    Warn 'Detected pattern indicating OneLake connector feature not enabled for this Search service.'
    '/tmp/onelake_connector_unsupported.flag' | Out-File -FilePath '/tmp/onelake_connector_unsupported.flag'
    Warn 'Skipping OneLake indexer creation gracefully (no failure). Fallback ingestion can be used.'
    return
  }

  Fail 'Failed to create OneLake data source after exhaustive attempts'
}

# Create search index
$indexSchema = @{
  name = $IndexName
  fields = @(
    @{ name = 'content'; type = 'Edm.String'; filterable = $false; sortable = $false; facetable = $false; searchable = $true; analyzer = 'standard.lucene' }
    @{ name = 'metadata_storage_path'; type = 'Edm.String'; filterable = $true; sortable = $true; facetable = $false; searchable = $false; key = $true }
    @{ name = 'metadata_storage_name'; type = 'Edm.String'; filterable = $true; sortable = $true; facetable = $true; searchable = $true }
    @{ name = 'metadata_storage_size'; type = 'Edm.Int64'; filterable = $true; sortable = $true; facetable = $true; searchable = $false }
    @{ name = 'metadata_storage_last_modified'; type = 'Edm.DateTimeOffset'; filterable = $true; sortable = $true; facetable = $true; searchable = $false }
    @{ name = 'metadata_content_type'; type = 'Edm.String'; filterable = $true; sortable = $false; facetable = $true; searchable = $false }
  )
} | ConvertTo-Json -Depth 10

Log "Creating search index '$IndexName'..."
try {
  Invoke-RestMethod -Uri "$searchEndpoint/indexes?api-version=2024-05-01-preview" -Method Post -Headers $activeHeaders -Body $indexSchema | Out-Null
  Log 'Index created successfully'
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Index '$IndexName' already exists, updating if needed..."
    Invoke-RestMethod -Uri "$searchEndpoint/indexes/$IndexName`?api-version=2024-05-01-preview" -Method Put -Headers $activeHeaders -Body $indexSchema | Out-Null
    Log 'Index updated successfully'
  } else { Fail "Failed to create index: $($_.Exception.Message)" }
}

# Create OneLake indexer
$indexerName = "$IndexName-indexer"
$indexer = @{
  name = $indexerName
  dataSourceName = $dataSourceName
  targetIndexName = $IndexName
  schedule = @{ interval = "PT$($ScheduleIntervalMinutes)M" }
  parameters = @{ batchSize = 100; maxFailedItems = 0; maxFailedItemsPerBatch = 0; configuration = @{ indexedFileNameExtensions = '.pdf,.docx,.pptx,.xlsx,.txt,.html,.json'; excludedFileNameExtensions = '.tmp,.temp'; dataToExtract = 'contentAndMetadata'; parsingMode = 'default' } }
} | ConvertTo-Json -Depth 10

Log "Creating OneLake indexer '$indexerName' with $ScheduleIntervalMinutes minute schedule..."
try {
  Invoke-RestMethod -Uri "$searchEndpoint/indexers?api-version=2024-05-01-preview" -Method Post -Headers $activeHeaders -Body $indexer | Out-Null
  Log 'Indexer created successfully'
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Indexer '$indexerName' already exists, updating..."
    Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName`?api-version=2024-05-01-preview" -Method Put -Headers $activeHeaders -Body $indexer | Out-Null
    Log 'Indexer updated successfully'
  } else { Fail "Failed to create indexer: $($_.Exception.Message)" }
}

# Run the indexer once to start initial indexing
Log 'Starting initial indexer run...'
try { Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName/run?api-version=2024-05-01-preview" -Method Post -Headers $activeHeaders | Out-Null; Log 'Initial indexer run started successfully' } catch { Warn "Could not start initial indexer run: $($_.Exception.Message)" }

Log 'OneLake indexer setup completed successfully!'
Log "Data source: $dataSourceName"
Log "Index: $IndexName"
Log "Indexer: $indexerName"
Log "Schedule: Every $ScheduleIntervalMinutes minutes"

# 2) Try azd env values
if (-not $subscriptionId -or -not $resourceGroup) {
  try {
    $envText = & azd env get-values 2>$null
    if ($envText) {
      foreach ($line in ($envText -split "`n")) {
        if (-not $subscriptionId -and $line -match '^AZURE_SUBSCRIPTION_ID=(.+)$') { $subscriptionId = $Matches[1].Trim() }
        if (-not $resourceGroup -and $line -match '^AZURE_RESOURCE_GROUP=(.+)$') { $resourceGroup = $Matches[1].Trim() }
      }
    }
  } catch { }
}

# 3) Fallback to current sub and heuristic RG selection
if (-not $subscriptionId) { try { $subscriptionId = (& az account show --query id -o tsv) } catch { $subscriptionId = $null } }
if (-not $resourceGroup) {
  try {
    $rgList = & az group list -o tsv --query "[].name"
    if ($rgList) {
      $candidates = $rgList -split "`n" | Where-Object { $_ -match '^rg-' }
      if ($candidates -and $candidates.Length -gt 0) { $resourceGroup = ($candidates | Select-Object -First 1) }
      else { $resourceGroup = (($rgList -split "`n") | Select-Object -First 1) }
    }
  } catch { }
}

# Normalize values to remove accidental surrounding quotes
if ($subscriptionId) { $subscriptionId = $subscriptionId.Trim().Trim('"') }
if ($resourceGroup) { $resourceGroup = $resourceGroup.Trim().Trim('"') }
if ($script:WorkspaceId) { $script:WorkspaceId = $script:WorkspaceId.Trim().Trim('"') }

if (-not $subscriptionId -or -not $resourceGroup) {
  Fail "Could not determine subscription/resource group for Fabric workspace. Provide -WorkspaceId and ensure az login; optionally set AZURE_RESOURCE_GROUP."
}

# Determine search endpoint (support custom endpoints for private links)
$searchEndpoint = if ($env:AI_SEARCH_CUSTOM_ENDPOINT -and $env:AI_SEARCH_CUSTOM_ENDPOINT -ne "") { 
  $env:AI_SEARCH_CUSTOM_ENDPOINT.TrimEnd('/')
} else { 
  "https://$AISearchName.search.windows.net" 
}

Log "Search endpoint: $searchEndpoint"

# Discover Search resource group and auth options for data plane calls
try {
  $searchResJson = & az resource list --resource-type Microsoft.Search/searchServices --name $AISearchName -o json --query "[0]"
  if (-not $searchResJson -or $searchResJson -eq "null") { Fail "AI Search service '$AISearchName' not found in current context" }
  $searchRes = $searchResJson | ConvertFrom-Json
  $searchRg = $searchRes.resourceGroup
  $disableLocalAuth = & az search service show --resource-group $searchRg --name $AISearchName --query disableLocalAuth -o tsv
  $adminKey = $null
  if ($disableLocalAuth -ne "true") {
    $adminKey = & az search admin-key show --resource-group $searchRg --service-name $AISearchName --query primaryKey -o tsv
  }
  # Ensure system-assigned managed identity is enabled (needed for OneLake data source identity)
  $identityType = & az search service show --resource-group $searchRg --name $AISearchName --query identity.type -o tsv 2>$null
  if (-not $identityType -or $identityType -eq "None") {
    Log "Enabling system-assigned managed identity on AI Search service..."
    & az search service update --resource-group $searchRg --name $AISearchName --assign-identity system | Out-Null
    Start-Sleep -Seconds 3
    $identityType = & az search service show --resource-group $searchRg --name $AISearchName --query identity.type -o tsv 2>$null
    Log "AI Search identity type: $identityType"
  }
  # Bearer fallback
  $aadToken = $null
  try { $aadToken = & az account get-access-token --resource https://search.azure.com --query accessToken -o tsv } catch {}
  if (-not $adminKey -and -not $aadToken) { Fail "Could not acquire either admin key or AAD token for AI Search" }
  $headersApiKey = if ($adminKey) { @{ 'Content-Type' = 'application/json'; 'api-key' = $adminKey } } else { $null }
  $headersBearer = if ($aadToken) { @{ 'Content-Type' = 'application/json'; 'Authorization' = "Bearer $aadToken" } } else { $null }
} catch {
  Fail "Failed to acquire AI Search admin key: $($_.Exception.Message)"
}

# Create OneLake data source (per Learn docs)
$dataSourceName = "$IndexName-onelake-datasource"

# Build connection string variants that some service versions accept
$workspaceArmId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Fabric/workspaces/$($script:WorkspaceId)"
$tenantId = $null
try { $tenantId = & az account show --query tenantId -o tsv 2>$null } catch { $tenantId = $null }
Log "Using Fabric workspace ARM ResourceId: $workspaceArmId"
if ($tenantId) { Log "TenantId: $tenantId" }

$connStrPreferred = "ResourceId=/workspaces/$($script:WorkspaceId);OneLakeEndpoint=https://onelake.dfs.fabric.microsoft.com" + ($(if($tenantId){";TenantId=$tenantId"} else {""}))
$connStrFallbackArm = "ResourceId=$workspaceArmId" + ($(if($tenantId){";TenantId=$tenantId"} else {""}))

$dataSource = @{
  name = $dataSourceName
  type = "onelake"
  credentials = @{
  connectionString = $connStrPreferred
  }
  container = @{
    name = $lakehouseId
    query = "$FolderPath"
  }
} | ConvertTo-Json -Depth 10

Log "Creating OneLake data source '$dataSourceName'..."

try {
  $activeHeaders = if ($headersApiKey) { $headersApiKey } else { $headersBearer }
  Invoke-RestMethod -Uri "$searchEndpoint/datasources?api-version=2024-05-01-preview" `
    -Method Post `
    -Headers $activeHeaders `
    -Body $dataSource
  
  Log "Data source created successfully"
} catch {
  # For debugging, let's check what we're sending
  Log "Request body: $dataSource"
  # If service claims ResourceId missing, retry once with ARM-based connection string variant
  $shouldRetry = $false
  try {
    $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    $errBody = $sr.ReadToEnd()
    if ($errBody -match 'ResourceId') { $shouldRetry = $true }
  } catch {}
  if ($shouldRetry) {
    Warn "Retrying datasource create with ARM ResourceId variant..."
    $dataSourceRetry = @{
      name = $dataSourceName
      type = "onelake"
      credentials = @{ connectionString = $connStrFallbackArm }
      container = @{ name = $lakehouseId; query = "$FolderPath" }
    } | ConvertTo-Json -Depth 10
    Log "Retry request body: $dataSourceRetry"
    try {
  Invoke-RestMethod -Uri "$searchEndpoint/datasources?api-version=2024-05-01-preview" -Method Post -Headers $activeHeaders -Body $dataSourceRetry
      Log "Data source created successfully on retry"
      $dataSource = $dataSourceRetry
      $shouldRetry = $false
    } catch {
      Log "Retry failed: $($_.Exception.Message)"
    }
  }
  
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Data source '$dataSourceName' already exists, updating..."
    try {
  Invoke-RestMethod -Uri "$searchEndpoint/datasources/$dataSourceName`?api-version=2024-05-01-preview" `
        -Method Put `
        -Headers $activeHeaders `
        -Body $dataSource
      Log "Data source updated successfully"
    } catch {
      Fail "Failed to update data source: $($_.Exception.Message)"
    }
  } else {
    # Try to get error details using curl for better error reporting
    Log "Attempting to get detailed error with curl..."
    $tempFile = "/tmp/datasource_request.json"
    $dataSource | Out-File -FilePath $tempFile -Encoding UTF8
    
    $curlResult = if ($adminKey) {
      & curl -s -X POST "$searchEndpoint/datasources?api-version=2024-05-01-preview" -H "Content-Type: application/json" -H "api-key: $adminKey" -d "@$tempFile" 2>&1
    } else {
      & curl -s -X POST "$searchEndpoint/datasources?api-version=2024-05-01-preview" -H "Content-Type: application/json" -H "Authorization: Bearer $aadToken" -d "@$tempFile" 2>&1
    }
    
    Log "Curl response: $curlResult"
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
  Invoke-RestMethod -Uri "$searchEndpoint/indexes?api-version=2024-05-01-preview" `
    -Method Post `
    -Headers $activeHeaders `
    -Body $indexSchema
  
  Log "Index created successfully"
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Index '$IndexName' already exists, updating if needed..."
    try {
  Invoke-RestMethod -Uri "$searchEndpoint/indexes/$IndexName`?api-version=2024-05-01-preview" `
        -Method Put `
        -Headers $activeHeaders `
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
  Invoke-RestMethod -Uri "$searchEndpoint/indexers?api-version=2024-05-01-preview" `
    -Method Post `
    -Headers $activeHeaders `
    -Body $indexer
  
  Log "Indexer created successfully"
  Log "Indexer will run every $ScheduleIntervalMinutes minutes"
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Warn "Indexer '$indexerName' already exists, updating..."
    try {
  Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName`?api-version=2024-05-01-preview" `
        -Method Put `
        -Headers $activeHeaders `
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
  Invoke-RestMethod -Uri "$searchEndpoint/indexers/$indexerName/run?api-version=2024-05-01-preview" `
    -Method Post `
    -Headers $activeHeaders
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
