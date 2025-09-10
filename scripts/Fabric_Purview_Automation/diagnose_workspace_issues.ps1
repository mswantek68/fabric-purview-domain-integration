#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Diagnose Fabric workspace issues, especially those related to capacity removal.
.DESCRIPTION
  Analyzes workspace states to identify common deletion problems.
.PARAMETER WorkspaceName
  Optional specific workspace name to analyze. If not provided, analyzes all problematic workspaces.
#>

[CmdletBinding()]
param(
  [string]$WorkspaceName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[diagnose-workspaces] $m" }
function Warn([string]$m){ Write-Warning "[diagnose-workspaces] $m" }
function Fail([string]$m){ Write-Error "[diagnose-workspaces] $m"; exit 1 }

# Get Power BI API token
try { 
  $accessToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
} catch { 
  Fail 'Unable to obtain Power BI API token (az login as Fabric admin required)' 
}

if (-not $accessToken) { Fail 'No access token obtained' }

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'
$fabricApiRoot = 'https://api.fabric.microsoft.com/v1'

Log "Analyzing workspace issues..."

# Get all workspaces
try {
  $workspacesResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups?%24top=5000" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
  $allWorkspaces = $workspacesResponse.value
  Log "Found $($allWorkspaces.Count) total workspaces"
} catch {
  Fail "Failed to fetch workspaces: $_"
}

# Filter workspaces if specific name provided
if ($WorkspaceName) {
  $allWorkspaces = $allWorkspaces | Where-Object { $_.name -like "*$WorkspaceName*" }
  Log "Filtered to $($allWorkspaces.Count) workspaces matching '$WorkspaceName'"
}

$problemWorkspaces = @()

foreach ($workspace in $allWorkspaces) {
  $issues = @()
  $canDelete = $true
  
  # Check workspace state
  if ($workspace.state -ne 'Active') {
    $issues += "State: $($workspace.state) (not Active)"
    if ($workspace.state -eq 'Removing' -or $workspace.state -eq 'Deleted') {
      $canDelete = $false
    }
  }
  
  # Check capacity status
  $capacityId = if ($workspace.PSObject.Properties['capacityId']) { $workspace.capacityId } else { $null }
  
  if ($workspace.isOnDedicatedCapacity -and [string]::IsNullOrEmpty($capacityId)) {
    $issues += "Capacity conflict: marked as on dedicated capacity but no capacity ID"
    $canDelete = $false
  }
  
  if (-not $workspace.isOnDedicatedCapacity -and -not [string]::IsNullOrEmpty($capacityId)) {
    $issues += "Capacity conflict: has capacity ID but not marked as on dedicated capacity"
  }
  
  # Try to get workspace users
  $userIssues = $false
  $adminCount = 0
  try {
    $usersResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/users" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    $adminUsers = $usersResponse.value | Where-Object { $_.groupUserAccessRight -eq 'Admin' }
    $adminCount = if ($adminUsers) { $adminUsers.Count } else { 0 }
    
    if ($adminCount -eq 0) {
      $issues += "No admin users found"
    }
  } catch {
    $issues += "Cannot access user list: $($_.Exception.Message)"
    $userIssues = $true
    $canDelete = $false
  }
  
  # Try to get workspace content
  try {
    $contentResponse = Invoke-RestMethod -Uri "$fabricApiRoot/workspaces/$($workspace.id)/items" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    $itemCount = if ($contentResponse.value) { $contentResponse.value.Count } else { 0 }
    
    if ($itemCount -gt 0) {
      $issues += "Has $itemCount items that may prevent deletion"
    }
  } catch {
    $issues += "Cannot access workspace content: $($_.Exception.Message)"
  }
  
  # Check if workspace has datasets/reports
  try {
    $datasetsResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/datasets" -Headers @{ Authorization = "Bearer $accessToken" } -Method Get -ErrorAction Stop
    if ($datasetsResponse.value -and $datasetsResponse.value.Count -gt 0) {
      $issues += "Has $($datasetsResponse.value.Count) datasets"
    }
  } catch {
    # This might fail for some workspace types, which is OK
  }
  
  # Only include workspaces with issues
  if ($issues.Count -gt 0 -or -not $canDelete) {
    $problemWorkspaces += [PSCustomObject]@{
      Id = $workspace.id
      Name = $workspace.name
      State = $workspace.state
      Type = $workspace.type
      IsOnDedicatedCapacity = $workspace.isOnDedicatedCapacity
      CapacityId = $capacityId
      AdminCount = $adminCount
      Issues = $issues
      RecommendedAction = if ($canDelete) { 
        if ($issues -contains "No admin users found") { "Can be deleted as orphaned" }
        elseif ($issues.Count -eq 0) { "No issues found" }
        else { "Review and possibly delete" }
      } else { 
        "Cannot delete - resolve issues first" 
      }
    }
  }
}

Log "Found $($problemWorkspaces.Count) workspaces with potential issues"

if ($problemWorkspaces.Count -eq 0) {
  Log "No problematic workspaces found!"
  exit 0
}

# Display results
Log ""
Log "🔍 WORKSPACE ANALYSIS RESULTS"
Log "=============================="

foreach ($workspace in $problemWorkspaces) {
  Log ""
  Log "📋 Workspace: $($workspace.Name)"
  Log "   ID: $($workspace.Id)"
  Log "   State: $($workspace.State)"
  Log "   Type: $($workspace.Type)"
  Log "   On Dedicated Capacity: $($workspace.IsOnDedicatedCapacity)"
  Log "   Capacity ID: $($workspace.CapacityId)"
  Log "   Admin Count: $($workspace.AdminCount)"
  Log "   🚨 Issues:"
  
  if ($workspace.Issues.Count -eq 0) {
    Log "     (No specific issues detected)"
  } else {
    foreach ($issue in $workspace.Issues) {
      Log "     - $issue"
    }
  }
  
  Log "   💡 Recommended Action: $($workspace.RecommendedAction)"
}

# Provide specific guidance for common issues
Log ""
Log "🛠️  COMMON SOLUTIONS"
Log "==================="
Log ""
Log "For workspaces that can't be deleted after capacity removal:"
Log "1. 🔄 Try re-assigning to a capacity first, then remove properly"
Log "2. 🏠 Ensure workspace is moved to shared capacity before deletion"
Log "3. 🧹 Delete all content (datasets, reports, etc.) first"
Log "4. 👥 Verify you have admin permissions on the workspace"
Log ""
Log "For API access issues:"
Log "1. 🔑 Ensure you're logged in as a Fabric admin"
Log "2. 🎯 Try using the Fabric portal directly for stubborn workspaces"
Log "3. 📞 Contact Microsoft support for workspaces in 'Removing' state"
Log ""

# Offer to attempt fixes for specific common issues
if ($problemWorkspaces | Where-Object { $_.Issues -contains "No admin users found" }) {
  Log "Found workspaces with no admin users (truly orphaned)."
  $tryDelete = Read-Host "Attempt to delete orphaned workspaces? (y/N)"
  
  if ($tryDelete -eq 'y' -or $tryDelete -eq 'Y') {
    $orphaned = $problemWorkspaces | Where-Object { $_.Issues -contains "No admin users found" }
    
    foreach ($workspace in $orphaned) {
      Log "Attempting to delete orphaned workspace: $($workspace.Name)"
      try {
        $deleteResponse = Invoke-WebRequest -Uri "$fabricApiRoot/workspaces/$($workspace.Id)" -Headers @{ Authorization = "Bearer $accessToken" } -Method Delete -UseBasicParsing -ErrorAction Stop
        Log "✅ Successfully deleted: $($workspace.Name)"
      } catch {
        Warn "❌ Failed to delete $($workspace.Name): $_"
      }
    }
  }
}

Log ""
Log "✅ Workspace analysis completed!"
