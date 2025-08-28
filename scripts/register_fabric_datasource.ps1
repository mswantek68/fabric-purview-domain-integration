<#
.SYNOPSIS
  Register Fabric/PowerBI as a datasoure in Purview (PowerShell version)
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[fabric-datasource] $m" }
function Warn([string]$m){ Write-Warning "[fabric-datasource] $m" }
function Fail([string]$m){ Write-Error "[fabric-datasource] $m"; exit 1 }

# Resolve Purview account and collection name from azd (if present)
$purviewAccountName = $null; $collectionName = $null
try { $purviewAccountName = & azd env get-value purviewAccountName 2>$null } catch {}
try { $collectionName = & azd env get-value desiredFabricDomainName 2>$null } catch {}

if (-not $purviewAccountName) { Fail 'Missing required value: purviewAccountName' }

# Try to read collection info from /tmp/purview_collection.env
$collectionId = $collectionName
if (Test-Path '/tmp/purview_collection.env') {
  Get-Content '/tmp/purview_collection.env' | ForEach-Object {
    if ($_ -match '^PURVIEW_COLLECTION_ID=(.+)$') { $collectionId = $Matches[1] }
  }
}

$endpoint = "https://$purviewAccountName.purview.azure.com"

# Acquire token
try { 
  $purviewToken = & az account get-access-token --resource https://purview.azure.net --query accessToken -o tsv 2>$null
  if (-not $purviewToken) {
    $purviewToken = & az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv 2>$null
  }
} catch { $purviewToken = $null }
if (-not $purviewToken) { Fail 'Failed to acquire Purview access token' }
# Acquire token
try { 
  $purviewToken = & az account get-access-token --resource https://purview.azure.net --query accessToken -o tsv 2>$null
  if (-not $purviewToken) {
    $purviewToken = & az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv 2>$null
  }
} catch { $purviewToken = $null }
if (-not $purviewToken) { Fail 'Failed to acquire Purview access token' }

# Debug: print the identity running this script
try {
  $acctName = & az account show --query name -o tsv 2>$null
} catch { $acctName = $null }
if ($acctName) { Log "Running as Azure account: $acctName" }

Log "Checking for existing Fabric (PowerBI) datasources..."
try {
  $existing = Invoke-RestMethod -Uri "$endpoint/scan/datasources?api-version=2022-07-01-preview" -Headers @{ Authorization = "Bearer $purviewToken" } -Method Get -ErrorAction Stop
} catch { $existing = @{ value = @() } }

$fabricDatasourceName = $null
# Prefer root-level powerbi datasource (no collection or in root collection)
if ($existing.value) {
  foreach ($ds in $existing.value) {
    if ($ds.kind -eq 'PowerBI') {
      # Accept datasources with no collection OR in the account root collection
      $isRootLevel = (-not $ds.properties.collection) -or 
                     ($ds.properties.collection -eq $null) -or 
                     ($ds.properties.collection.referenceName -eq $purviewAccountName)
      if ($isRootLevel) { 
        $fabricDatasourceName = $ds.name
        Log "Found existing Fabric datasource at root level: $fabricDatasourceName"
        break 
      }
    }
  }
}

if ($fabricDatasourceName) {
  Log "Found existing Fabric datasource registered at account root: $fabricDatasourceName"
} else {
  # No root-level datasource; check for any PowerBI datasource
  $anyPbi = $null
  if ($existing.value) {
    $anyPbi = $existing.value | Where-Object { $_.kind -eq 'PowerBI' } | Select-Object -First 1
  }
  if ($anyPbi) {
    Warn "Found existing PowerBI datasource '${($anyPbi.name)}' registered under a collection and no root-level Fabric datasource exists. Using that datasource and not creating a new root-level datasource."
    $fabricDatasourceName = $anyPbi.name
    $collectionRef = $anyPbi.properties.collection.referenceName
    if ($collectionRef) { $collectionId = $collectionRef }
  } else {
    # No PowerBI datasource exists; create root-level one
    Log "No existing PowerBI datasource found — registering Fabric at account root"
    $datasourceName = 'Fabric'
    $payload = @{ kind = 'PowerBI'; name = $datasourceName; properties = @{ tenant = (& az account show --query tenantId -o tsv) } } | ConvertTo-Json -Depth 6
    try {
      $resp = Invoke-WebRequest -Uri "$endpoint/scan/datasources/${datasourceName}?api-version=2022-07-01-preview" -Headers @{ Authorization = "Bearer $purviewToken"; 'Content-Type' = 'application/json' } -Method Put -Body $payload -UseBasicParsing -ErrorAction Stop
      if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
        $fabricDatasourceName = $datasourceName
        Log "Fabric datasource '$datasourceName' registered successfully at account root (HTTP $($resp.StatusCode))"
      } else {
        Warn "Unexpected HTTP status: $($resp.StatusCode)"
        throw "HTTP $($resp.StatusCode)"
      }
    } catch {
      # Capture possible HTTP response body for debugging
      $errBody = $null
      $httpCode = $null
      if ($_.Exception -and $_.Exception.Response) {
        try {
          $httpCode = [int]$_.Exception.Response.StatusCode
          $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
          $errBody = $sr.ReadToEnd()
        } catch {}
      }
      if ($errBody) { Warn "Create error body: $errBody" }
      Warn "Fabric datasource registration failed (HTTP $httpCode): $_"
      # Re-check datasources and try to pick an existing PowerBI datasource as a fallback
      try {
        $existing = Invoke-RestMethod -Uri "$endpoint/scan/datasources?api-version=2022-07-01-preview" -Headers @{ Authorization = "Bearer $purviewToken" } -Method Get -ErrorAction Stop
      } catch { $existing = @{ value = @() } }
      $anyPbi = $null
      if ($existing.value) { $anyPbi = $existing.value | Where-Object { $_.kind -eq 'PowerBI' } | Select-Object -First 1 }
      if ($anyPbi) {
        Warn "Found existing PowerBI datasource after failed create: $($anyPbi.name). Using it."
        $fabricDatasourceName = $anyPbi.name
        $collectionRef = $anyPbi.properties.collection.referenceName
        if ($collectionRef) { $collectionId = $collectionRef }
      } else {
        # Instead of failing the entire provisioning, continue but mark that we couldn't register a datasource.
        Warn "Could not create Fabric datasource in Purview (server returned ResourceNotFound or registration method not supported)."
        Warn "Proceeding without a registered Purview datasource. Downstream Purview scan creation will be skipped."
        # Leave the datasource name blank so downstream scripts can detect and skip scans.
        $fabricDatasourceName = ''
        $collectionId = ''
        # do not exit; allow provisioning to continue
      }
    }
  }
}

Log "Fabric datasource registration completed: $fabricDatasourceName"
if ($collectionId) { Log "Collection: $collectionId" } else { Log 'Collection: (default/root)' }

# Export for other scripts
$envContent = @()
$envContent += "FABRIC_DATASOURCE_NAME=$fabricDatasourceName"
if ($collectionId) { $envContent += "FABRIC_COLLECTION_ID=$collectionId" } else { $envContent += "FABRIC_COLLECTION_ID=" }
Set-Content -Path '/tmp/fabric_datasource.env' -Value $envContent

exit 0
