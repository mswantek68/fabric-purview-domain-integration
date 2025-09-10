#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Delete specific Fabric workspaces that are not associated with a capacity.
.DESCRIPTION
  Targets specific workspace names and removes their content before deleting them.
.PARAMETER DryRun
  If true, only shows what would be deleted without actually doing it.
#>

[CmdletBinding()]
param(
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[specific-cleanup] $m" -ForegroundColor Green }
function Warn([string]$m){ Write-Warning "[specific-cleanup] $m" }
function Fail([string]$m){ Write-Error "[specific-cleanup] $m"; exit 1 }

# Target workspace names
$targetWorkspaceNames = @(
  'Zava-Marketing-ws',
  'swantest-ws1', 
  'swantest-ws14',
  'swantest-ws04'
)

Log "Targeting specific workspaces: $($targetWorkspaceNames -join ', ')"
if ($DryRun) { 
  Log "DRY RUN MODE - No actual deletions will occur" 
} else {
  Log "LIVE MODE - Will actually delete workspaces and content!"
}

# Get tokens
try { 
  $powerBIToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
  $fabricToken = & az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
} catch { 
  Fail 'Unable to obtain API tokens (az login as Fabric admin required)' 
}

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'
$fabricApiRoot = 'https://api.fabric.microsoft.com/v1'

# Get the specific workspaces
try {
  $workspacesResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups?%24top=5000" -Headers @{ Authorization = "Bearer $powerBIToken" } -Method Get
  $targetWorkspaces = $workspacesResponse.value | Where-Object { $_.name -in $targetWorkspaceNames }
  
  Log "Found $($targetWorkspaces.Count) out of $($targetWorkspaceNames.Count) target workspaces"
  
  # Show which ones were found
  foreach ($name in $targetWorkspaceNames) {
    $found = $targetWorkspaces | Where-Object { $_.name -eq $name }
    if ($found) {
      $capacityInfo = if ($found.isOnDedicatedCapacity) { "On Capacity" } else { "Shared Capacity" }
      Log "  ✅ Found: $name ($($found.state), $capacityInfo)"
    } else {
      Warn "  ❌ Not found: $name"
    }
  }
} catch {
  Fail "Failed to fetch workspaces: $_"
}

if ($targetWorkspaces.Count -eq 0) {
  Log "No target workspaces found. Nothing to do."
  exit 0
}

# Process each workspace
foreach ($workspace in $targetWorkspaces) {
  Log ""
  Log "🔧 Processing workspace: $($workspace.name)"
  Log "   ID: $($workspace.id)"
  Log "   State: $($workspace.state)"
  Log "   Capacity: $(if ($workspace.isOnDedicatedCapacity) { 'Dedicated' } else { 'Shared' })"
  
  # Step 1: Get and delete Fabric items (lakehouses, notebooks, etc.)
  try {
    Log "   📋 Checking Fabric items..."
    $itemsResponse = Invoke-RestMethod -Uri "$fabricApiRoot/workspaces/$($workspace.id)/items" -Headers @{ Authorization = "Bearer $fabricToken" } -Method Get -ErrorAction SilentlyContinue
    
    if ($itemsResponse.value -and $itemsResponse.value.Count -gt 0) {
      Log "   📦 Found $($itemsResponse.value.Count) Fabric items"
      
      foreach ($item in $itemsResponse.value) {
        if ($DryRun) {
          Log "      Would delete $($item.type): $($item.displayName)"
        } else {
          try {
            Log "      Deleting $($item.type): $($item.displayName)"
            Invoke-RestMethod -Uri "$fabricApiRoot/workspaces/$($workspace.id)/items/$($item.id)" -Headers @{ Authorization = "Bearer $fabricToken" } -Method Delete -ErrorAction Stop
            Log "      ✅ Deleted: $($item.displayName)"
          } catch {
            Warn "      ❌ Failed to delete $($item.displayName): $_"
          }
        }
      }
    } else {
      Log "   ✅ No Fabric items found"
    }
  } catch {
    Warn "   ⚠️  Could not access Fabric items: $_"
  }
  
  # Step 2: Get and delete Power BI datasets
  try {
    Log "   📊 Checking Power BI datasets..."
    $datasetsResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/datasets" -Headers @{ Authorization = "Bearer $powerBIToken" } -Method Get -ErrorAction SilentlyContinue
    
    if ($datasetsResponse.value -and $datasetsResponse.value.Count -gt 0) {
      Log "   📈 Found $($datasetsResponse.value.Count) datasets"
      
      foreach ($dataset in $datasetsResponse.value) {
        if ($DryRun) {
          Log "      Would delete dataset: $($dataset.name)"
        } else {
          try {
            Log "      Deleting dataset: $($dataset.name)"
            Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/datasets/$($dataset.id)" -Headers @{ Authorization = "Bearer $powerBIToken" } -Method Delete -ErrorAction Stop
            Log "      ✅ Deleted dataset: $($dataset.name)"
          } catch {
            Warn "      ❌ Failed to delete dataset $($dataset.name): $_"
          }
        }
      }
    } else {
      Log "   ✅ No datasets found"
    }
  } catch {
    Warn "   ⚠️  Could not access datasets: $_"
  }
  
  # Step 3: Get and delete Power BI reports
  try {
    Log "   📋 Checking Power BI reports..."
    $reportsResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/reports" -Headers @{ Authorization = "Bearer $powerBIToken" } -Method Get -ErrorAction SilentlyContinue
    
    if ($reportsResponse.value -and $reportsResponse.value.Count -gt 0) {
      Log "   📄 Found $($reportsResponse.value.Count) reports"
      
      foreach ($report in $reportsResponse.value) {
        if ($DryRun) {
          Log "      Would delete report: $($report.name)"
        } else {
          try {
            Log "      Deleting report: $($report.name)"
            Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/reports/$($report.id)" -Headers @{ Authorization = "Bearer $powerBIToken" } -Method Delete -ErrorAction Stop
            Log "      ✅ Deleted report: $($report.name)"
          } catch {
            Warn "      ❌ Failed to delete report $($report.name): $_"
          }
        }
      }
    } else {
      Log "   ✅ No reports found"
    }
  } catch {
    Warn "   ⚠️  Could not access reports: $_"
  }
  
  # Step 4: Delete the workspace itself
  if ($DryRun) {
    Log "   🗑️  Would delete workspace: $($workspace.name)"
  } else {
    Log "   🗑️  Deleting workspace: $($workspace.name)"
    try {
      Invoke-RestMethod -Uri "$fabricApiRoot/workspaces/$($workspace.id)" -Headers @{ Authorization = "Bearer $fabricToken" } -Method Delete -ErrorAction Stop
      Log "   ✅ Successfully deleted workspace: $($workspace.name)"
    } catch {
      if ($_.Exception.Response.StatusCode -eq 404) {
        Log "   ✅ Workspace already deleted: $($workspace.name)"
      } else {
        Warn "   ❌ Failed to delete workspace: $_"
        Warn "   💡 You may need to delete it manually from the Fabric portal"
      }
    }
  }
  
  # Add a small delay between workspace deletions
  if (-not $DryRun) {
    Start-Sleep -Seconds 2
  }
}

Log ""
if ($DryRun) {
  Log "🎯 DRY RUN COMPLETED - No actual changes made"
  Log "Run without -DryRun to perform actual deletions"
  Log ""
  Log "To execute the deletions, run:"
  Log "pwsh ./scripts/Fabric_Purview_Automation/delete_specific_workspaces.ps1"
} else {
  Log "✅ Specific workspace cleanup completed!"
}

Log ""
Log "Workspaces targeted for deletion:"
foreach ($name in $targetWorkspaceNames) {
  Log "  - $name"
}
