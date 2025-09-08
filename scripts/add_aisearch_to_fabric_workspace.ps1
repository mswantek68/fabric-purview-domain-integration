#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Add AI Search managed identity to Fabric workspace
.DESCRIPTION
    This script adds the AI Search system-assigned managed identity to the Fabric workspace
    with appropriate permissions for OneLake access
#>

[CmdletBinding()]
param(
    [string]$WorkspaceId,
    [string]$AISearchName = "aisearchswan2",
    [string]$AISearchResourceGroup = "AI_Related"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Log([string]$m) { Write-Host "[add-aisearch-to-workspace] $m" -ForegroundColor Cyan }
function Success([string]$m) { Write-Host "[add-aisearch-to-workspace] $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "[add-aisearch-to-workspace] $m" -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host "[add-aisearch-to-workspace] $m" -ForegroundColor Red; exit 1 }

Log "=================================================================="
Log "Adding AI Search managed identity to Fabric workspace"
Log "=================================================================="

# Get workspace ID if not provided
if (-not $WorkspaceId) {
    if (Test-Path '/tmp/fabric_workspace.env') {
        Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
            if ($_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { 
                $script:WorkspaceId = $Matches[1].Trim().Trim('"')
            }
        }
    }
}

if (-not $script:WorkspaceId) {
    Fail "WorkspaceId not provided and not found in /tmp/fabric_workspace.env"
}

Log "Workspace ID: $script:WorkspaceId"
Log "AI Search: $AISearchName"

# Get AI Search managed identity principal ID
Log "Getting AI Search managed identity..."
try {
    $identity = az search service show --name $AISearchName --resource-group $AISearchResourceGroup --query "identity" | ConvertFrom-Json
    if (-not $identity -or -not $identity.principalId) {
        Fail "AI Search service does not have system-assigned managed identity enabled"
    }
    $principalId = $identity.principalId
    Log "AI Search Principal ID: $principalId"
} catch {
    Fail "Failed to get AI Search managed identity: $($_.Exception.Message)"
}

# Get Fabric access token (use Power BI API for workspace management)
Log "Getting Power BI access token..."
try {
    $powerBIToken = az account get-access-token --resource 'https://analysis.windows.net/powerbi/api' --query accessToken -o tsv
    if (-not $powerBIToken) {
        Fail "Failed to get Power BI access token"
    }
} catch {
    Fail "Failed to get Power BI access token: $($_.Exception.Message)"
}

$headers = @{
    'Authorization' = "Bearer $powerBIToken"
    'Content-Type' = 'application/json'
}

# Check if workspace exists and we can access it (use Fabric API for workspace info)
Log "Verifying workspace access..."
try {
    $fabricToken = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
    $fabricHeaders = @{ 'Authorization' = "Bearer $fabricToken" }
    $workspace = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$script:WorkspaceId" -Headers $fabricHeaders
    Success "✅ Workspace found: $($workspace.displayName)"
} catch {
    Fail "Cannot access workspace $script:WorkspaceId - check permissions: $($_.Exception.Message)"
}

# Try to add the AI Search managed identity to the workspace
Log "Adding AI Search managed identity to workspace..."

# First try to get current workspace users (use Power BI API)
try {
    $workspaceUsers = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$script:WorkspaceId/users" -Headers $headers
    Log "Current workspace has $($workspaceUsers.value.Count) users/members"
    
    # Check if AI Search is already a member
    $existingMember = $workspaceUsers.value | Where-Object { $_.identifier -eq $principalId }
    if ($existingMember) {
        Success "✅ AI Search managed identity is already a workspace member with role: $($existingMember.groupUserAccessRight)"
        exit 0
    }
} catch {
    Warn "Could not list current workspace users: $($_.Exception.Message)"
}

# Add AI Search managed identity as workspace member (use Power BI API)
$addUserBody = @{
    identifier = $principalId
    principalType = "App"  # For service principals/managed identities
    groupUserAccessRight = "Contributor"  # Power BI API uses this field name
} | ConvertTo-Json

Log "Adding AI Search as workspace Contributor..."
Log "Principal ID: $principalId"

try {
    Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$script:WorkspaceId/users" -Method Post -Headers $headers -Body $addUserBody | Out-Null
    Success "✅ Successfully added AI Search managed identity to workspace!"
    Log "Role: Contributor"
    Log "Principal ID: $principalId"
} catch {
    $statusCode = $_.Exception.Response.StatusCode
    $errorMessage = $_.Exception.Message
    
    if ($statusCode -eq 409) {
        Success "✅ AI Search managed identity is already a workspace member"
    } elseif ($statusCode -eq 403) {
        Fail "❌ Access denied - you may not have admin permissions on this workspace"
    } else {
        # Try with Admin role instead
        Warn "Contributor role failed, trying Admin role..."
        $addUserBodyAdmin = @{
            identifier = $principalId
            principalType = "App"
            groupUserAccessRight = "Admin"
        } | ConvertTo-Json
        
        try {
            Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$script:WorkspaceId/users" -Method Post -Headers $headers -Body $addUserBodyAdmin | Out-Null
            Success "✅ Successfully added AI Search managed identity as workspace Admin!"
        } catch {
            Fail "❌ Failed to add AI Search to workspace: $errorMessage"
        }
    }
}

Log ""
Log "=================================================================="
Success "✅ AI Search managed identity setup complete!"
Log "Next step: Test OneLake datasource creation again"
Log "The 400 Bad Request error should now be resolved"
Log "=================================================================="
