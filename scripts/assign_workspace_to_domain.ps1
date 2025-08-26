<#
.SYNOPSIS
  Assign Fabric workspaces on a capacity to a domain (PowerShell)
.DESCRIPTION
  Translated from assign_workspace_to_domain.sh. Requires Azure CLI and appropriate permissions.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[assign-domain] $m" }
function Warn([string]$m){ Write-Warning "[assign-domain] $m" }
function Fail([string]$m){ Write-Error "[assign-domain] $m"; exit 1 }

# Resolve values from environment or azd
$FABRIC_CAPACITY_ID = $env:FABRIC_CAPACITY_ID
$FABRIC_WORKSPACE_NAME = $env:FABRIC_WORKSPACE_NAME
$FABRIC_DOMAIN_NAME = $env:FABRIC_DOMAIN_NAME
$FABRIC_CAPACITY_NAME = $env:FABRIC_CAPACITY_NAME

# Try AZURE_OUTPUTS_JSON
if ($env:AZURE_OUTPUTS_JSON) {
  try {
    $out = $env:AZURE_OUTPUTS_JSON | ConvertFrom-Json -ErrorAction Stop
    if (-not $FABRIC_CAPACITY_ID -and $out.fabricCapacityId -and $out.fabricCapacityId.value) { $FABRIC_CAPACITY_ID = $out.fabricCapacityId.value }
    if (-not $FABRIC_WORKSPACE_NAME -and $out.desiredFabricWorkspaceName -and $out.desiredFabricWorkspaceName.value) { $FABRIC_WORKSPACE_NAME = $out.desiredFabricWorkspaceName.value }
    if (-not $FABRIC_DOMAIN_NAME -and $out.desiredFabricDomainName -and $out.desiredFabricDomainName.value) { $FABRIC_DOMAIN_NAME = $out.desiredFabricDomainName.value }
    if (-not $FABRIC_CAPACITY_NAME -and $out.fabricCapacityName -and $out.fabricCapacityName.value) { $FABRIC_CAPACITY_NAME = $out.fabricCapacityName.value }
  } catch { }
}

# Try .azure env file
if ((-not $FABRIC_WORKSPACE_NAME) -or (-not $FABRIC_DOMAIN_NAME) -or (-not $FABRIC_CAPACITY_ID)) {
  $envDir = $env:AZURE_ENV_NAME
  if (-not $envDir -and (Test-Path '.azure')) { $dirs = Get-ChildItem -Path .azure -Name -ErrorAction SilentlyContinue; if ($dirs) { $envDir = $dirs[0] } }
  if ($envDir) {
    $envPath = Join-Path -Path '.azure' -ChildPath "$envDir/.env"
    if (Test-Path $envPath) {
      Get-Content $envPath | ForEach-Object {
        if ($_ -match '^fabricCapacityId=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_CAPACITY_ID) { $FABRIC_CAPACITY_ID = $Matches[1] } }
        if ($_ -match '^desiredFabricWorkspaceName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_WORKSPACE_NAME) { $FABRIC_WORKSPACE_NAME = $Matches[1] } }
        if ($_ -match '^desiredFabricDomainName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_DOMAIN_NAME) { $FABRIC_DOMAIN_NAME = $Matches[1] } }
        if ($_ -match '^fabricCapacityName=(?:"|")?(.+?)(?:"|")?$') { if (-not $FABRIC_CAPACITY_NAME) { $FABRIC_CAPACITY_NAME = $Matches[1] } }
      }
    }
  }
}

if (-not $FABRIC_WORKSPACE_NAME) { Fail 'FABRIC_WORKSPACE_NAME unresolved (no outputs/env/bicep).' }
if (-not $FABRIC_DOMAIN_NAME) { Fail 'FABRIC_DOMAIN_NAME unresolved (no outputs/env/bicep).' }
if (-not $FABRIC_CAPACITY_ID) { Fail 'FABRIC_CAPACITY_ID unresolved (no outputs/env/bicep).' }

Log "Assigning workspace '$FABRIC_WORKSPACE_NAME' to domain '$FABRIC_DOMAIN_NAME'"

# Acquire tokens
try { $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv } catch { $accessToken = $null }
try { $fabricToken = & az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv } catch { $fabricToken = $null }
if (-not $accessToken) { Fail 'Unable to obtain Power BI API token (az login as Fabric admin).' }
if (-not $fabricToken) { Fail 'Unable to obtain Fabric API token (az login as Fabric admin).' }

$apiFabricRoot = 'https://api.fabric.microsoft.com/v1'
$apiPbiRoot = 'https://api.powerbi.com/v1.0/myorg'

# 1. Find domain ID via Power BI admin domains
$domainId = $null
try {
  $domainsResponse = Invoke-RestMethod -Uri "$apiPbiRoot/admin/domains" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  if ($domainsResponse.domains) {
    $d = $domainsResponse.domains | Where-Object { $_.displayName -eq $FABRIC_DOMAIN_NAME }
    if ($d) { $domainId = $d.objectId }
  }
} catch { Warn 'Admin domains API not available. Cannot proceed with automatic assignment.'; Write-Host 'Manual assignment required: Fabric Admin Portal > Governance > Domains'; exit 0 }

if (-not $domainId) { Fail "Domain '$FABRIC_DOMAIN_NAME' not found. Create it first." }

# 2. Resolve capacity GUID
$capacityGuid = $null
$capName = ($FABRIC_CAPACITY_ID -split '/')[ -1 ]
try {
  $caps = Invoke-RestMethod -Uri "$apiPbiRoot/admin/capacities" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  if ($caps.value) {
    $match = $caps.value | Where-Object { ($_.displayName -eq $capName) -or ($_.name -eq $capName) }
    if ($match) { $capacityGuid = $match.id }
  }
} catch { }

if (-not $capacityGuid) { Fail "Cannot resolve capacity GUID from '$FABRIC_CAPACITY_ID'." }

# 3. Find the workspace ID
$workspaceId = $null
try {
  $groups = Invoke-RestMethod -Uri "$apiPbiRoot/groups?top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  if ($groups.value) {
    $g = $groups.value | Where-Object { $_.name -eq $FABRIC_WORKSPACE_NAME }
    if ($g) { $workspaceId = $g.id }
  }
} catch { }

if (-not $workspaceId) { Fail "Workspace '$FABRIC_WORKSPACE_NAME' not found." }

Log "Found workspace ID: $workspaceId"
Log "Found domain ID: $domainId"
Log "Found capacity GUID: $capacityGuid"

# 4. Assign workspaces by capacities
$assignPayload = @{ capacitiesIds = @($capacityGuid) } | ConvertTo-Json -Depth 4
$assignUrl = "$apiFabricRoot/admin/domains/$domainId/assignWorkspacesByCapacities"
try {
  $assignResp = Invoke-WebRequest -Uri $assignUrl -Headers @{ Authorization = "Bearer $fabricToken"; 'Content-Type' = 'application/json' } -Method Post -Body $assignPayload -UseBasicParsing -ErrorAction Stop
  if ($assignResp.StatusCode -in 200..299) { Log "Successfully assigned workspaces on capacity '$FABRIC_CAPACITY_NAME' to domain '$FABRIC_DOMAIN_NAME' (HTTP $($assignResp.StatusCode))." }
  else { Warn "Domain assignment failed (HTTP $($assignResp.StatusCode))."; exit 1 }
} catch {
  Warn "Domain assignment failed: $_"; exit 1
}

Log 'Domain assignment complete.'
