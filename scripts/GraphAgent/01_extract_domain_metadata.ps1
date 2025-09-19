#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Extract RBAC group or domain name from Fabric lakehouse metadata for Microsoft Graph queries

.DESCRIPTION
    This script connects to Microsoft Purview and Fabric APIs to extract organizational 
    identifiers from lakehouse metadata. These identifiers are used to scope Microsoft 
    Graph searches for relevant documents and content.

.PARAMETER LakehouseName
    Name of the Fabric lakehouse to analyze

.PARAMETER WorkspaceName  
    Name of the Fabric workspace containing the lakehouse

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account for metadata queries

.PARAMETER OutputFormat
    Output format: 'json', 'csv', or 'table' (default: json)

.EXAMPLE
    ./01_extract_domain_metadata.ps1 -LakehouseName "bronze" -WorkspaceName "ws001"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LakehouseName = "",
    
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceName = "",
    
    [Parameter(Mandatory = $false)]
    [string]$PurviewAccountName = "",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('json', 'csv', 'table')]
    [string]$OutputFormat = "json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Logging functions
function Log([string]$message) { 
    Write-Host "[domain-metadata] $message" -ForegroundColor Cyan 
}

function Success([string]$message) { 
    Write-Host "[domain-metadata] ✅ $message" -ForegroundColor Green 
}

function Warn([string]$message) { 
    Write-Warning "[domain-metadata] ⚠️ $message" 
}

function Error([string]$message) { 
    Write-Error "[domain-metadata] ❌ $message" 
}

# Get azd environment values if parameters not provided
function Get-AzdEnvironmentValues {
    Log "Getting configuration from azd environment..."
    try {
        $azdEnvValues = azd env get-values 2>$null
        if ($azdEnvValues) {
            $env_vars = @{}
            foreach ($line in $azdEnvValues) {
                if ($line -match '^(.+?)=(.*)$') {
                    $env_vars[$matches[1]] = $matches[2].Trim('"')
                }
            }
            return $env_vars
        }
    }
    catch {
        Warn "Could not read azd environment: $_"
    }
    return @{}
}

# Extract domain information from Fabric workspace metadata
function Get-FabricWorkspaceMetadata {
    param([string]$WorkspaceName)
    
    Log "Extracting metadata from Fabric workspace: $WorkspaceName"
    
    try {
        # Get workspace details using Fabric REST API
        $headers = @{
            'Authorization' = "Bearer $(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)"
            'Content-Type' = 'application/json'
        }
        
        # Get workspace by name
        $workspacesUri = "https://api.powerbi.com/v1.0/myorg/groups"
        $workspaces = Invoke-RestMethod -Uri $workspacesUri -Headers $headers -Method Get
        
        $workspace = $workspaces.value | Where-Object { $_.name -eq $WorkspaceName }
        
        if (-not $workspace) {
            throw "Workspace '$WorkspaceName' not found"
        }
        
        Log "Found workspace: $($workspace.name) (ID: $($workspace.id))"
        
        # Extract domain information from workspace properties
        $domainInfo = @{
            WorkspaceId = $workspace.id
            WorkspaceName = $workspace.name
            DomainName = ""
            OrganizationName = ""
            RBACGroups = @()
        }
        
        # Try to extract domain from workspace description or properties
        if ($workspace.description) {
            Log "Analyzing workspace description for domain information..."
            $domainInfo.DomainName = Extract-DomainFromText $workspace.description
        }
        
        return $domainInfo
    }
    catch {
        Error "Failed to get Fabric workspace metadata: $_"
        throw
    }
}

# Extract domain information from Purview metadata
function Get-PurviewMetadata {
    param(
        [string]$PurviewAccountName,
        [string]$WorkspaceName,
        [string]$LakehouseName
    )
    
    Log "Extracting metadata from Purview account: $PurviewAccountName"
    
    try {
        # Get Purview access token
        $purviewToken = az account get-access-token --resource "https://purview.azure.net" --query accessToken -o tsv
        $headers = @{
            'Authorization' = "Bearer $purviewToken"
            'Content-Type' = 'application/json'
        }
        
        # Search for Fabric lakehouse assets
        $searchUri = "https://$PurviewAccountName.purview.azure.com/catalog/api/search/query"
        $searchBody = @{
            keywords = "$WorkspaceName $LakehouseName"
            filter = @{
                assetType = @("FabricLakehouse")
            }
            limit = 50
        } | ConvertTo-Json -Depth 3
        
        $searchResults = Invoke-RestMethod -Uri $searchUri -Headers $headers -Method Post -Body $searchBody
        
        $domainInfo = @{
            PurviewAssets = @()
            Collections = @()
            DomainMappings = @()
        }
        
        foreach ($asset in $searchResults.value) {
            Log "Found Purview asset: $($asset.name)"
            
            # Get detailed asset information
            $assetUri = "https://$PurviewAccountName.purview.azure.com/catalog/api/atlas/v2/entity/guid/$($asset.id)"
            $assetDetails = Invoke-RestMethod -Uri $assetUri -Headers $headers -Method Get
            
            # Extract domain information from asset metadata
            $assetInfo = @{
                AssetId = $asset.id
                AssetName = $asset.name
                CollectionId = $asset.collectionId
                DomainName = Extract-DomainFromAsset $assetDetails
                Classifications = $asset.classification
            }
            
            $domainInfo.PurviewAssets += $assetInfo
        }
        
        return $domainInfo
    }
    catch {
        Error "Failed to get Purview metadata: $_"
        throw
    }
}

# Extract domain name from text using pattern matching
function Extract-DomainFromText {
    param([string]$Text)
    
    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }
    
    # Common patterns for domain/organization extraction
    $patterns = @(
        "(?i)domain[:\s]+([a-zA-Z0-9\-\.]+)",
        "(?i)organization[:\s]+([a-zA-Z0-9\-\s]+)",
        "(?i)company[:\s]+([a-zA-Z0-9\-\s]+)",
        "(?i)dept[:\s]+([a-zA-Z0-9\-\s]+)",
        "(?i)team[:\s]+([a-zA-Z0-9\-\s]+)"
    )
    
    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $matches[1].Trim()
        }
    }
    
    return ""
}

# Extract domain information from Purview asset
function Extract-DomainFromAsset {
    param($AssetDetails)
    
    $domainName = ""
    
    # Check asset attributes for domain information
    if ($AssetDetails.entity.attributes) {
        $attrs = $AssetDetails.entity.attributes
        
        # Common attribute names that might contain domain info
        $domainAttrs = @('domain', 'organization', 'businessUnit', 'department', 'owner')
        
        foreach ($attr in $domainAttrs) {
            if ($attrs.$attr) {
                $domainName = $attrs.$attr
                break
            }
        }
    }
    
    # Check asset classifications for domain information
    if ($AssetDetails.entity.classifications) {
        foreach ($classification in $AssetDetails.entity.classifications) {
            if ($classification.typeName -like "*Domain*" -or $classification.typeName -like "*Organization*") {
                if ($classification.attributes.value) {
                    $domainName = $classification.attributes.value
                    break
                }
            }
        }
    }
    
    return $domainName
}

# Main execution
try {
    Log "=============================================================="
    Log "Extracting domain metadata for Microsoft Graph queries"
    Log "=============================================================="
    
    # Get configuration from azd environment if not provided
    $envVars = Get-AzdEnvironmentValues
    
    if (-not $LakehouseName) { 
        $LakehouseName = $envVars['documentLakehouseName'] ?? 'bronze'
    }
    if (-not $WorkspaceName) { 
        $WorkspaceName = $envVars['desiredFabricWorkspaceName'] ?? 'ws001'
    }
    if (-not $PurviewAccountName) { 
        $PurviewAccountName = $envVars['purviewAccountName'] ?? ''
    }
    
    Log "Configuration:"
    Log "  Lakehouse: $LakehouseName"
    Log "  Workspace: $WorkspaceName"
    Log "  Purview Account: $PurviewAccountName"
    
    # Initialize result object
    $result = @{
        Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        Configuration = @{
            LakehouseName = $LakehouseName
            WorkspaceName = $WorkspaceName
            PurviewAccountName = $PurviewAccountName
        }
        FabricMetadata = @{}
        PurviewMetadata = @{}
        ExtractedDomains = @()
        GraphSearchTerms = @()
    }
    
    # Extract Fabric workspace metadata
    Log ""
    Log "🔍 Step 1: Extracting Fabric workspace metadata..."
    $result.FabricMetadata = Get-FabricWorkspaceMetadata -WorkspaceName $WorkspaceName
    
    # Extract Purview metadata if account specified
    if ($PurviewAccountName) {
        Log ""
        Log "🔍 Step 2: Extracting Purview metadata..."
        $result.PurviewMetadata = Get-PurviewMetadata -PurviewAccountName $PurviewAccountName -WorkspaceName $WorkspaceName -LakehouseName $LakehouseName
    } else {
        Warn "No Purview account specified, skipping Purview metadata extraction"
    }
    
    # Compile extracted domains
    Log ""
    Log "🔍 Step 3: Compiling domain information..."
    
    $domains = @()
    
    # Add domains from Fabric metadata
    if ($result.FabricMetadata.DomainName) {
        $domains += $result.FabricMetadata.DomainName
    }
    if ($result.FabricMetadata.OrganizationName) {
        $domains += $result.FabricMetadata.OrganizationName
    }
    
    # Add domains from Purview metadata
    foreach ($asset in $result.PurviewMetadata.PurviewAssets) {
        if ($asset.DomainName) {
            $domains += $asset.DomainName
        }
    }
    
    # Remove duplicates and empty values
    $result.ExtractedDomains = $domains | Where-Object { $_ } | Sort-Object -Unique
    
    # Generate Graph search terms
    foreach ($domain in $result.ExtractedDomains) {
        $result.GraphSearchTerms += @{
            Domain = $domain
            SearchQuery = "organization:$domain OR company:$domain OR team:$domain"
            FileTypes = @("docx", "xlsx", "pptx", "pdf")
            Sources = @("SharePoint", "OneDrive", "Teams")
        }
    }
    
    # Output results
    Log ""
    Success "Domain metadata extraction completed!"
    Log "Found $($result.ExtractedDomains.Count) unique domain(s): $($result.ExtractedDomains -join ', ')"
    
    # Format output based on requested format
    switch ($OutputFormat) {
        "json" {
            $jsonOutput = $result | ConvertTo-Json -Depth 5
            Write-Output $jsonOutput
            
            # Save to file for downstream consumption
            $outputFile = "domain_metadata_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            $jsonOutput | Out-File -FilePath $outputFile -Encoding UTF8
            Log "Results saved to: $outputFile"
        }
        "csv" {
            $csvData = @()
            foreach ($term in $result.GraphSearchTerms) {
                $csvData += [PSCustomObject]@{
                    Domain = $term.Domain
                    SearchQuery = $term.SearchQuery
                    FileTypes = ($term.FileTypes -join ";")
                    Sources = ($term.Sources -join ";")
                }
            }
            $csvOutput = $csvData | ConvertTo-Csv -NoTypeInformation
            Write-Output $csvOutput
            
            $outputFile = "domain_metadata_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $csvOutput | Out-File -FilePath $outputFile -Encoding UTF8
            Log "Results saved to: $outputFile"
        }
        "table" {
            if ($result.ExtractedDomains.Count -gt 0) {
                Write-Host "`n📊 Extracted Domains:" -ForegroundColor Yellow
                $result.ExtractedDomains | ForEach-Object { Write-Host "  • $_" -ForegroundColor White }
                
                Write-Host "`n🔍 Graph Search Terms:" -ForegroundColor Yellow
                $result.GraphSearchTerms | ForEach-Object {
                    Write-Host "  Domain: $($_.Domain)" -ForegroundColor White
                    Write-Host "  Query:  $($_.SearchQuery)" -ForegroundColor Gray
                    Write-Host ""
                }
            } else {
                Warn "No domain information found in metadata"
            }
        }
    }
    
    Log ""
    Success "✅ Domain metadata extraction completed successfully!"
    Log "Next: Use extracted domains in Microsoft Graph search queries"
    
} catch {
    Error "Domain metadata extraction failed: $_"
    exit 1
}