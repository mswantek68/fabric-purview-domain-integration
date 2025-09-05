<#
.SYNOPSIS
  Grant AI Search service managed identity access to Fabric workspace
.DESCRIPTION
  Adds the AI Search service's system-assigned managed identity as a Viewer to the Fabric workspace.
  This is required for OneLake indexer to work.
.PARAMETER AISearchName
  The name of the AI Search service
.PARAMETER WorkspaceId
  The Fabric workspace ID
.PARAMETER AISearchResourceGroup
  The resource group containing the AI Search service
.PARAMETER AISearchSubscriptionId
  The subscription ID containing the AI Search service
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$AISearchName,
  [Parameter(Mandatory=$true)][string]$WorkspaceId,
  [string]$AISearchResourceGroup,
  [string]$AISearchSubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[fabric-workspace-access] $m" }
function Warn([string]$m){ Write-Warning "[fabric-workspace-access] $m" }
function Fail([string]$m){ Write-Error "[fabric-workspace-access] $m"; exit 1 }

# Get AI Search configuration from azd outputs if not provided
if (-not $AISearchResourceGroup) { $AISearchResourceGroup = 'AI_Related' }
if (-not $AISearchSubscriptionId) { $AISearchSubscriptionId = '48ab3756-f962-40a8-b0cf-b33ddae744bb' }

if (Test-Path '/tmp/azd-outputs.json') {
  try {
    $outputs = Get-Content '/tmp/azd-outputs.json' | ConvertFrom-Json
    if ($outputs.aiSearchResourceGroup) { $AISearchResourceGroup = $outputs.aiSearchResourceGroup.value }
    if ($outputs.aiSearchSubscriptionId) { $AISearchSubscriptionId = $outputs.aiSearchSubscriptionId.value }
  } catch {
    # Use defaults
  }
}

Log "Getting AI Search service managed identity..."
Log "AI Search: $AISearchName"
Log "Resource Group: $AISearchResourceGroup"
Log "Subscription: $AISearchSubscriptionId"
Log "Workspace ID: $WorkspaceId"

# Get the AI Search service's system-assigned managed identity principal ID
try {
  $searchService = & az search service show --name $AISearchName --resource-group $AISearchResourceGroup --subscription $AISearchSubscriptionId --query "{principalId:identity.principalId,tenantId:identity.tenantId}" -o json | ConvertFrom-Json
  
  if (-not $searchService.principalId) {
    Fail "AI Search service '$AISearchName' does not have a system-assigned managed identity enabled"
  }
  
  $principalId = $searchService.principalId
  Log "AI Search managed identity principal ID: $principalId"
  
} catch {
  Fail "Failed to get AI Search service information: $($_.Exception.Message)"
}

# Get Fabric API access token
try {
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
  if (-not $accessToken) { Fail "Could not acquire Fabric API access token" }
} catch {
  Fail "Failed to get Fabric API token: $($_.Exception.Message)"
}

$apiRoot = 'https://api.fabric.microsoft.com/v1'

# Check if the principal is already assigned to the workspace
Log "Checking existing workspace role assignments..."
try {
  $existingAssignments = Invoke-RestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/roleAssignments" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  
  $existingAssignment = $existingAssignments.value | Where-Object { $_.principal.id -eq $principalId }
  
  if ($existingAssignment) {
    Log "AI Search managed identity already has role '$($existingAssignment.role)' in the workspace"
    Log "OneLake indexer should work with this assignment"
    exit 0
  }
  
} catch {
  Warn "Could not check existing role assignments: $($_.Exception.Message)"
}

# Add the AI Search managed identity as Viewer to the workspace
Log "Adding AI Search managed identity as Viewer to Fabric workspace..."

$roleAssignmentBody = @{
  principal = @{
    id = $principalId
    type = "ServicePrincipal"
  }
  role = "Viewer"
} | ConvertTo-Json -Depth 3

try {
  $response = Invoke-RestMethod -Uri "$apiRoot/workspaces/$WorkspaceId/roleAssignments" -Headers @{ 
    Authorization = "Bearer $accessToken"
    'Content-Type' = 'application/json'
  } -Method Post -Body $roleAssignmentBody -ErrorAction Stop
  
  Log "Successfully added AI Search managed identity as Viewer to workspace"
  Log "Principal ID: $principalId"
  Log "Role: Viewer"
  Log "OneLake indexer should now work"
  
} catch {
  if ($_.Exception.Response.StatusCode -eq 409) {
    Log "Role assignment already exists (conflict response)"
  } else {
    Fail "Failed to add role assignment: $($_.Exception.Message)"
  }
}

Log "Fabric workspace access configuration completed"
