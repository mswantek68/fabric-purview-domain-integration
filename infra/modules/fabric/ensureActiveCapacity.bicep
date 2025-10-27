@description('Ensures Microsoft Fabric capacity is in Active state using deployment script')
param fabricCapacityId string
param fabricCapacityName string
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



@description('Resume timeout in seconds')
param resumeTimeoutSeconds int = 900

@description('Poll interval in seconds')
param pollIntervalSeconds int = 20

// Generate unique names for deployment script resources
var deploymentScriptName = 'ensure-capacity-${uniqueString(resourceGroup().id, fabricCapacityName)}'

// Deployment script to ensure capacity is active
resource ensureCapacityDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
        name: 'FABRIC_CAPACITY_ID'
        value: fabricCapacityId
      }
      {
        name: 'FABRIC_CAPACITY_NAME'
        value: fabricCapacityName
      }
      {
        name: 'RESUME_TIMEOUT_SECONDS'
        value: string(resumeTimeoutSeconds)
      }
      {
        name: 'POLL_INTERVAL_SECONDS'
        value: string(pollIntervalSeconds)
      }
    ]
    scriptContent: '''
# Ensure Fabric Capacity is Active
param(
  [string]$CapacityId = $env:FABRIC_CAPACITY_ID,
  [string]$CapacityName = $env:FABRIC_CAPACITY_NAME,
  [int]$ResumeTimeoutSeconds = [int]$env:RESUME_TIMEOUT_SECONDS,
  [int]$PollIntervalSeconds = [int]$env:POLL_INTERVAL_SECONDS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m) { 
  Write-Host "[fabric-capacity] $m" 
  Write-Output "[fabric-capacity] $m"
}

function Warn([string]$m) { 
  Write-Warning "[fabric-capacity] $m"
  Write-Output "[WARNING] $m"
}

function Fail([string]$m) { 
  Write-Error "[fabric-capacity] $m"
  throw $m
}

if (-not $CapacityId) { 
  Fail 'FABRIC_CAPACITY_ID is required'
}

Log "Ensuring capacity Active: $CapacityName ($CapacityId)"

# Function to get capacity state
function Get-CapacityState {
  param([string]$Id)
  try {
    $resJson = & az resource show --ids $Id -o json 2>$null | ConvertFrom-Json -ErrorAction Stop
    return $resJson.properties.state
  } catch {
    return $null
  }
}

$state = Get-CapacityState -Id $CapacityId
if (-not $state) { 
  Warn "Unable to retrieve capacity state; proceeding anyway"
  $DeploymentScriptOutputs = @{
    capacityState = 'Unknown'
    capacityActive = $false
  }
  return
}

Log "Current capacity state: $state"

if ($state -eq 'Active') { 
  Log 'Capacity already Active.'
  $DeploymentScriptOutputs = @{
    capacityState = $state
    capacityActive = $true
  }
  return
}

if ($state -ne 'Paused' -and $state -ne 'Suspended') {
  Warn "Capacity state '$state' not Active; not attempting resume (only valid for Paused/Suspended)."
  $DeploymentScriptOutputs = @{
    capacityState = $state
    capacityActive = $false
  }
  return
}

Log "Attempting to resume capacity..."

# Use az powerbi embedded-capacity resume
try {
  $resourceGroup = ($CapacityId -split '/')[4]
  $resumeOut = & az powerbi embedded-capacity resume --name $CapacityName --resource-group $resourceGroup 2>&1
  $rc = $LASTEXITCODE
} catch {
  $rc = 1
  $resumeOut = $_
}

if ($rc -ne 0) {
  Warn "Resume command failed (exit $rc): $resumeOut"
  Warn "Proceeding without Active capacity"
  $DeploymentScriptOutputs = @{
    capacityState = $state
    capacityActive = $false
  }
  return
}

Log "Resume command issued; polling for Active state (timeout ${ResumeTimeoutSeconds}s, interval ${PollIntervalSeconds}s)."

$start = Get-Date
while ($true) {
  Start-Sleep -Seconds $PollIntervalSeconds
  $state = Get-CapacityState -Id $CapacityId
  
  if ($state -eq 'Active') { 
    Log 'Capacity is Active.'
    $DeploymentScriptOutputs = @{
      capacityState = $state
      capacityActive = $true
    }
    return
  }
  
  $elapsed = (Get-Date) - $start
  if ($elapsed.TotalSeconds -ge $ResumeTimeoutSeconds) { 
    Warn "Timeout waiting for Active state (last state=$state). Continuing anyway."
    $DeploymentScriptOutputs = @{
      capacityState = $state
      capacityActive = $false
    }
    return
  }
  
  Log "State=$state; waiting ${PollIntervalSeconds}s..."
}
    '''
  }
}

// Outputs
output capacityState string = ensureCapacityDeploymentScript.properties.outputs.capacityState
output capacityActive bool = ensureCapacityDeploymentScript.properties.outputs.capacityActive
