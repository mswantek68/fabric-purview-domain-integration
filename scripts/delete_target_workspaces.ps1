<#
.SYNOPSIS
  Delete specific Fabric workspaces by name pattern (e.g., swan-fabworkspace*).
.DESCRIPTION
  Uses Fabric admin APIs to find and delete workspaces matching a pattern when portal deletion fails.
.PARAMETER NamePattern
  Pattern to match workspace names (supports wildcards). Default: 'swan-fabworkspace*'
.PARAMETER Delete
  If true, actually deletes the matching workspaces. Otherwise just lists them.
#>

[CmdletBinding()]
param(
  [string]$NamePattern = 'swan-fabworkspace*',
  [switch]$Delete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[delete-workspaces] $m" }
function Warn([string]$m){ Write-Warning "[delete-workspaces] $m" }
function Fail([string]$m){ Write-Error "[delete-workspaces] $m"; exit 1 }

# Get Power BI API token for admin operations
try { 
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
} catch { 
  Fail 'Unable to obtain Power BI API token (az login as Fabric admin required)' 
}

if (-not $accessToken) { Fail 'No access token obtained' }

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'
$fabricApiRoot = 'https://api.fabric.microsoft.com/v1'

Log "Searching for workspaces matching pattern: '$NamePattern'"

# Get all workspaces using admin API
try {
  $workspacesResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups?%24top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  $allWorkspaces = $workspacesResponse.value
  Log "Found $($allWorkspaces.Count) total workspaces"
} catch {
  Fail "Failed to fetch workspaces: $_"
}

# Find matching workspaces
$matchingWorkspaces = $allWorkspaces | Where-Object { $_.name -like $NamePattern }

if ($matchingWorkspaces.Count -eq 0) {
  Log "No workspaces found matching pattern '$NamePattern'"
  exit 0
}

Log "Found $($matchingWorkspaces.Count) workspaces matching pattern:"
foreach ($workspace in $matchingWorkspaces) {
  Log "  - $($workspace.name) (ID: $($workspace.id), State: $($workspace.state))"
  
  # Try to get capacity info
  if ($workspace.PSObject.Properties['capacityId'] -and $workspace.capacityId) {
    Log "    Capacity ID: $($workspace.capacityId)"
  } else {
    Log "    Capacity: Shared/None"
  }
  
  # Try to get user count
  try {
    $usersResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/users" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction SilentlyContinue
    $adminUsers = $usersResponse.value | Where-Object { $_.groupUserAccessRight -eq 'Admin' }
    Log "    Users: $($usersResponse.value.Count) total, $($adminUsers.Count) admins"
  } catch {
    Log "    Users: Unable to query"
  }
}

if (-not $Delete) {
  Log ""
  Log "DRY RUN MODE: No workspaces will be deleted."
  Log "To delete these workspaces, run with -Delete parameter"
  Log "Command: pwsh -Command `"./scripts/delete_target_workspaces.ps1 -NamePattern '$NamePattern' -Delete`""
  exit 0
}

Log ""
Log "WARNING: About to delete $($matchingWorkspaces.Count) workspaces!"
Log "This action cannot be undone!"

$workspaceNames = $matchingWorkspaces | ForEach-Object { $_.name }
Log "Workspaces to delete: $($workspaceNames -join ', ')"

$confirmation = Read-Host "Type 'DELETE' to confirm deletion"
if ($confirmation -ne 'DELETE') {
  Log "Deletion cancelled."
  exit 0
}

$deletedCount = 0
$failedCount = 0

foreach ($workspace in $matchingWorkspaces) {
  Log "Attempting to delete workspace: $($workspace.name) ($($workspace.id))"
  
  # Try multiple deletion methods
  $deleted = $false
  
  # Method 1: Try Fabric API deletion
  try {
    Log "  Trying Fabric API deletion..."
    $deleteResponse = Invoke-WebRequest -Uri "$fabricApiRoot/workspaces/$($workspace.id)" -Headers @{ Authorization = "Bearer $accessToken" } -Method Delete -UseBasicParsing -ErrorAction Stop
    
    if ($deleteResponse.StatusCode -eq 200 -or $deleteResponse.StatusCode -eq 204) {
      Log "  Successfully deleted via Fabric API: $($workspace.name)"
      $deletedCount++
      $deleted = $true
    }
  } catch {
    Log "  Fabric API deletion failed: $($_.Exception.Message)"
  }
  
  # Method 2: Try Power BI admin API deletion if Fabric API failed
  if (-not $deleted) {
    try {
      Log "  Trying Power BI admin API deletion..."
      $deleteResponse = Invoke-WebRequest -Uri "$apiRoot/admin/groups/$($workspace.id)" -Headers @{ Authorization = "Bearer $accessToken" } -Method Delete -UseBasicParsing -ErrorAction Stop
      
      if ($deleteResponse.StatusCode -eq 200 -or $deleteResponse.StatusCode -eq 204) {
        Log "  Successfully deleted via Power BI admin API: $($workspace.name)"
        $deletedCount++
        $deleted = $true
      }
    } catch {
      Log "  Power BI admin API deletion failed: $($_.Exception.Message)"
    }
  }
  
  # Method 3: Try regular Power BI API deletion if admin API failed
  if (-not $deleted) {
    try {
      Log "  Trying regular Power BI API deletion..."
      $deleteResponse = Invoke-WebRequest -Uri "$apiRoot/groups/$($workspace.id)" -Headers @{ Authorization = "Bearer $accessToken" } -Method Delete -UseBasicParsing -ErrorAction Stop
      
      if ($deleteResponse.StatusCode -eq 200 -or $deleteResponse.StatusCode -eq 204) {
        Log "  Successfully deleted via Power BI API: $($workspace.name)"
        $deletedCount++
        $deleted = $true
      }
    } catch {
      Log "  Regular Power BI API deletion failed: $($_.Exception.Message)"
    }
  }
  
  if (-not $deleted) {
    Warn "Failed to delete workspace: $($workspace.name) - all methods failed"
    $failedCount++
    
    # Try to provide helpful error information
    try {
      $workspaceDetails = Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
      Log "  Workspace details: State=$($workspaceDetails.state), Type=$($workspaceDetails.type)"
    } catch {
      Log "  Could not retrieve workspace details for troubleshooting"
    }
  }
  
  # Small delay to avoid rate limiting
  Start-Sleep -Seconds 2
}

Log ""
Log "Deletion Summary:"
Log "================="
Log "Successfully deleted: $deletedCount workspaces"
Log "Failed to delete: $failedCount workspaces"

if ($failedCount -gt 0) {
  Log ""
  Log "For workspaces that failed to delete, you may need to:"
  Log "1. Check if they contain critical content that prevents deletion"
  Log "2. Remove all content first (datasets, reports, etc.)"
  Log "3. Ensure you have proper admin permissions"
  Log "4. Try again later if there are temporary API issues"
}
