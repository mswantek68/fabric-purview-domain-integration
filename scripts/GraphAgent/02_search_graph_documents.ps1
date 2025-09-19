#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Search Microsoft Graph for documents mentioning organization names

.DESCRIPTION
    This script searches across SharePoint, OneDrive, and Teams for documents 
    (Word, Excel, PowerPoint, PDFs) that mention specific organization names.
    Results are filtered by relevance and recency for downstream processing.

.PARAMETER SearchTerms
    JSON string or file path containing search terms and domains

.PARAMETER FileTypes
    Comma-separated list of file types to search (default: docx,xlsx,pptx,pdf)

.PARAMETER DaysBack
    Number of days back to search (default: 90)

.PARAMETER MaxResults
    Maximum number of results to return per search term (default: 50)

.PARAMETER OutputPath
    Path to save search results (default: current directory)

.EXAMPLE
    ./02_search_graph_documents.ps1 -SearchTerms "Contoso,Fabrikam" -DaysBack 30
    
.EXAMPLE
    ./02_search_graph_documents.ps1 -SearchTerms "domain_metadata.json" -MaxResults 100
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SearchTerms = "",
    
    [Parameter(Mandatory = $false)]
    [string]$FileTypes = "docx,xlsx,pptx,pdf",
    
    [Parameter(Mandatory = $false)]
    [int]$DaysBack = 90,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxResults = 50,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Logging functions
function Log([string]$message) { 
    Write-Host "[graph-search] $message" -ForegroundColor Cyan 
}

function Success([string]$message) { 
    Write-Host "[graph-search] ✅ $message" -ForegroundColor Green 
}

function Warn([string]$message) { 
    Write-Warning "[graph-search] ⚠️ $message" 
}

function Error([string]$message) { 
    Write-Error "[graph-search] ❌ $message" 
}

# Check if Microsoft Graph PowerShell module is available
function Test-GraphModule {
    Log "Checking Microsoft Graph PowerShell module..."
    
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        Error "Microsoft Graph PowerShell module not found"
        Log "Install with: Install-Module Microsoft.Graph -Scope CurrentUser"
        throw "Microsoft Graph module required"
    }
    
    Success "Microsoft Graph module found"
}

# Connect to Microsoft Graph with required scopes
function Connect-GraphWithScopes {
    Log "Connecting to Microsoft Graph..."
    
    $requiredScopes = @(
        "Files.Read.All",
        "Sites.Read.All", 
        "Directory.Read.All",
        "Chat.Read.All",
        "ChannelMessage.Read.All"
    )
    
    try {
        Connect-MgGraph -Scopes $requiredScopes -NoWelcome
        $context = Get-MgContext
        Success "Connected to Microsoft Graph as $($context.Account)"
        return $context
    }
    catch {
        Error "Failed to connect to Microsoft Graph: $_"
        throw
    }
}

# Parse search terms from input
function Get-SearchTermsFromInput {
    param([string]$Input)
    
    if ([string]::IsNullOrEmpty($Input)) {
        # Try to find latest domain metadata file
        $metadataFiles = Get-ChildItem -Path "." -Name "domain_metadata_*.json" | Sort-Object LastWriteTime -Descending
        if ($metadataFiles.Count -gt 0) {
            $Input = $metadataFiles[0].FullName
            Log "Using latest domain metadata file: $($metadataFiles[0].Name)"
        } else {
            throw "No search terms provided and no domain metadata files found"
        }
    }
    
    # Check if input is a file path
    if (Test-Path $Input) {
        Log "Loading search terms from file: $Input"
        $content = Get-Content -Path $Input -Raw | ConvertFrom-Json
        
        if ($content.GraphSearchTerms) {
            return $content.GraphSearchTerms
        } elseif ($content.ExtractedDomains) {
            # Convert extracted domains to search terms
            $searchTerms = @()
            foreach ($domain in $content.ExtractedDomains) {
                $searchTerms += @{
                    Domain = $domain
                    SearchQuery = "$domain"
                    FileTypes = @("docx", "xlsx", "pptx", "pdf")
                    Sources = @("SharePoint", "OneDrive", "Teams")
                }
            }
            return $searchTerms
        } else {
            throw "Invalid domain metadata file format"
        }
    } else {
        # Treat as comma-separated list of terms
        Log "Parsing search terms from input string"
        $terms = $Input.Split(',') | ForEach-Object { $_.Trim() }
        $searchTerms = @()
        
        foreach ($term in $terms) {
            $searchTerms += @{
                Domain = $term
                SearchQuery = $term
                FileTypes = @("docx", "xlsx", "pptx", "pdf")
                Sources = @("SharePoint", "OneDrive", "Teams")
            }
        }
        return $searchTerms
    }
}

# Search SharePoint sites for documents
function Search-SharePointDocuments {
    param(
        [string]$SearchQuery,
        [array]$FileTypes,
        [DateTime]$FromDate,
        [int]$MaxResults
    )
    
    Log "Searching SharePoint for: '$SearchQuery'"
    
    try {
        $results = @()
        
        # Build file type filter
        $fileTypeFilter = ($FileTypes | ForEach-Object { "filetype:$_" }) -join " OR "
        
        # Construct search query
        $fullQuery = "($SearchQuery) AND ($fileTypeFilter)"
        
        # Use Microsoft Graph Search API
        $searchBody = @{
            requests = @(
                @{
                    entityTypes = @("driveItem")
                    query = @{
                        queryString = $fullQuery
                    }
                    from = 0
                    size = $MaxResults
                    sortProperties = @(
                        @{
                            name = "lastModifiedDateTime"
                            isDescending = $true
                        }
                    )
                }
            )
        }
        
        $searchResults = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/search/query" -Body ($searchBody | ConvertTo-Json -Depth 5)
        
        foreach ($response in $searchResults.value) {
            foreach ($hit in $response.hitsContainers[0].hits) {
                $item = $hit.resource
                
                # Filter by date
                $lastModified = [DateTime]::Parse($item.lastModifiedDateTime)
                if ($lastModified -ge $FromDate) {
                    $results += @{
                        Id = $item.id
                        Name = $item.name
                        WebUrl = $item.webUrl
                        LastModified = $lastModified
                        Size = $item.size
                        CreatedBy = $item.createdBy.user.displayName
                        ModifiedBy = $item.lastModifiedBy.user.displayName
                        Source = "SharePoint"
                        FileType = [System.IO.Path]::GetExtension($item.name).TrimStart('.')
                        SearchTerm = $SearchQuery
                        Relevance = $hit.rank
                    }
                }
            }
        }
        
        Log "Found $($results.Count) SharePoint documents"
        return $results
    }
    catch {
        Error "SharePoint search failed: $_"
        return @()
    }
}

# Search OneDrive for documents
function Search-OneDriveDocuments {
    param(
        [string]$SearchQuery,
        [array]$FileTypes,
        [DateTime]$FromDate,
        [int]$MaxResults
    )
    
    Log "Searching OneDrive for: '$SearchQuery'"
    
    try {
        $results = @()
        
        # Get current user's OneDrive
        $drive = Get-MgUserDrive -UserId "me"
        
        # Search OneDrive items
        $searchUrl = "https://graph.microsoft.com/v1.0/me/drive/root/search(q='$SearchQuery')"
        $searchResults = Invoke-MgGraphRequest -Method GET -Uri $searchUrl
        
        foreach ($item in $searchResults.value) {
            # Filter by file type and date
            $fileExtension = [System.IO.Path]::GetExtension($item.name).TrimStart('.')
            $lastModified = [DateTime]::Parse($item.lastModifiedDateTime)
            
            if ($FileTypes -contains $fileExtension -and $lastModified -ge $FromDate) {
                $results += @{
                    Id = $item.id
                    Name = $item.name
                    WebUrl = $item.webUrl
                    LastModified = $lastModified
                    Size = $item.size
                    CreatedBy = $item.createdBy.user.displayName
                    ModifiedBy = $item.lastModifiedBy.user.displayName
                    Source = "OneDrive"
                    FileType = $fileExtension
                    SearchTerm = $SearchQuery
                    Relevance = 1.0
                }
                
                if ($results.Count -ge $MaxResults) {
                    break
                }
            }
        }
        
        Log "Found $($results.Count) OneDrive documents"
        return $results
    }
    catch {
        Error "OneDrive search failed: $_"
        return @()
    }
}

# Search Teams messages for document references
function Search-TeamsMessages {
    param(
        [string]$SearchQuery,
        [array]$FileTypes,
        [DateTime]$FromDate,
        [int]$MaxResults
    )
    
    Log "Searching Teams messages for: '$SearchQuery'"
    
    try {
        $results = @()
        
        # Get user's teams
        $teams = Get-MgUserJoinedTeam -UserId "me"
        
        foreach ($team in $teams) {
            # Get team channels
            $channels = Get-MgTeamChannel -TeamId $team.Id
            
            foreach ($channel in $channels) {
                try {
                    # Get recent messages in channel
                    $messages = Get-MgTeamChannelMessage -TeamId $team.Id -ChannelId $channel.Id -Top 50
                    
                    foreach ($message in $messages) {
                        $createdDateTime = [DateTime]::Parse($message.CreatedDateTime)
                        
                        # Check if message is within date range and contains search term
                        if ($createdDateTime -ge $FromDate -and $message.Body.Content -like "*$SearchQuery*") {
                            
                            # Check for file attachments
                            if ($message.Attachments) {
                                foreach ($attachment in $message.Attachments) {
                                    if ($attachment.ContentType -eq "reference") {
                                        $fileExtension = [System.IO.Path]::GetExtension($attachment.Name).TrimStart('.')
                                        
                                        if ($FileTypes -contains $fileExtension) {
                                            $results += @{
                                                Id = $attachment.Id
                                                Name = $attachment.Name
                                                WebUrl = $attachment.ContentUrl
                                                LastModified = $createdDateTime
                                                Size = 0
                                                CreatedBy = $message.From.User.DisplayName
                                                ModifiedBy = $message.From.User.DisplayName
                                                Source = "Teams"
                                                FileType = $fileExtension
                                                SearchTerm = $SearchQuery
                                                Relevance = 1.0
                                                TeamName = $team.DisplayName
                                                ChannelName = $channel.DisplayName
                                                MessageContext = $message.Body.Content.Substring(0, [Math]::Min(200, $message.Body.Content.Length))
                                            }
                                            
                                            if ($results.Count -ge $MaxResults) {
                                                return $results
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                catch {
                    # Skip channels that can't be accessed
                    continue
                }
            }
        }
        
        Log "Found $($results.Count) Teams document references"
        return $results
    }
    catch {
        Error "Teams search failed: $_"
        return @()
    }
}

# Rank and filter results by relevance
function Optimize-SearchResults {
    param(
        [array]$Results,
        [int]$MaxResults
    )
    
    Log "Optimizing search results by relevance and recency..."
    
    # Calculate composite score based on relevance and recency
    $now = Get-Date
    $scoredResults = @()
    
    foreach ($result in $Results) {
        $daysSinceModified = ($now - $result.LastModified).TotalDays
        
        # Score components
        $relevanceScore = $result.Relevance ?? 1.0
        $recencyScore = [Math]::Max(0, 1.0 - ($daysSinceModified / 365.0)) # Decay over a year
        $sizeScore = [Math]::Min(1.0, $result.Size / 10MB) # Prefer larger files up to 10MB
        
        # Composite score
        $compositeScore = (0.5 * $relevanceScore) + (0.3 * $recencyScore) + (0.2 * $sizeScore)
        
        $scoredResults += $result | Add-Member -NotePropertyName "CompositeScore" -NotePropertyValue $compositeScore -PassThru
    }
    
    # Sort by composite score and take top results
    $optimizedResults = $scoredResults | Sort-Object CompositeScore -Descending | Select-Object -First $MaxResults
    
    Log "Optimized to $($optimizedResults.Count) top results"
    return $optimizedResults
}

# Main execution
try {
    Log "=============================================================="
    Log "Searching Microsoft Graph for organization documents"
    Log "=============================================================="
    
    # Check prerequisites
    Test-GraphModule
    
    # Connect to Microsoft Graph
    $graphContext = Connect-GraphWithScopes
    
    # Parse search terms
    $searchTermsList = Get-SearchTermsFromInput -Input $SearchTerms
    Log "Found $($searchTermsList.Count) search term(s)"
    
    # Parse file types
    $fileTypesArray = $FileTypes.Split(',') | ForEach-Object { $_.Trim().ToLower() }
    Log "Searching for file types: $($fileTypesArray -join ', ')"
    
    # Calculate search date range
    $fromDate = (Get-Date).AddDays(-$DaysBack)
    Log "Searching documents modified since: $($fromDate.ToString('yyyy-MM-dd'))"
    
    # Initialize results collection
    $allResults = @()
    $searchStats = @{
        TotalSearches = 0
        SharePointResults = 0
        OneDriveResults = 0
        TeamsResults = 0
        TotalResults = 0
    }
    
    # Process each search term
    foreach ($searchTerm in $searchTermsList) {
        Log ""
        Log "🔍 Processing search term: '$($searchTerm.Domain)'"
        $searchStats.TotalSearches++
        
        $termResults = @()
        
        # Search SharePoint
        if ($searchTerm.Sources -contains "SharePoint") {
            $spResults = Search-SharePointDocuments -SearchQuery $searchTerm.SearchQuery -FileTypes $fileTypesArray -FromDate $fromDate -MaxResults $MaxResults
            $termResults += $spResults
            $searchStats.SharePointResults += $spResults.Count
        }
        
        # Search OneDrive
        if ($searchTerm.Sources -contains "OneDrive") {
            $odResults = Search-OneDriveDocuments -SearchQuery $searchTerm.SearchQuery -FileTypes $fileTypesArray -FromDate $fromDate -MaxResults $MaxResults
            $termResults += $odResults
            $searchStats.OneDriveResults += $odResults.Count
        }
        
        # Search Teams
        if ($searchTerm.Sources -contains "Teams") {
            $teamsResults = Search-TeamsMessages -SearchQuery $searchTerm.SearchQuery -FileTypes $fileTypesArray -FromDate $fromDate -MaxResults $MaxResults
            $termResults += $teamsResults
            $searchStats.TeamsResults += $teamsResults.Count
        }
        
        # Add term results to collection
        $allResults += $termResults
        Log "Found $($termResults.Count) documents for term '$($searchTerm.Domain)'"
    }
    
    # Remove duplicates based on file ID or URL
    Log ""
    Log "🔄 Removing duplicate results..."
    $uniqueResults = @()
    $seenIds = @{}
    
    foreach ($result in $allResults) {
        $key = $result.Id ?? $result.WebUrl
        if (-not $seenIds.ContainsKey($key)) {
            $uniqueResults += $result
            $seenIds[$key] = $true
        }
    }
    
    Log "Removed $($allResults.Count - $uniqueResults.Count) duplicate(s)"
    $searchStats.TotalResults = $uniqueResults.Count
    
    # Optimize results by relevance and recency
    $optimizedResults = Optimize-SearchResults -Results $uniqueResults -MaxResults ($MaxResults * $searchTermsList.Count)
    
    # Create output object
    $output = @{
        Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        SearchConfiguration = @{
            SearchTerms = $searchTermsList
            FileTypes = $fileTypesArray
            DaysBack = $DaysBack
            MaxResults = $MaxResults
            FromDate = $fromDate.ToString("yyyy-MM-dd")
        }
        Statistics = $searchStats
        Results = $optimizedResults
    }
    
    # Save results to file
    $outputFileName = "graph_search_results_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $outputFilePath = Join-Path $OutputPath $outputFileName
    
    $output | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputFilePath -Encoding UTF8
    
    # Display summary
    Log ""
    Success "Microsoft Graph search completed!"
    Log "📊 Search Statistics:"
    Log "  • Total searches: $($searchStats.TotalSearches)"
    Log "  • SharePoint results: $($searchStats.SharePointResults)"
    Log "  • OneDrive results: $($searchStats.OneDriveResults)"
    Log "  • Teams results: $($searchStats.TeamsResults)"
    Log "  • Unique results: $($searchStats.TotalResults)"
    Log "  • Optimized results: $($optimizedResults.Count)"
    Log ""
    Success "Results saved to: $outputFilePath"
    
    # Display top results
    if ($optimizedResults.Count -gt 0) {
        Log ""
        Log "🏆 Top Results:"
        $optimizedResults | Select-Object -First 5 | ForEach-Object {
            Log "  📄 $($_.Name) ($($_.Source))"
            Log "     Modified: $($_.LastModified.ToString('yyyy-MM-dd')) | Score: $($_.CompositeScore.ToString('F2'))"
        }
        
        if ($optimizedResults.Count -gt 5) {
            Log "     ... and $($optimizedResults.Count - 5) more"
        }
    }
    
    Log ""
    Success "✅ Graph document search completed successfully!"
    Log "Next: Use results for document summarization"
    
    # Disconnect from Graph
    Disconnect-MgGraph | Out-Null
    
} catch {
    Error "Microsoft Graph search failed: $_"
    
    # Attempt to disconnect on error
    try { Disconnect-MgGraph | Out-Null } catch { }
    
    exit 1
}