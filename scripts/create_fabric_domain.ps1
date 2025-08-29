<#
.SYNOPSIS
  Create a Fabric domain (PowerShell)
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[fabric-domain] $m" }
function Warn([string]$m){ Write-Warning "[fabric-domain] $m" }
function Fail([string]$m){ Write-Error "[fabric-domain] $m"; exit 1 }

# Resolve domain/workspace via AZURE_OUTPUTS_JSON or azd env
$domainName = $env:desiredFabricDomainName
$workspaceName = $env:desiredFabricWorkspaceName
if (-not $domainName -and $env:AZURE_OUTPUTS_JSON) { try { $domainName = ($env:AZURE_OUTPUTS_JSON | ConvertFrom-Json).desiredFabricDomainName.value } catch {} }
if (-not $workspaceName -and $env:AZURE_OUTPUTS_JSON) { try { $workspaceName = ($env:AZURE_OUTPUTS_JSON | ConvertFrom-Json).desiredFabricWorkspaceName.value } catch {} }

if (-not $domainName) { Fail 'FABRIC_DOMAIN_NAME unresolved (no outputs/env/bicep).' }

# Acquire tokens
try { $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv } catch { $accessToken = $null }
try { $fabricToken = & az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv } catch { $fabricToken = $null }
if (-not $accessToken) { Fail 'Unable to obtain Power BI API token (az login as Fabric admin).' }
if (-not $fabricToken) { Fail 'Unable to obtain Fabric API token (az login as Fabric admin).' }

$apiFabricRoot = 'https://api.fabric.microsoft.com/v1'

# Check if domain exists
try { $domains = Invoke-RestMethod -Uri "$apiFabricRoot/governance/domains" -Headers @{ Authorization = "Bearer $fabricToken" } -Method Get -ErrorAction Stop } catch { $domains = $null }
$domainId = $null
if ($domains -and $domains.value) { $d = $domains.value | Where-Object { $_.displayName -eq $domainName -or $_.name -eq $domainName }; if ($d) { $domainId = $d.id } }

if (-not $domainId) {
  Log "Creating domain '$domainName'"
  try {
    $payload = @{ displayName = $domainName } | ConvertTo-Json -Depth 4
    $resp = Invoke-WebRequest -Uri "$apiFabricRoot/admin/domains" -Method Post -Headers @{ Authorization = "Bearer $fabricToken"; 'Content-Type' = 'application/json' } -Body $payload -UseBasicParsing -ErrorAction Stop
    $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    $domainId = $body.id
    Log "Created domain id: $domainId"
  } catch { Warn "Domain creation failed: $_.Exception.Message"; exit 0 }
} else { Log "Domain '$domainName' already exists (id=$domainId)" }

Log 'Domain provisioning script complete.'
exit 0
