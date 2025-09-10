#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Clean up specific Fabric workspaces by removing content first, then deleting the workspace.
.DESCRIPTION
  Focuses on workspaces that can actually be deleted (not in "Removing" state).
.PARAMETER WorkspacePattern
  Pattern to match workspace names (e.g., "PersonalWorkspace*")
.PARAMETER DryRun
  If true, only shows what would be deleted without actually doing it.
#>

[CmdletBinding()]
param(
  [string]$WorkspacePattern = "PersonalWorkspace*",
  [switch]$DryRun = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[workspace-cleanup] $m" -ForegroundColor Green }
function Warn([string]$m){ Write-Warning "[workspace-cleanup] $m" }
function Fail([string]$m){ Write-Error "[workspace-cleanup] $m"; exit 1 }

# Get tokens
try { 
  $powerBIToken = & az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 
  $fabricToken = & az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
} catch { 
  Fail 'Unable to obtain API tokens (az login as Fabric admin required)' 
}

$apiRoot = 'https://api.powerbi.com/v1.0/myorg'
$fabricApiRoot = 'https://api.fabric.microsoft.com/v1'

Log "Targeting workspaces matching: $WorkspacePattern"
if ($DryRun) { Log "DRY RUN MODE - No actual deletions will occur" }

# Get workspaces matching pattern
try {
  $workspacesResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups?%24top=5000" -Headers @{ Authorization = "Bearer $powerBIToken" } -Method Get
  $targetWorkspaces = $workspacesResponse.value | Where-Object { 
    $_.name -like $WorkspacePattern -and 
    $_.state -eq 'Active' -and
    $_.type -eq 'PersonalGroup'
  }
  
  Log "Found $($targetWorkspaces.Count) workspaces to process"
} catch {
  Fail "Failed to fetch workspaces: $_"
}

if ($targetWorkspaces.Count -eq 0) {
  Log "No workspaces found matching pattern '$WorkspacePattern'"
  exit 0
}

# Process each workspace
foreach ($workspace in $targetWorkspaces) {
  Log ""
  Log "🔧 Processing workspace: $($workspace.name)"
  Log "   ID: $($workspace.id)"
  
  # Step 1: Try to clean up content first
  try {
    Log "   📋 Checking workspace content..."
    $itemsResponse = Invoke-RestMethod -Uri "$fabricApiRoot/workspaces/$($workspace.id)/items" -Headers @{ Authorization = "Bearer $fabricToken" } -Method Get -ErrorAction SilentlyContinue
    
    if ($itemsResponse.value -and $itemsResponse.value.Count -gt 0) {
      Log "   📦 Found $($itemsResponse.value.Count) items in workspace"
      
      if (-not $DryRun) {
        Log "   🧹 Attempting to delete workspace content..."
        foreach ($item in $itemsResponse.value) {
          try {
            Log "      Deleting $($item.type): $($item.displayName)"
            Invoke-RestMethod -Uri "$fabricApiRoot/workspaces/$($workspace.id)/items/$($item.id)" -Headers @{ Authorization = "Bearer $fabricToken" } -Method Delete -ErrorAction Stop
          } catch {
            Warn "      Failed to delete $($item.displayName): $_"
          }
        }
      } else {
        foreach ($item in $itemsResponse.value) {
          Log "      Would delete $($item.type): $($item.displayName)"
        }
      }
    } else {
      Log "   ✅ No content found in workspace"
    }
  } catch {
    Warn "   ⚠️  Could not access workspace content: $_"
  }
  
  # Step 2: Try to delete datasets via Power BI API
  try {
    $datasetsResponse = Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/datasets" -Headers @{ Authorization = "Bearer $powerBIToken" } -Method Get -ErrorAction SilentlyContinue
    
    if ($datasetsResponse.value -and $datasetsResponse.value.Count -gt 0) {
      Log "   📊 Found $($datasetsResponse.value.Count) datasets"
      
      if (-not $DryRun) {
        foreach ($dataset in $datasetsResponse.value) {
          try {
            Log "      Deleting dataset: $($dataset.name)"
            Invoke-RestMethod -Uri "$apiRoot/admin/groups/$($workspace.id)/datasets/$($dataset.id)" -Headers @{ Authorization = "Bearer $powerBIToken" } -Method Delete -ErrorAction Stop
          } catch {
            Warn "      Failed to delete dataset $($dataset.name): $_"
          }
        }
      } else {
        foreach ($dataset in $datasetsResponse.value) {
          Log "      Would delete dataset: $($dataset.name)"
        }
      }
    }
  } catch {
    Warn "   ⚠️  Could not access datasets: $_"
  }
  
  # Step 3: Try to delete the workspace
  if (-not $DryRun) {
    Log "   🗑️  Attempting to delete workspace..."
    try {
      Invoke-RestMethod -Uri "$fabricApiRoot/workspaces/$($workspace.id)" -Headers @{ Authorization = "Bearer $fabricToken" } -Method Delete -ErrorAction Stop
      Log "   ✅ Successfully deleted workspace: $($workspace.name)"
    } catch {
      if ($_.Exception.Response.StatusCode -eq 404) {
        Log "   ✅ Workspace already deleted: $($workspace.name)"
      } else {
        Warn "   ❌ Failed to delete workspace: $_"
        Warn "   💡 Try deleting manually from Fabric portal"
      }
    }
  } else {
    Log "   🗑️  Would attempt to delete workspace"
  }
}

Log ""
if ($DryRun) {
  Log "🎯 DRY RUN COMPLETED - No actual changes made"
  Log "Run without -DryRun to perform actual deletions"
} else {
  Log "✅ Workspace cleanup completed!"
}

Log ""
Log "💡 For workspaces stuck in 'Removing' state:"
Log "   - PersonalWorkspace swan-workspace1"  
Log "   - PersonalWorkspace swantest-ws4"
Log "   These require Microsoft support ticket to resolve."
