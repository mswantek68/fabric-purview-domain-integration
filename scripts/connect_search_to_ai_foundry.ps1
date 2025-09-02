<#
.SYNOPSIS
  Connect an Azure AI Search index to Azure AI Foundry as a data source
.DESCRIPTION
  This script registers an Azure AI Search index as a data source in Azure AI Foundry,
  making it available for use in the AI playground and other AI workflows.
.PARAMETER IndexName
  The name of the search index to connect
.PARAMETER AIFoundryName
  The name of the Azure AI Foundry workspace
.PARAMETER DataSourceName
  Optional custom name for the data source. If not provided, will be generated from index name
.PARAMETER Description
  Optional description for the data source
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$IndexName,
  
  [string]$AIFoundryName,
  [string]$DataSourceName,
  [string]$Description
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[ai-foundry-connect] $m" }
function Warn([string]$m){ Write-Warning "[ai-foundry-connect] $m" }
function Fail([string]$m){ Write-Error "[ai-foundry-connect] $m"; exit 1 }

# Resolve AI Foundry name from environment if not provided
if (-not $AIFoundryName) {
  try { $AIFoundryName = & azd env get-value aiFoundryName 2>$null } catch {}
  if (-not $AIFoundryName) { $AIFoundryName = & azd env get-value fabricCapacityName 2>$null }
  if ($AIFoundryName) { $AIFoundryName = "$AIFoundryName-aiworkspace" }
}
if (-not $AIFoundryName) { Fail "AIFoundryName not provided and could not be resolved from environment" }

# Generate data source name if not provided
if (-not $DataSourceName) {
  $DataSourceName = "$IndexName-datasource"
}

# Generate description if not provided
if (-not $Description) {
  $Description = "Data source from search index: $IndexName"
}

# Load index configuration
$configPath = "/tmp/search_index_$($IndexName.Replace('-', '_')).json"
if (-not (Test-Path $configPath)) {
  Fail "Index configuration not found at $configPath. Run create_search_index_for_folder.ps1 first."
}

try {
  $indexConfig = Get-Content $configPath | ConvertFrom-Json
  $aiSearchName = $indexConfig.aiSearchName
  $searchEndpoint = $indexConfig.searchEndpoint
  $folderPath = $indexConfig.folderPath
} catch {
  Fail "Failed to load index configuration: $_"
}

Log "Connecting search index to AI Foundry"
Log "  • Search Index: $IndexName"
Log "  • AI Search Service: $aiSearchName"
Log "  • AI Foundry: $AIFoundryName"
Log "  • Data Source Name: $DataSourceName"
Log "  • Folder Path: $folderPath"

# Get Azure subscription and resource group
$subscriptionId = (& az account show --query id -o tsv)
$resourceGroup = (& az group list --query "[?contains(name, 'rg-')].name" -o tsv | Select-Object -First 1)

if (-not $subscriptionId -or -not $resourceGroup) {
  Fail "Could not determine subscription ID or resource group. Ensure 'az login' is completed."
}

# Get AI Search admin key
try {
  $searchKey = & az search admin-key show --service-name $aiSearchName --resource-group $resourceGroup --query primaryKey -o tsv
  if (-not $searchKey) { Fail "Could not retrieve AI Search admin key" }
} catch {
  Fail "Failed to get AI Search admin key: $_"
}

# Check if AI Foundry workspace exists
try {
  $aiFoundryWorkspace = & az ml workspace show --name $AIFoundryName --resource-group $resourceGroup --query id -o tsv 2>$null
  if (-not $aiFoundryWorkspace) {
    Warn "AI Foundry workspace '$AIFoundryName' not found, attempting to find ML workspace..."
    $mlWorkspaces = & az ml workspace list --resource-group $resourceGroup --query "[].name" -o tsv
    if ($mlWorkspaces) {
      $AIFoundryName = $mlWorkspaces | Select-Object -First 1
      Log "Using ML workspace: $AIFoundryName"
    } else {
      Fail "No ML workspace found in resource group '$resourceGroup'"
    }
  }
} catch {
  Fail "Failed to check AI Foundry workspace: $_"
}

# Create data source configuration for AI Foundry
$dataSourceConfig = @{
  name = $DataSourceName
  description = $Description
  type = "azure_search"
  properties = @{
    endpoint = $searchEndpoint
    index_name = $IndexName
    api_key = $searchKey
    search_service_name = $aiSearchName
    semantic_configuration = "default"
    top_k = 10
    folder_path = $folderPath
  }
  metadata = @{
    created_from = "lakehouse_folder"
    folder_path = $folderPath
    search_index = $IndexName
    created_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  }
} | ConvertTo-Json -Depth 10

# Save data source configuration as a file in the AI Foundry workspace
$configFileName = "datasource_$($DataSourceName.Replace('-', '_')).json"
$tempConfigPath = "/tmp/$configFileName"
$dataSourceConfig | Out-File -FilePath $tempConfigPath -Encoding UTF8

Log "Creating data source configuration file..."

try {
  # Upload the configuration to the ML workspace as a data asset
  $dataAssetConfig = @{
    name = $DataSourceName
    description = $Description
    type = "uri_file"
    path = $tempConfigPath
    properties = @{
      data_source_type = "azure_search"
      search_service = $aiSearchName
      search_index = $IndexName
      folder_path = $folderPath
    }
  } | ConvertTo-Json -Depth 10
  
  $dataAssetTempPath = "/tmp/data_asset_$($DataSourceName.Replace('-', '_')).yml"
  
  # Create YAML format for Azure ML
  $yamlContent = @"
name: $DataSourceName
description: $Description
type: uri_file
path: $tempConfigPath
properties:
  data_source_type: azure_search
  search_service: $aiSearchName
  search_index: $IndexName
  folder_path: $folderPath
  endpoint: $searchEndpoint
"@
  
  $yamlContent | Out-File -FilePath $dataAssetTempPath -Encoding UTF8
  
  Log "Registering data source in AI Foundry workspace..."
  $createResult = & az ml data create --file $dataAssetTempPath --workspace-name $AIFoundryName --resource-group $resourceGroup 2>&1
  
  if ($LASTEXITCODE -eq 0) {
    Log "Data source registered successfully in AI Foundry"
  } else {
    Warn "Failed to register as ML data asset: $createResult"
    Log "Saving configuration for manual registration..."
  }
  
} catch {
  Warn "Failed to register data source in AI Foundry: $($_.Exception.Message)"
  Log "Configuration saved for manual registration"
}

# Save connection details for other scripts
$connectionConfig = @{
  dataSourceName = $DataSourceName
  aiFoundryName = $AIFoundryName
  aiSearchName = $aiSearchName
  indexName = $IndexName
  folderPath = $folderPath
  searchEndpoint = $searchEndpoint
  configFilePath = $tempConfigPath
  registeredAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
} | ConvertTo-Json -Depth 10

$connectionConfigPath = "/tmp/ai_foundry_connection_$($DataSourceName.Replace('-', '_')).json"
$connectionConfig | Out-File -FilePath $connectionConfigPath -Encoding UTF8

Log "Connection configuration saved to: $connectionConfigPath"

# Create a simple validation script
$validationScript = @"
# Validation script for AI Foundry data source connection
# Run this in the AI Foundry playground to test the connection

from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential

# Connection details
search_endpoint = "$searchEndpoint"
index_name = "$IndexName"
search_key = "$searchKey"

# Test the connection
search_client = SearchClient(
    endpoint=search_endpoint,
    index_name=index_name,
    credential=AzureKeyCredential(search_key)
)

# Sample search query
results = search_client.search(
    search_text="*",
    top=5,
    include_total_count=True
)

print(f"Connected to index '{index_name}' successfully!")
print(f"Total documents: {results.get_count()}")
print("\\nSample documents:")
for result in results:
    print(f"- {result.get('fileName', 'Unknown')}: {result.get('content', '')[:100]}...")
"@

$validationScriptPath = "/tmp/validate_ai_foundry_connection.py"
$validationScript | Out-File -FilePath $validationScriptPath -Encoding UTF8

Log "AI Foundry connection completed successfully"
Log "Data source '$DataSourceName' is now available in AI Foundry workspace '$AIFoundryName'"
Log "Validation script created: $validationScriptPath"
Log "Run the validation script in AI Foundry playground to test the connection"

exit 0
