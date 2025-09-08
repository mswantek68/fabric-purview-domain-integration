#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup RBAC permissions for AI Search managed identity to access Fabric workspace

.DESCRIPTION
    This script configures the AI Search System-Assigned Managed Identity (SAMI) 
    with proper permissions to access OneLake data in the Fabric workspace.
    This is required before creating OneLake data sources in AI Search.

.PARAMETER ExecutionManagedIdentityPrincipalId
    The principal ID of the execution managed identity (for Azure Container Apps)

.PARAMETER AISearchName
    The name of the AI Search service

.PARAMETER AIFoundryName
    The name of the AI Foundry/AI Services resource

.EXAMPLE
    ./setup_ai_services_rbac.ps1 -ExecutionManagedIdentityPrincipalId "12345678-1234-1234-1234-123456789abc" -AISearchName "aisearch123" -AIFoundryName "aifoundry123"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutionManagedIdentityPrincipalId,
    
    [Parameter(Mandatory = $true)]
    [string]$AISearchName,
    
    [Parameter(Mandatory = $true)]
    [string]$AIFoundryName,
    
    [Parameter(Mandatory = $false)]
    [string]$AISearchResourceGroup = "AI_Related"
)

# Colors for output
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Magenta = "`e[35m"
$Reset = "`e[0m"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = $Reset)
    Write-Host "$Color$Message$Reset"
}

function Log {
    param([string]$Message)
    Write-ColorOutput "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message" $Green
}

function Warn {
    param([string]$Message)
    Write-ColorOutput "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): WARNING: $Message" $Yellow
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): ERROR: $Message" $Red
}

function Get-AISearchManagedIdentity {
    param([string]$SearchServiceName, [string]$ResourceGroup)
    
    try {
        Log "Getting AI Search managed identity for $SearchServiceName..."
        $searchService = az search service show --name $SearchServiceName --resource-group $ResourceGroup --query "{principalId:identity.principalId,resourceGroup:resourceGroup}" -o json | ConvertFrom-Json
        
        if (-not $searchService.principalId) {
            throw "AI Search service $SearchServiceName does not have a system-assigned managed identity enabled"
        }
        
        Log "✅ Found AI Search managed identity: $($searchService.principalId)"
        return @{
            PrincipalId = $searchService.principalId
            ResourceGroup = $searchService.resourceGroup
        }
    } catch {
        Write-Error "Failed to get AI Search managed identity: $($_.Exception.Message)"
        throw
    }
}

function Add-AISearchToFabricWorkspace {
    param([string]$AISearchPrincipalId, [string]$WorkspaceId)
    
    try {
        Log "Adding AI Search managed identity to Fabric workspace $WorkspaceId..."
        
        # Get Fabric access token
        $fabricToken = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
        if (-not $fabricToken) {
            throw "Failed to get Fabric access token"
        }
        
        # Check if workspace exists and get details
        $headers = @{
            'Authorization' = "Bearer $fabricToken"
            'Content-Type' = 'application/json'
        }
        
        $workspaceUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId"
        
        try {
            $workspaceResponse = Invoke-RestMethod -Uri $workspaceUri -Headers $headers -Method GET
            Log "✅ Workspace found: $($workspaceResponse.displayName)"
        } catch {
            throw "Workspace $WorkspaceId not found or not accessible"
        }
        
        # Add user to workspace with Contributor role using the new API
        # Note: This is a simplified approach - in production you might want more granular permissions
        $addUserUri = "$workspaceUri/roleAssignments"
        $body = @{
            principal = @{
                id = $AISearchPrincipalId
                type = "ServicePrincipal"
            }
            role = "Contributor"
        } | ConvertTo-Json -Depth 3
        
        try {
            Invoke-RestMethod -Uri $addUserUri -Headers $headers -Method POST -Body $body | Out-Null
            Log "✅ Successfully added AI Search managed identity to Fabric workspace"
            Log "   Principal ID: $AISearchPrincipalId"
            Log "   Workspace: $($workspaceResponse.displayName)"
            Log "   Role: Contributor"
        } catch {
            $errorDetails = $_.Exception.Message
            if ($errorDetails -like "*already exists*" -or $errorDetails -like "*already a member*" -or $errorDetails -like "*already has a role*" -or $errorDetails -like "*409*") {
                Log "✅ AI Search managed identity already has access to the workspace"
                Log "   Principal ID: $AISearchPrincipalId"
                Log "   Workspace: $($workspaceResponse.displayName)"
                Log "   Role: Contributor (existing)"
            } else {
                Warn "Failed to add AI Search to workspace via API: $errorDetails"
                Log "This might require manual configuration in the Fabric portal"
            }
        }
        
    } catch {
        Write-Error "Failed to add AI Search to Fabric workspace: $($_.Exception.Message)"
        throw
    }
}

function Set-StorageBlobPermissions {
    param([string]$AISearchPrincipalId, [string]$ResourceGroup)
    
    try {
        Log "Setting up Storage Blob Data Reader permissions for AI Search..."
        
        # Get subscription ID
        $subscriptionId = az account show --query id -o tsv
        
        # Assign Storage Blob Data Reader role
        $roleAssignment = az role assignment create `
            --assignee $AISearchPrincipalId `
            --role "Storage Blob Data Reader" `
            --scope "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup" `
            --output json 2>/dev/null | ConvertFrom-Json
            
        if ($roleAssignment) {
            Log "✅ Storage Blob Data Reader role assigned successfully"
        } else {
            Warn "Role assignment may already exist or failed silently"
        }
        
    } catch {
        Warn "Failed to assign Storage Blob Data Reader role: $($_.Exception.Message)"
        Log "This can be assigned manually if needed"
    }
}

# Main execution
try {
    Write-ColorOutput "`n🔐 Setting up AI Search RBAC permissions for OneLake..." $Magenta
    
    # Get AI Search managed identity
    $aiSearchInfo = Get-AISearchManagedIdentity -SearchServiceName $AISearchName -ResourceGroup $AISearchResourceGroup
    $aiSearchPrincipalId = $aiSearchInfo.PrincipalId
    $aiSearchResourceGroup = $aiSearchInfo.ResourceGroup
    
    # Read workspace ID from environment file
    $workspaceEnvFile = "/tmp/fabric_workspace.env"
    if (Test-Path $workspaceEnvFile) {
        $workspaceContent = Get-Content $workspaceEnvFile
        $workspaceId = $null
        foreach ($line in $workspaceContent) {
            if ($line -match '^FABRIC_WORKSPACE_ID=(.+)$') {
                $workspaceId = $matches[1].Trim('"').Trim("'")
                break
            }
        }
        
        if ($workspaceId) {
            Log "Found Fabric workspace ID: $workspaceId"
            
            # Add AI Search to Fabric workspace
            Add-AISearchToFabricWorkspace -AISearchPrincipalId $aiSearchPrincipalId -WorkspaceId $workspaceId
            
        } else {
            Warn "Could not find FABRIC_WORKSPACE_ID in $workspaceEnvFile"
        }
    } else {
        Warn "Workspace environment file not found: $workspaceEnvFile"
    }
    
    # Setup Storage permissions
    Set-StorageBlobPermissions -AISearchPrincipalId $aiSearchPrincipalId -ResourceGroup $aiSearchResourceGroup
    
    Write-ColorOutput "`n✅ RBAC setup completed!" $Green
    Write-ColorOutput "AI Search managed identity permissions configured for OneLake access" $Green
    
} catch {
    Write-Error "RBAC setup failed: $($_.Exception.Message)"
    Write-ColorOutput "`nYou can manually configure permissions:" $Yellow
    Write-ColorOutput "1. Add AI Search managed identity to Fabric workspace as Contributor" $Yellow
    Write-ColorOutput "2. Assign Storage Blob Data Reader role to AI Search managed identity" $Yellow
    exit 1
}
