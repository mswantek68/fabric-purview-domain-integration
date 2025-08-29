<#
.SYNOPSIS
  List all workspaces in the Fabric tenant with details.
.DESCRIPTION
  Uses Fabric/Power BI admin APIs to list all workspaces with capacity assignments and user counts.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[list-workspaces] $m" }
function Warn([string]$m){ Write-Warning "[list-workspaces] $m" }
function Fail([string]$m){ Write-Error "[list-workspaces] $m"; exit 1 }

# Get Power BI API token for admin operations
try { 
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
} catch { 
  Fail 'Unable to obtain Power BI API token (az login as Fabric admin required)' 
}

if (-not $accessToken) { Fail 'No access token obtained' }

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'

Log "Fetching all workspaces from tenant..."

# Get all workspaces using admin API
try {
  $workspacesResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups?%24top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  $allWorkspaces = $workspacesResponse.value
  Log "Found $($allWorkspaces.Count) total workspaces"
} catch {
  Fail "Failed to fetch workspaces: $_"
}

# Get capacities for reference
try {
  $capacitiesResponse = Invoke-RestMethod -Uri "$apiRoot/admin/capacities" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  $capacities = @{}
  $capacitiesResponse.value | ForEach-Object { $capacities[$_.id] = $_ }
} catch {
  Warn "Failed to fetch capacities: $_"
  $capacities = @{}
}

Log ""
Log "Workspace Details:"
Log "=================="

$workspaceDetails = @()

foreach ($workspace in $allWorkspaces) {
  $adminCount = 0
  $userCount = 0
  $usersInfo = "Unable to query"
  
  try {
    # Get workspace users
    $usersResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/users" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    $userCount = $usersResponse.value.Count
    $adminUsers = $usersResponse.value | Where-Object { $_.groupUserAccessRight -eq 'Admin' }
    $adminCount = if ($adminUsers) { $adminUsers.Count } else { 0 }
    $usersInfo = "Total: $userCount, Admins: $adminCount"
  } catch {
    # Personal workspaces and some system workspaces don't allow user queries
    $usersInfo = "Private/System workspace"
  }
  
  $capacityInfo = "None (Shared)"
  if ($workspace.PSObject.Properties['capacityId'] -and $workspace.capacityId -and $capacities[$workspace.capacityId]) {
    $cap = $capacities[$workspace.capacityId]
    $capacityInfo = "$($cap.displayName) ($($cap.sku), $($cap.state))"
  } elseif ($workspace.PSObject.Properties['capacityId'] -and $workspace.capacityId) {
    $capacityInfo = "Capacity ID: $($workspace.capacityId)"
  }
  
  $details = [PSCustomObject]@{
    Name = $workspace.name
    Id = $workspace.id
    State = $workspace.state
    Type = $workspace.type
    Users = $usersInfo
    AdminCount = $adminCount
    Capacity = $capacityInfo
    IsOnDedicatedCapacity = if ($workspace.PSObject.Properties['isOnDedicatedCapacity']) { $workspace.isOnDedicatedCapacity } else { $false }
  }
  
  $workspaceDetails += $details
  
  Log "Name: $($workspace.name)"
  Log "  ID: $($workspace.id)"
  Log "  State: $($workspace.state)"
  Log "  Type: $($workspace.type)"
  Log "  Users: $usersInfo"
  Log "  Capacity: $capacityInfo"
  Log "  On Dedicated: $(if ($workspace.PSObject.Properties['isOnDedicatedCapacity']) { $workspace.isOnDedicatedCapacity } else { 'False' })"
  Log ""
}

# Summary
Log "Summary:"
Log "========"
Log "Total workspaces: $($allWorkspaces.Count)"
Log "On dedicated capacity: $(($workspaceDetails | Where-Object { $_.IsOnDedicatedCapacity }).Count)"
Log "On shared capacity: $(($workspaceDetails | Where-Object { -not $_.IsOnDedicatedCapacity }).Count)"
Log "Potentially orphaned (0 admins): $(($workspaceDetails | Where-Object { $_.AdminCount -eq 0 }).Count)"

# Export to CSV for easier analysis
$csvPath = "/tmp/fabric_workspaces.csv"
$workspaceDetails | Export-Csv -Path $csvPath -NoTypeInformation
Log "Detailed workspace information exported to: $csvPath"
