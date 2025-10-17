@description('Creates Fabric lakehouses (bronze, silver, gold) using deployment script')
param workspaceName string
param workspaceId string
param lakehouseNames string = 'bronze,silver,gold'
param location string = resourceGroup().location
param utcValue string = utcNow()

@description('Tags to apply to resources')
param tags object = {}

@description('Managed Identity for deployment script execution')
param userAssignedIdentityId string

@description('Name of the shared storage account for deployment scripts')
param storageAccountName string

@description('Storage account key for deployment scripts')
@secure()
param storageAccountKey string



// Generate unique names for deployment script resources
var deploymentScriptName = 'create-lakehouses-${uniqueString(resourceGroup().id, workspaceName)}'

// Deployment script to create lakehouses
resource createLakehousesDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: deploymentScriptName
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    forceUpdateTag: utcValue
    retentionInterval: 'P1D'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    storageAccountSettings: {
      storageAccountName: storageAccountName
      storageAccountKey: storageAccountKey
    }
    environmentVariables: [
      {
        name: 'FABRIC_WORKSPACE_NAME'
        value: workspaceName
      }
      {
        name: 'WORKSPACE_ID'
        value: workspaceId
      }
      {
        name: 'LAKEHOUSE_NAMES'
        value: lakehouseNames
      }
    ]
    scriptContent: '''
# Create Fabric Lakehouses
param(
  [string]$WorkspaceName = $env:FABRIC_WORKSPACE_NAME,
  [string]$WorkspaceId = $env:WORKSPACE_ID,
  [string]$LakehouseNames = $env:LAKEHOUSE_NAMES
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { 
  Write-Host "[fabric-lakehouses] $m" 
  Write-Output "[fabric-lakehouses] $m"
}

function Warn([string]$m) { 
  Write-Warning "[fabric-lakehouses] $m"
  Write-Output "[WARNING] $m"
}

function Fail([string]$m) { 
  Write-Error "[fabric-lakehouses] $m"
  throw $m
}

if (-not $WorkspaceId) { 
  Fail 'WORKSPACE_ID is required' 
}

if (-not $LakehouseNames) { 
  $LakehouseNames = 'bronze,silver,gold' 
}

Log "Creating lakehouses in workspace: $WorkspaceName ($WorkspaceId)"
Log "Lakehouse names: $LakehouseNames"

# Acquire token
try { 
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
  if (-not $accessToken) { throw "No token returned" }
} catch { 
  Fail "Failed to obtain Fabric API token"
}

$apiRoot = 'https://api.fabric.microsoft.com/v1'
$names = $LakehouseNames -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$created = 0
$skipped = 0
$failed = 0
$lakehouseIds = @{}

foreach ($name in $names) {
  # Check existence
  $match = $null
  try {
    $existingLakehouses = Invoke-RestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/lakehouses" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    if ($existingLakehouses.value) {
      $match = $existingLakehouses.value | Where-Object {
        $hasDisplay = $_.PSObject.Properties['displayName'] -ne $null
        $hasName = $_.PSObject.Properties['name'] -ne $null
        ($hasDisplay -and ($_.displayName -eq $name)) -or ($hasName -and ($_.name -eq $name))
      }
    }
  } catch { }

  if ($match) { 
    Log "Lakehouse exists: $name ($($match.id))"
    $lakehouseIds[$name] = $match.id
    $skipped++
    continue 
  }
  
  Log "Creating lakehouse: $name"

  $maxAttempts = 6
  $attempt = 0
  $backoff = 15
  $created_this = $false
  $lakehouseId = $null

  $lhPayload = @{ displayName = $name } | ConvertTo-Json -Depth 6
  $lhUrl = "$apiRoot/workspaces/$WorkspaceId/lakehouses"
  $itemsPayload = @{ displayName = $name; type = 'Lakehouse' } | ConvertTo-Json -Depth 6
  $itemsUrl = "$apiRoot/workspaces/$WorkspaceId/items"

  while (($attempt -lt $maxAttempts) -and (-not $created_this)) {
    $attempt++
    
    # Try dedicated lakehouses endpoint first
    try {
      $resp = Invoke-WebRequest -Uri $lhUrl -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body $lhPayload -UseBasicParsing -ErrorAction Stop
      $code = $resp.StatusCode
      $respBody = $resp.Content
    } catch {
      $code = $null
      $respBody = $_.ToString()
      if ($_.Exception -and $_.Exception.Response) {
        try {
          if ($_.Exception.Response -is [System.Net.Http.HttpResponseMessage]) {
            $respBody = $_.Exception.Response.Content.ReadAsStringAsync().Result
          }
        } catch { }
      }
    }

    if ($code -and $code -ge 200 -and $code -lt 300) {
      try { 
        $content = $respBody | ConvertFrom-Json -ErrorAction SilentlyContinue 
        $lakehouseId = $content.id
      } catch { }
      Log "Created lakehouse $name ($lakehouseId)"
      $lakehouseIds[$name] = $lakehouseId
      $created++
      $created_this = $true
      break
    }

    # Handle specific response bodies
    if ($respBody -and $respBody -match 'UnsupportedCapacitySKU') {
      Warn "UnsupportedCapacitySKU for $name. Capacity SKU does not support this operation."
      break
    }
    if ($respBody -and $respBody -match 'ItemDisplayNameAlreadyInUse') {
      Log "Item display name already in use for $name - treating as present"
      $created++
      $created_this = $true
      break
    }
    if ($respBody -and $respBody -match 'NotInActiveState') {
      Warn "Attempt ${attempt}: Capacity not active yet for $name (will retry in $backoff s)."
      Start-Sleep -Seconds $backoff
      continue
    }

    # If transient server error, retry
    if ($code -and ($code -ge 500 -or $code -eq 429)) {
      Start-Sleep -Seconds $backoff
      continue
    }

    # Fallback: try the generic items endpoint
    try {
      $resp2 = Invoke-WebRequest -Uri $itemsUrl -Method Post -Headers @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } -Body $itemsPayload -UseBasicParsing -ErrorAction Stop
      $code2 = $resp2.StatusCode
      $respBody2 = $resp2.Content
    } catch {
      $code2 = $null
      $respBody2 = $_.ToString()
    }

    if ($code2 -and $code2 -ge 200 -and $code2 -lt 300) {
      try { 
        $content2 = $respBody2 | ConvertFrom-Json -ErrorAction SilentlyContinue 
        $lakehouseId = $content2.id
      } catch { }
      Log "Created lakehouse $name ($lakehouseId) via items endpoint"
      $lakehouseIds[$name] = $lakehouseId
      $created++
      $created_this = $true
      break
    }

    if ($respBody2 -and $respBody2 -match 'UnsupportedCapacitySKU') {
      Warn "UnsupportedCapacitySKU for $name on items endpoint."
      break
    }
    if ($respBody2 -and $respBody2 -match 'ItemDisplayNameAlreadyInUse') {
      Log "Item display name already in use for $name (items endpoint) - treating as present"
      $created++
      $created_this = $true
      break
    }
    if ($respBody2 -and $respBody2 -match 'NotInActiveState') {
      Warn "Attempt ${attempt}: Capacity not active yet for $name (on items endpoint); retrying in $backoff s."
      Start-Sleep -Seconds $backoff
      continue
    }

    Warn "Attempt ${attempt}: Failed to create $name."
    break
  }

  if (-not $created_this) { $failed++ }
  Start-Sleep -Seconds 1
}

Log "Lakehouse creation summary: created=$created skipped=$skipped failed=$failed"

# Set outputs for Bicep
$DeploymentScriptOutputs = @{
  lakehousesCreated = $created
  lakehousesSkipped = $skipped
  lakehousesFailed = $failed
  lakehouseIds = ($lakehouseIds | ConvertTo-Json -Compress)
}
    '''
  }
}

// Outputs
output lakehousesCreated int = createLakehousesDeploymentScript.properties.outputs.lakehousesCreated
output lakehousesSkipped int = createLakehousesDeploymentScript.properties.outputs.lakehousesSkipped
output lakehousesFailed int = createLakehousesDeploymentScript.properties.outputs.lakehousesFailed
output lakehouseIds string = createLakehousesDeploymentScript.properties.outputs.lakehouseIds
