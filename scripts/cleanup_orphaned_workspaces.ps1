<#
.SYNOPSIS
  List and optionally delete orphaned Fabric workspaces (workspaces with no admin users).
.DESCRIPTION
  Uses Fabric/Power BI admin APIs to identify workspaces with no admin users and optionally delete them.
.PARAMETER DryRun
  If true (default), only lists orphaned workspaces without deleting them.
.PARAMETER Delete
  If true, actually deletes the orphaned workspaces. Use with caution!
#>

[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Delete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[cleanup-workspaces] $m" }
function Warn([string]$m){ Write-Warning "[cleanup-workspaces] $m" }
function Fail([string]$m){ Write-Error "[cleanup-workspaces] $m"; exit 1 }

# Get Power BI API token for admin operations
try { 
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
} catch { 
  Fail 'Unable to obtain Power BI API token (az login as Fabric admin required)' 
}

if (-not $accessToken) { Fail 'No access token obtained' }

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'
$fabricApiRoot = 'https://api.fabric.microsoft.com/v1'

Log "Fetching all workspaces from tenant..."

# Get all workspaces using admin API
try {
  $workspacesResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups?%24top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  $allWorkspaces = $workspacesResponse.value
  Log "Found $($allWorkspaces.Count) total workspaces"
} catch {
  Fail "Failed to fetch workspaces: $_"
}

# Identify orphaned workspaces (no admin users)
$orphanedWorkspaces = @()
$processedCount = 0

foreach ($workspace in $allWorkspaces) {
  $processedCount++
  Write-Progress -Activity "Checking workspaces" -Status "Processing $($workspace.name)" -PercentComplete (($processedCount / $allWorkspaces.Count) * 100)
  
  try {
    # Get workspace users
    $usersResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/users" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    
    # Check if there are any admin users
    $adminUsers = $usersResponse.value | Where-Object { $_.groupUserAccessRight -eq 'Admin' }
    
    if (-not $adminUsers -or $adminUsers.Count -eq 0) {
      $orphanedWorkspaces += [PSCustomObject]@{
        Id = $workspace.id
        Name = $workspace.name
        State = $workspace.state
        Type = $workspace.type
        CapacityId = $workspace.capacityId
        IsOnDedicatedCapacity = $workspace.isOnDedicatedCapacity
        UserCount = $usersResponse.value.Count
        AdminCount = 0
      }
      Log "Found orphaned workspace: $($workspace.name) (ID: $($workspace.id))"
    }
  } catch {
    Warn "Failed to get users for workspace $($workspace.name): $_"
  }
}

Write-Progress -Activity "Checking workspaces" -Completed

Log "Found $($orphanedWorkspaces.Count) orphaned workspaces (no admin users)"

if ($orphanedWorkspaces.Count -eq 0) {
  Log "No orphaned workspaces found. All workspaces have admin users."
  exit 0
}

# Display orphaned workspaces
Log "Orphaned workspaces:"
$orphanedWorkspaces | ForEach-Object {
  Log "  - Name: $($_.Name)"
  Log "    ID: $($_.Id)"
  Log "    State: $($_.State)"
  Log "    Type: $($_.Type)"
  Log "    On Dedicated Capacity: $($_.IsOnDedicatedCapacity)"
  Log "    Capacity ID: $($_.CapacityId)"
  Log "    Total Users: $($_.UserCount)"
  Log ""
}

if (-not $Delete -or $DryRun) {
  Log "DRY RUN MODE: No workspaces will be deleted."
  Log "To actually delete these workspaces, run with -Delete (without -DryRun)"
  exit 0
}

if ($Delete) {
  Log "WARNING: About to delete $($orphanedWorkspaces.Count) orphaned workspaces!"
  Log "This action cannot be undone!"
  
  $confirmation = Read-Host "Type 'DELETE' to confirm deletion of all orphaned workspaces"
  if ($confirmation -ne 'DELETE') {
    Log "Deletion cancelled."
    exit 0
  }
  
  $deletedCount = 0
  $failedCount = 0
  
  foreach ($workspace in $orphanedWorkspaces) {
    try {
      Log "Deleting workspace: $($workspace.Name) ($($workspace.Id))"
      
      # Use Fabric API to delete workspace
      $deleteResponse = Invoke-WebRequest -Uri "$fabricApiRoot/workspaces/$($workspace.Id)" -Headers @{ Authorization = "Bearer $accessToken" } -Method Delete -UseBasicParsing -ErrorAction Stop
      
      if ($deleteResponse.StatusCode -eq 200 -or $deleteResponse.StatusCode -eq 204) {
        Log "Successfully deleted workspace: $($workspace.Name)"
        $deletedCount++
      } else {
        Warn "Unexpected response when deleting $($workspace.Name): $($deleteResponse.StatusCode)"
        $failedCount++
      }
    } catch {
      Warn "Failed to delete workspace $($workspace.Name): $_"
      $failedCount++
    }
    
    # Add small delay to avoid rate limiting
    Start-Sleep -Seconds 1
  }
  
  Log "Deletion summary: $deletedCount deleted, $failedCount failed"
} else {
  Log "Use -Delete to actually delete the orphaned workspaces."
}
