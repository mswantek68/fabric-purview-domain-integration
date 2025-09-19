#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Summarize documents using Azure OpenAI or Cognitive Services

.DESCRIPTION
    This script processes documents found by Microsoft Graph search and generates 
    intelligent summaries using Azure OpenAI or Cognitive Services. Summaries are 
    generated in markdown or JSON format for ingestion into Fabric lakehouse.

.PARAMETER InputFile
    Path to JSON file containing search results from graph search

.PARAMETER OpenAIEndpoint
    Azure OpenAI endpoint URL

.PARAMETER OpenAIKey
    Azure OpenAI API key (optional if using managed identity)

.PARAMETER ModelName
    OpenAI model to use for summarization (default: gpt-4)

.PARAMETER OutputFormat
    Output format: 'markdown', 'json', or 'both' (default: both)

.PARAMETER MaxDocuments
    Maximum number of documents to process (default: 50)

.PARAMETER ChunkSize
    Text chunk size for large documents (default: 4000)

.EXAMPLE
    ./03_summarize_documents.ps1 -InputFile "graph_search_results.json" -OutputFormat "markdown"
    
.EXAMPLE
    ./03_summarize_documents.ps1 -InputFile "graph_search_results.json" -MaxDocuments 20
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InputFile = "",
    
    [Parameter(Mandatory = $false)]
    [string]$OpenAIEndpoint = "",
    
    [Parameter(Mandatory = $false)]
    [string]$OpenAIKey = "",
    
    [Parameter(Mandatory = $false)]
    [string]$ModelName = "gpt-4",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('markdown', 'json', 'both')]
    [string]$OutputFormat = "both",
    
    [Parameter(Mandatory = $false)]
    [int]$MaxDocuments = 50,
    
    [Parameter(Mandatory = $false)]
    [int]$ChunkSize = 4000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Logging functions
function Log([string]$message) { 
    Write-Host "[doc-summarizer] $message" -ForegroundColor Cyan 
}

function Success([string]$message) { 
    Write-Host "[doc-summarizer] ✅ $message" -ForegroundColor Green 
}

function Warn([string]$message) { 
    Write-Warning "[doc-summarizer] ⚠️ $message" 
}

function Error([string]$message) { 
    Write-Error "[doc-summarizer] ❌ $message" 
}

# Get Azure OpenAI configuration
function Get-OpenAIConfiguration {
    Log "Getting Azure OpenAI configuration..."
    
    $config = @{
        Endpoint = $OpenAIEndpoint
        ApiKey = $OpenAIKey
        ModelName = $ModelName
    }
    
    # Try to get from azd environment if not provided
    if (-not $config.Endpoint -or -not $config.ApiKey) {
        try {
            $azdEnvValues = azd env get-values 2>$null
            if ($azdEnvValues) {
                $env_vars = @{}
                foreach ($line in $azdEnvValues) {
                    if ($line -match '^(.+?)=(.*)$') {
                        $env_vars[$matches[1]] = $matches[2].Trim('"')
                    }
                }
                
                if (-not $config.Endpoint) { 
                    $config.Endpoint = $env_vars['aiFoundryName'] ? "https://$($env_vars['aiFoundryName']).openai.azure.com/" : ""
                }
                if (-not $config.ApiKey) {
                    # Try to get API key from Azure CLI
                    try {
                        $resourceGroup = $env_vars['aiFoundryResourceGroup']
                        $serviceName = $env_vars['aiFoundryName']
                        if ($resourceGroup -and $serviceName) {
                            $config.ApiKey = az cognitiveservices account keys list --name $serviceName --resource-group $resourceGroup --query "key1" -o tsv
                        }
                    }
                    catch {
                        Warn "Could not retrieve API key automatically"
                    }
                }
            }
        }
        catch {
            Warn "Could not read azd environment"
        }
    }
    
    # Use managed identity if no API key provided
    if (-not $config.ApiKey) {
        Log "No API key provided, will attempt to use managed identity"
        $config.ApiKey = "managed-identity"
    }
    
    if (-not $config.Endpoint) {
        throw "Azure OpenAI endpoint is required"
    }
    
    Log "Using endpoint: $($config.Endpoint)"
    Log "Using model: $($config.ModelName)"
    
    return $config
}

# Get access token for managed identity authentication
function Get-ManagedIdentityToken {
    param([string]$Resource = "https://cognitiveservices.azure.com")
    
    try {
        $tokenResponse = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$Resource" -Headers @{Metadata="true"}
        return $tokenResponse.access_token
    }
    catch {
        throw "Failed to get managed identity token: $_"
    }
}

# Call Azure OpenAI API
function Invoke-OpenAICompletion {
    param(
        [string]$Prompt,
        [hashtable]$Config,
        [int]$MaxTokens = 2000
    )
    
    $headers = @{
        'Content-Type' = 'application/json'
    }
    
    # Set authentication header
    if ($Config.ApiKey -eq "managed-identity") {
        $token = Get-ManagedIdentityToken
        $headers['Authorization'] = "Bearer $token"
    } else {
        $headers['api-key'] = $Config.ApiKey
    }
    
    $body = @{
        messages = @(
            @{
                role = "system"
                content = "You are an expert document analyst. Generate concise, structured summaries that capture key information, decisions, and actionable items."
            },
            @{
                role = "user"
                content = $Prompt
            }
        )
        max_tokens = $MaxTokens
        temperature = 0.3
        top_p = 0.9
    } | ConvertTo-Json -Depth 3
    
    $uri = "$($Config.Endpoint)openai/deployments/$($Config.ModelName)/chat/completions?api-version=2024-02-15-preview"
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
        return $response.choices[0].message.content
    }
    catch {
        Error "OpenAI API call failed: $_"
        throw
    }
}

# Download and extract text from document
function Get-DocumentContent {
    param(
        [hashtable]$Document
    )
    
    Log "Downloading content from: $($Document.Name)"
    
    try {
        # Connect to Microsoft Graph if not already connected
        if (-not (Get-MgContext)) {
            Connect-MgGraph -Scopes "Files.Read.All" -NoWelcome
        }
        
        $content = ""
        
        # Download file content based on source
        switch ($Document.Source) {
            "SharePoint" {
                # Extract site and drive info from URL
                if ($Document.WebUrl -match "sites/([^/]+)") {
                    $siteName = $matches[1]
                    $driveItem = Get-MgDriveItem -DriveId $Document.DriveId -DriveItemId $Document.Id
                    $downloadUrl = $driveItem.AdditionalProperties["@microsoft.graph.downloadUrl"]
                    
                    if ($downloadUrl) {
                        $tempFile = [System.IO.Path]::GetTempFileName()
                        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile
                        $content = Extract-TextFromFile -FilePath $tempFile -FileType $Document.FileType
                        Remove-Item $tempFile -Force
                    }
                }
            }
            "OneDrive" {
                $driveItem = Get-MgDriveItem -DriveId "me" -DriveItemId $Document.Id
                $downloadUrl = $driveItem.AdditionalProperties["@microsoft.graph.downloadUrl"]
                
                if ($downloadUrl) {
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile
                    $content = Extract-TextFromFile -FilePath $tempFile -FileType $Document.FileType
                    Remove-Item $tempFile -Force
                }
            }
            "Teams" {
                # For Teams files, try to get content URL
                if ($Document.WebUrl) {
                    $content = "Teams file reference: $($Document.Name)`nContext: $($Document.MessageContext)"
                }
            }
        }
        
        # Truncate content if too long
        if ($content.Length -gt $ChunkSize) {
            $content = $content.Substring(0, $ChunkSize) + "`n[Content truncated...]"
        }
        
        return $content
    }
    catch {
        Warn "Failed to get content for $($Document.Name): $_"
        return "Content unavailable: $($Document.Name)"
    }
}

# Extract text from different file types
function Extract-TextFromFile {
    param(
        [string]$FilePath,
        [string]$FileType
    )
    
    switch ($FileType.ToLower()) {
        "pdf" {
            # For PDF files, you would need a PDF text extraction library
            # This is a placeholder - implement based on your needs
            return "PDF content extraction not implemented - file: $FilePath"
        }
        "docx" {
            # For Word documents, you would need Office interop or Open XML SDK
            # This is a placeholder - implement based on your needs
            return "Word document content extraction not implemented - file: $FilePath"
        }
        "xlsx" {
            # For Excel files, you would need Excel interop or EPPlus
            # This is a placeholder - implement based on your needs
            return "Excel content extraction not implemented - file: $FilePath"
        }
        "pptx" {
            # For PowerPoint files, you would need PowerPoint interop or Open XML SDK
            # This is a placeholder - implement based on your needs
            return "PowerPoint content extraction not implemented - file: $FilePath"
        }
        default {
            # Try to read as plain text
            try {
                return Get-Content -Path $FilePath -Raw -Encoding UTF8
            }
            catch {
                return "Unable to extract text from file: $FilePath"
            }
        }
    }
}

# Generate document summary using OpenAI
function New-DocumentSummary {
    param(
        [hashtable]$Document,
        [string]$Content,
        [hashtable]$Config
    )
    
    Log "Generating summary for: $($Document.Name)"
    
    $prompt = @"
Analyze the following document and provide a structured summary:

Document Name: $($Document.Name)
Source: $($Document.Source)
File Type: $($Document.FileType)
Last Modified: $($Document.LastModified)
Search Term: $($Document.SearchTerm)

Content:
$Content

Please provide a summary in the following format:

**Document Summary**
- **Title**: [Document title/name]
- **Document Type**: [Type of document]
- **Key Topics**: [Main topics covered]
- **Organization References**: [Any organization/company names mentioned]
- **Key Decisions**: [Important decisions or conclusions]
- **Action Items**: [Any action items or next steps]
- **Key People**: [Important people mentioned]
- **Dates**: [Important dates mentioned]
- **Relevance**: [Why this document is relevant to the search term]

**Executive Summary** (2-3 sentences):
[Brief executive summary]

**Tags**: [Relevant tags for categorization]
"@

    try {
        $summary = Invoke-OpenAICompletion -Prompt $prompt -Config $Config -MaxTokens 1500
        
        return @{
            DocumentId = $Document.Id
            DocumentName = $Document.Name
            Source = $Document.Source
            FileType = $Document.FileType
            LastModified = $Document.LastModified
            SearchTerm = $Document.SearchTerm
            WebUrl = $Document.WebUrl
            Summary = $summary
            GeneratedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            ModelUsed = $Config.ModelName
        }
    }
    catch {
        Error "Failed to generate summary for $($Document.Name): $_"
        return @{
            DocumentId = $Document.Id
            DocumentName = $Document.Name
            Source = $Document.Source
            Error = "Summary generation failed: $_"
            GeneratedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }
}

# Load search results from input file
function Get-SearchResults {
    param([string]$FilePath)
    
    if ([string]::IsNullOrEmpty($FilePath)) {
        # Find latest search results file
        $searchFiles = Get-ChildItem -Path "." -Name "graph_search_results_*.json" | Sort-Object LastWriteTime -Descending
        if ($searchFiles.Count -gt 0) {
            $FilePath = $searchFiles[0].FullName
            Log "Using latest search results file: $($searchFiles[0].Name)"
        } else {
            throw "No input file specified and no search results files found"
        }
    }
    
    if (-not (Test-Path $FilePath)) {
        throw "Input file not found: $FilePath"
    }
    
    Log "Loading search results from: $FilePath"
    $content = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
    
    if (-not $content.Results) {
        throw "No results found in input file"
    }
    
    return $content
}

# Generate markdown report
function New-MarkdownReport {
    param(
        [array]$Summaries,
        [hashtable]$SearchData
    )
    
    $markdown = @"
# Document Summaries Report

**Generated**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  
**Search Terms**: $($SearchData.SearchConfiguration.SearchTerms | ForEach-Object { $_.Domain } | Join-String ', ')  
**Documents Processed**: $($Summaries.Count)  
**Date Range**: $($SearchData.SearchConfiguration.FromDate) to present

---

"@
    
    foreach ($summary in $Summaries) {
        if ($summary.Error) {
            $markdown += @"

## ❌ $($summary.DocumentName)

**Source**: $($summary.Source)  
**Error**: $($summary.Error)

---

"@
        } else {
            $markdown += @"

## 📄 $($summary.DocumentName)

**Source**: $($summary.Source) | **Type**: $($summary.FileType) | **Modified**: $($summary.LastModified)  
**Search Term**: $($summary.SearchTerm)  
**URL**: [$($summary.DocumentName)]($($summary.WebUrl))

$($summary.Summary)

---

"@
        }
    }
    
    return $markdown
}

# Main execution
try {
    Log "=============================================================="
    Log "Summarizing documents using Azure OpenAI"
    Log "=============================================================="
    
    # Get OpenAI configuration
    $openAIConfig = Get-OpenAIConfiguration
    
    # Load search results
    $searchData = Get-SearchResults -FilePath $InputFile
    Log "Loaded $($searchData.Results.Count) search results"
    
    # Limit number of documents to process
    $documentsToProcess = $searchData.Results | Select-Object -First $MaxDocuments
    Log "Processing $($documentsToProcess.Count) documents (max: $MaxDocuments)"
    
    # Process documents and generate summaries
    $summaries = @()
    $processedCount = 0
    
    foreach ($document in $documentsToProcess) {
        $processedCount++
        Log "Processing document $processedCount/$($documentsToProcess.Count): $($document.Name)"
        
        try {
            # Get document content
            $content = Get-DocumentContent -Document $document
            
            # Generate summary
            $summary = New-DocumentSummary -Document $document -Content $content -Config $openAIConfig
            $summaries += $summary
            
            Success "Generated summary for: $($document.Name)"
        }
        catch {
            Error "Failed to process $($document.Name): $_"
            $summaries += @{
                DocumentId = $document.Id
                DocumentName = $document.Name
                Source = $document.Source
                Error = "Processing failed: $_"
                GeneratedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        }
        
        # Small delay to avoid rate limiting
        Start-Sleep -Milliseconds 500
    }
    
    # Create output object
    $output = @{
        Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        Configuration = @{
            InputFile = $InputFile
            ModelName = $openAIConfig.ModelName
            MaxDocuments = $MaxDocuments
            ChunkSize = $ChunkSize
        }
        SourceData = $searchData.SearchConfiguration
        Statistics = @{
            TotalDocuments = $searchData.Results.Count
            ProcessedDocuments = $documentsToProcess.Count
            SuccessfulSummaries = ($summaries | Where-Object { -not $_.Error }).Count
            FailedSummaries = ($summaries | Where-Object { $_.Error }).Count
        }
        Summaries = $summaries
    }
    
    # Generate outputs based on format preference
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    
    if ($OutputFormat -eq "json" -or $OutputFormat -eq "both") {
        $jsonFile = "document_summaries_$timestamp.json"
        $output | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonFile -Encoding UTF8
        Success "JSON output saved to: $jsonFile"
    }
    
    if ($OutputFormat -eq "markdown" -or $OutputFormat -eq "both") {
        $markdownFile = "document_summaries_$timestamp.md"
        $markdownContent = New-MarkdownReport -Summaries $summaries -SearchData $searchData
        $markdownContent | Out-File -FilePath $markdownFile -Encoding UTF8
        Success "Markdown output saved to: $markdownFile"
    }
    
    # Display summary statistics
    Log ""
    Success "Document summarization completed!"
    Log "📊 Processing Statistics:"
    Log "  • Total documents found: $($output.Statistics.TotalDocuments)"
    Log "  • Documents processed: $($output.Statistics.ProcessedDocuments)"
    Log "  • Successful summaries: $($output.Statistics.SuccessfulSummaries)"
    Log "  • Failed summaries: $($output.Statistics.FailedSummaries)"
    Log "  • Success rate: $([Math]::Round(($output.Statistics.SuccessfulSummaries / $output.Statistics.ProcessedDocuments) * 100, 1))%"
    
    # Show sample summaries
    $successfulSummaries = $summaries | Where-Object { -not $_.Error }
    if ($successfulSummaries.Count -gt 0) {
        Log ""
        Log "📋 Sample Summaries:"
        $successfulSummaries | Select-Object -First 3 | ForEach-Object {
            Log "  📄 $($_.DocumentName) ($($_.Source))"
            $summaryPreview = $_.Summary -split "`n" | Select-Object -First 2 | Join-String "`n"
            Log "     $($summaryPreview -replace "`n", " ")..."
        }
    }
    
    Log ""
    Success "✅ Document summarization completed successfully!"
    Log "Next: Ingest summaries into Fabric lakehouse"
    
    # Disconnect from Graph if connected
    try { 
        if (Get-MgContext) { 
            Disconnect-MgGraph | Out-Null 
        }
    } catch { }
    
} catch {
    Error "Document summarization failed: $_"
    
    # Cleanup on error
    try { 
        if (Get-MgContext) { 
            Disconnect-MgGraph | Out-Null 
        }
    } catch { }
    
    exit 1
}