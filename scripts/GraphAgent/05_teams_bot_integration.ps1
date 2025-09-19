# Teams Bot Integration for Document Discovery Agent
# This PowerShell script implements the Teams Bot Framework integration

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "config.json",
    
    [Parameter(Mandatory = $false)]
    [string]$BotEndpoint = $env:BOT_ENDPOINT,
    
    [Parameter(Mandatory = $false)]
    [string]$AppId = $env:TEAMS_APP_ID,
    
    [Parameter(Mandatory = $false)]
    [string]$AppPassword = $env:TEAMS_APP_PASSWORD,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputFormat = "adaptive_card"
)

# Import required modules and dependencies
Import-Module Microsoft.Graph.Authentication -Force
Import-Module PnP.PowerShell -Force

# Initialize configuration and global variables
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$script:Config = @{}
$script:BotAdapter = $null
$script:ActivityHandler = $null

# Logging configuration
$LogPath = "logs/teams_bot_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
if (!(Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logEntry
    Write-Host $logEntry
}

function Initialize-BotConfiguration {
    Write-Log "Initializing Teams Bot configuration"
    
    try {
        # Load configuration from file if exists
        if (Test-Path $ConfigPath) {
            $script:Config = Get-Content $ConfigPath | ConvertFrom-Json -AsHashtable
            Write-Log "Loaded configuration from $ConfigPath"
        }
        
        # Set default configuration values
        $script:Config = @{
            BotEndpoint = $BotEndpoint ?? "https://your-bot-app.azurewebsites.net"
            AppId = $AppId ?? $env:TEAMS_APP_ID
            AppPassword = $AppPassword ?? $env:TEAMS_APP_PASSWORD
            TenantId = $env:AZURE_TENANT_ID
            SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
            ResourceGroupName = $env:AZURE_RESOURCE_GROUP_NAME
            FabricWorkspaceName = $env:FABRIC_WORKSPACE_NAME
            FabricLakehouseName = $env:FABRIC_LAKEHOUSE_NAME
            OpenAIEndpoint = $env:AZURE_OPENAI_ENDPOINT
            OpenAIApiKey = $env:AZURE_OPENAI_API_KEY
            OpenAIDeployment = $env:AZURE_OPENAI_DEPLOYMENT ?? "gpt-4"
            AgentScriptsPath = "./scripts/GraphAgent"
            MaxConcurrentRequests = 5
            RequestTimeoutSeconds = 300
            CacheExpirationMinutes = 30
        }
        
        # Validate required configuration
        $requiredKeys = @("AppId", "AppPassword", "TenantId", "OpenAIEndpoint")
        foreach ($key in $requiredKeys) {
            if (-not $script:Config[$key]) {
                throw "Missing required configuration: $key"
            }
        }
        
        Write-Log "Bot configuration initialized successfully"
        return $true
    }
    catch {
        Write-Log "Failed to initialize bot configuration: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Register-ActivityHandlers {
    Write-Log "Registering Teams activity handlers"
    
    $script:ActivityHandler = @{
        OnMessage = {
            param($turnContext, $cancellationToken)
            return Handle-MessageActivity -TurnContext $turnContext
        }
        OnMembersAdded = {
            param($membersAdded, $turnContext, $cancellationToken)
            return Handle-MembersAdded -MembersAdded $membersAdded -TurnContext $turnContext
        }
        OnTeamsTaskModuleSubmit = {
            param($turnContext, $taskModuleRequest, $cancellationToken)
            return Handle-AdaptiveCardSubmit -TurnContext $turnContext -TaskModuleRequest $taskModuleRequest
        }
    }
    
    Write-Log "Activity handlers registered successfully"
}

function Handle-MessageActivity {
    param($TurnContext)
    
    Write-Log "Processing message activity: $($TurnContext.Activity.Text)"
    
    try {
        $userMessage = $TurnContext.Activity.Text.Trim()
        $userId = $TurnContext.Activity.From.Id
        $channelId = $TurnContext.Activity.ChannelId
        
        # Parse command and parameters
        $command = Parse-BotCommand -Message $userMessage
        
        # Route to appropriate handler
        switch ($command.Intent) {
            "search" {
                return Invoke-DocumentSearch -Command $command -TurnContext $TurnContext
            }
            "analyze" {
                return Invoke-DocumentAnalysis -Command $command -TurnContext $TurnContext
            }
            "domains" {
                return Invoke-DomainExtraction -Command $command -TurnContext $TurnContext
            }
            "help" {
                return Send-HelpMessage -TurnContext $TurnContext
            }
            "interactive" {
                return Send-InteractiveCard -TurnContext $TurnContext
            }
            default {
                return Send-UnknownCommandMessage -TurnContext $TurnContext -UserMessage $userMessage
            }
        }
    }
    catch {
        Write-Log "Error handling message activity: $($_.Exception.Message)" "ERROR"
        return Send-ErrorMessage -TurnContext $TurnContext -Error $_.Exception.Message
    }
}

function Parse-BotCommand {
    param([string]$Message)
    
    # Remove bot mention if present
    $cleanMessage = $Message -replace '@DocumentDiscoveryAgent\s*', '' -replace '^/\s*', ''
    
    # Define command patterns
    $patterns = @{
        search = @{
            Pattern = '^(search|find|discover)\s+(.+)$'
            Intent = "search"
        }
        analyze = @{
            Pattern = '^(analyze|analysis)\s+(.+)$'
            Intent = "analyze"
        }
        domains = @{
            Pattern = '^(domains|extract|metadata)$'
            Intent = "domains"
        }
        help = @{
            Pattern = '^(help|\?)$'
            Intent = "help"
        }
        interactive = @{
            Pattern = '^(card|interactive|configure)$'
            Intent = "interactive"
        }
    }
    
    foreach ($patternName in $patterns.Keys) {
        $pattern = $patterns[$patternName]
        if ($cleanMessage -match $pattern.Pattern) {
            return @{
                Intent = $pattern.Intent
                Parameters = if ($Matches.Count -gt 2) { $Matches[2] } else { $null }
                RawMessage = $Message
                CleanMessage = $cleanMessage
            }
        }
    }
    
    # Default to intelligent analysis if no pattern matches but contains organization names
    if ($cleanMessage -match '\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b') {
        return @{
            Intent = "search"
            Parameters = $cleanMessage
            RawMessage = $Message
            CleanMessage = $cleanMessage
        }
    }
    
    return @{
        Intent = "unknown"
        Parameters = $cleanMessage
        RawMessage = $Message
        CleanMessage = $cleanMessage
    }
}

function Invoke-DocumentSearch {
    param($Command, $TurnContext)
    
    Write-Log "Executing document search for: $($Command.Parameters)"
    
    try {
        # Send typing indicator
        Send-TypingIndicator -TurnContext $TurnContext
        
        # Execute search workflow
        $searchResults = Start-SearchWorkflow -SearchTerms $Command.Parameters
        
        # Generate response card
        $responseCard = New-SearchResultsCard -Results $searchResults
        
        # Send results to user
        return Send-AdaptiveCard -TurnContext $TurnContext -Card $responseCard
    }
    catch {
        Write-Log "Error in document search: $($_.Exception.Message)" "ERROR"
        return Send-ErrorMessage -TurnContext $TurnContext -Error "Failed to execute document search: $($_.Exception.Message)"
    }
}

function Invoke-DocumentAnalysis {
    param($Command, $TurnContext)
    
    Write-Log "Executing document analysis for: $($Command.Parameters)"
    
    try {
        Send-TypingIndicator -TurnContext $TurnContext
        
        # Execute full analysis workflow
        $analysisResults = Start-AnalysisWorkflow -OrganizationName $Command.Parameters
        
        # Generate comprehensive results card
        $responseCard = New-AnalysisResultsCard -Results $analysisResults
        
        return Send-AdaptiveCard -TurnContext $TurnContext -Card $responseCard
    }
    catch {
        Write-Log "Error in document analysis: $($_.Exception.Message)" "ERROR"
        return Send-ErrorMessage -TurnContext $TurnContext -Error "Failed to execute document analysis: $($_.Exception.Message)"
    }
}

function Invoke-DomainExtraction {
    param($Command, $TurnContext)
    
    Write-Log "Executing domain extraction"
    
    try {
        Send-TypingIndicator -TurnContext $TurnContext
        
        # Execute metadata extraction
        $domainResults = Start-DomainExtractionWorkflow
        
        # Generate domain results card
        $responseCard = New-DomainResultsCard -Results $domainResults
        
        return Send-AdaptiveCard -TurnContext $TurnContext -Card $responseCard
    }
    catch {
        Write-Log "Error in domain extraction: $($_.Exception.Message)" "ERROR"
        return Send-ErrorMessage -TurnContext $TurnContext -Error "Failed to extract domains: $($_.Exception.Message)"
    }
}

function Start-SearchWorkflow {
    param([string]$SearchTerms)
    
    Write-Log "Starting search workflow for terms: $SearchTerms"
    
    # Create temporary files for workflow
    $tempDir = "temp/workflow_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    try {
        # Step 1: Execute Graph search
        $searchScript = Join-Path $script:Config.AgentScriptsPath "02_search_graph_documents.ps1"
        $searchOutputFile = Join-Path $tempDir "search_results.json"
        
        $searchParams = @{
            SearchTerms = $SearchTerms
            OutputFile = $searchOutputFile
            MaxResults = 20
            DaysBack = 30
        }
        
        Write-Log "Executing search script: $searchScript"
        $searchResult = & $searchScript @searchParams
        
        if (Test-Path $searchOutputFile) {
            $searchData = Get-Content $searchOutputFile | ConvertFrom-Json
            
            # Step 2: Generate quick summaries for top results
            if ($searchData.results.Count -gt 0) {
                $summarizeScript = Join-Path $script:Config.AgentScriptsPath "03_summarize_documents.ps1"
                $summaryOutputFile = Join-Path $tempDir "summaries.json"
                
                $summaryParams = @{
                    InputFile = $searchOutputFile
                    OutputFile = $summaryOutputFile
                    MaxDocuments = 10
                    OutputFormat = "json"
                }
                
                Write-Log "Executing summary script: $summarizeScript"
                $summaryResult = & $summarizeScript @summaryParams
                
                if (Test-Path $summaryOutputFile) {
                    $summaryData = Get-Content $summaryOutputFile | ConvertFrom-Json
                    
                    return @{
                        SearchResults = $searchData
                        Summaries = $summaryData
                        Status = "Success"
                        WorkflowFiles = @{
                            SearchResults = $searchOutputFile
                            Summaries = $summaryOutputFile
                        }
                    }
                }
            }
            
            return @{
                SearchResults = $searchData
                Summaries = $null
                Status = "PartialSuccess"
                Message = "Search completed but summaries failed"
            }
        }
        else {
            throw "Search script did not produce output file"
        }
    }
    finally {
        # Cleanup temporary files (optional - keep for debugging)
        # Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Workflow files preserved in: $tempDir"
    }
}

function Start-AnalysisWorkflow {
    param([string]$OrganizationName)
    
    Write-Log "Starting full analysis workflow for organization: $OrganizationName"
    
    $tempDir = "temp/analysis_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    try {
        # Step 1: Extract domain metadata
        $metadataScript = Join-Path $script:Config.AgentScriptsPath "01_extract_domain_metadata.ps1"
        $metadataOutputFile = Join-Path $tempDir "metadata.json"
        
        Write-Log "Executing metadata extraction"
        $metadataResult = & $metadataScript -OutputFile $metadataOutputFile
        
        # Step 2: Enhanced search using metadata + organization name
        $searchTerms = $OrganizationName
        if (Test-Path $metadataOutputFile) {
            $metadataData = Get-Content $metadataOutputFile | ConvertFrom-Json
            if ($metadataData.graph_search_terms) {
                $searchTerms += "," + ($metadataData.graph_search_terms -join ",")
            }
        }
        
        # Execute comprehensive search
        $searchScript = Join-Path $script:Config.AgentScriptsPath "02_search_graph_documents.ps1"
        $searchOutputFile = Join-Path $tempDir "search_results.json"
        
        $searchParams = @{
            SearchTerms = $searchTerms
            OutputFile = $searchOutputFile
            MaxResults = 50
            DaysBack = 90
        }
        
        Write-Log "Executing comprehensive search"
        $searchResult = & $searchScript @searchParams
        
        # Step 3: Generate detailed summaries
        $summarizeScript = Join-Path $script:Config.AgentScriptsPath "03_summarize_documents.ps1"
        $summaryOutputFile = Join-Path $tempDir "summaries.json"
        
        $summaryParams = @{
            InputFile = $searchOutputFile
            OutputFile = $summaryOutputFile
            MaxDocuments = 30
            OutputFormat = "both"
        }
        
        Write-Log "Executing detailed summarization"
        $summaryResult = & $summarizeScript @summaryParams
        
        # Step 4: Ingest into lakehouse
        $ingestScript = Join-Path $script:Config.AgentScriptsPath "04_ingest_lakehouse.ps1"
        $ingestParams = @{
            InputFile = $summaryOutputFile
            LakehouseName = $script:Config.FabricLakehouseName
            WorkspaceName = $script:Config.FabricWorkspaceName
            TableName = "document_summaries_$(Get-Date -Format 'yyyyMMdd')"
            UpdateMode = "append"
        }
        
        Write-Log "Executing lakehouse ingestion"
        $ingestResult = & $ingestScript @ingestParams
        
        # Compile results
        $results = @{
            Metadata = if (Test-Path $metadataOutputFile) { Get-Content $metadataOutputFile | ConvertFrom-Json } else { $null }
            SearchResults = if (Test-Path $searchOutputFile) { Get-Content $searchOutputFile | ConvertFrom-Json } else { $null }
            Summaries = if (Test-Path $summaryOutputFile) { Get-Content $summaryOutputFile | ConvertFrom-Json } else { $null }
            IngestionResult = $ingestResult
            Status = "Success"
            WorkflowFiles = @{
                Metadata = $metadataOutputFile
                SearchResults = $searchOutputFile
                Summaries = $summaryOutputFile
            }
        }
        
        return $results
    }
    catch {
        Write-Log "Error in analysis workflow: $($_.Exception.Message)" "ERROR"
        return @{
            Status = "Error"
            Message = $_.Exception.Message
        }
    }
}

function Start-DomainExtractionWorkflow {
    Write-Log "Starting domain extraction workflow"
    
    $tempDir = "temp/domains_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    try {
        $metadataScript = Join-Path $script:Config.AgentScriptsPath "01_extract_domain_metadata.ps1"
        $outputFile = Join-Path $tempDir "extracted_domains.json"
        
        $params = @{
            OutputFile = $outputFile
            LakehouseName = $script:Config.FabricLakehouseName
            WorkspaceName = $script:Config.FabricWorkspaceName
        }
        
        Write-Log "Executing domain extraction script"
        $result = & $metadataScript @params
        
        if (Test-Path $outputFile) {
            $domainData = Get-Content $outputFile | ConvertFrom-Json
            return @{
                ExtractedDomains = $domainData
                Status = "Success"
                OutputFile = $outputFile
            }
        }
        else {
            throw "Domain extraction script did not produce output"
        }
    }
    catch {
        Write-Log "Error in domain extraction workflow: $($_.Exception.Message)" "ERROR"
        return @{
            Status = "Error"
            Message = $_.Exception.Message
        }
    }
}

function New-SearchResultsCard {
    param($Results)
    
    $resultCount = if ($Results.SearchResults) { $Results.SearchResults.statistics.total_results } else { 0 }
    $topResults = ""
    
    if ($Results.SearchResults -and $Results.SearchResults.results) {
        $topResults = ($Results.SearchResults.results[0..4] | ForEach-Object {
            "• **$($_.name)** - $($_.source) - $(([DateTime]$_.last_modified).ToString('MM/dd/yyyy'))"
        }) -join "`n"
    }
    
    $card = @{
        type = "AdaptiveCard"
        version = "1.3"
        body = @(
            @{
                type = "TextBlock"
                text = "📄 Document Search Results"
                weight = "Bolder"
                size = "Medium"
                color = "Accent"
            },
            @{
                type = "FactSet"
                facts = @(
                    @{ title = "Documents Found"; value = "$resultCount" },
                    @{ title = "Sources Searched"; value = "SharePoint, OneDrive, Teams" },
                    @{ title = "Search Time"; value = "$(Get-Date -Format 'HH:mm:ss')" }
                )
            }
        )
        actions = @()
    }
    
    if ($resultCount -gt 0) {
        $card.body += @{
            type = "Container"
            items = @(
                @{
                    type = "TextBlock"
                    text = "**Top Results:**"
                    weight = "Bolder"
                },
                @{
                    type = "TextBlock"
                    text = $topResults
                    wrap = $true
                }
            )
        }
        
        $card.actions = @(
            @{
                type = "Action.Submit"
                title = "📝 Generate Summaries"
                data = @{ action = "generate_summaries"; workflow_data = $Results }
            },
            @{
                type = "Action.Submit"
                title = "💾 Save to Lakehouse"
                data = @{ action = "save_lakehouse"; workflow_data = $Results }
            },
            @{
                type = "Action.Submit"
                title = "🔍 Refine Search"
                data = @{ action = "refine_search" }
            }
        )
    }
    else {
        $card.body += @{
            type = "TextBlock"
            text = "No documents found matching your search criteria. Try different search terms or check your permissions."
            wrap = $true
            color = "Warning"
        }
        
        $card.actions = @(
            @{
                type = "Action.Submit"
                title = "🔍 Try Different Search"
                data = @{ action = "new_search" }
            }
        )
    }
    
    return $card
}

function New-AnalysisResultsCard {
    param($Results)
    
    $card = @{
        type = "AdaptiveCard"
        version = "1.3"
        body = @(
            @{
                type = "TextBlock"
                text = "🎯 Document Analysis Complete"
                weight = "Bolder"
                size = "Medium"
                color = "Good"
            }
        )
        actions = @()
    }
    
    if ($Results.Status -eq "Success") {
        $facts = @(
            @{ title = "Analysis Status"; value = "✅ Complete" }
        )
        
        if ($Results.SearchResults) {
            $facts += @{ title = "Documents Analyzed"; value = "$($Results.SearchResults.statistics.total_results)" }
        }
        
        if ($Results.Summaries) {
            $facts += @{ title = "Summaries Generated"; value = "$($Results.Summaries.statistics.successful_summaries)" }
        }
        
        if ($Results.IngestionResult) {
            $facts += @{ title = "Lakehouse Records"; value = "$($Results.IngestionResult.statistics.records_ingested)" }
        }
        
        $card.body += @{
            type = "FactSet"
            facts = $facts
        }
        
        # Add key insights if available
        if ($Results.Summaries -and $Results.Summaries.summaries) {
            $keyInsights = ($Results.Summaries.summaries[0..2] | ForEach-Object {
                "• **$($_.document_name)**: $($_.key_points[0])"
            }) -join "`n"
            
            $card.body += @{
                type = "Container"
                items = @(
                    @{
                        type = "TextBlock"
                        text = "**Key Insights:**"
                        weight = "Bolder"
                    },
                    @{
                        type = "TextBlock"
                        text = $keyInsights
                        wrap = $true
                    }
                )
            }
        }
        
        $card.actions = @(
            @{
                type = "Action.Submit"
                title = "📊 View Full Report"
                data = @{ action = "view_report"; results = $Results }
            },
            @{
                type = "Action.Submit"
                title = "📤 Export Results"
                data = @{ action = "export_results"; results = $Results }
            },
            @{
                type = "Action.Submit"
                title = "🔄 Start New Analysis"
                data = @{ action = "new_analysis" }
            }
        )
    }
    else {
        $card.body += @{
            type = "TextBlock"
            text = "❌ Analysis failed: $($Results.Message)"
            wrap = $true
            color = "Attention"
        }
        
        $card.actions = @(
            @{
                type = "Action.Submit"
                title = "🔄 Retry Analysis"
                data = @{ action = "retry_analysis" }
            }
        )
    }
    
    return $card
}

function New-DomainResultsCard {
    param($Results)
    
    $card = @{
        type = "AdaptiveCard"
        version = "1.3"
        body = @(
            @{
                type = "TextBlock"
                text = "🏢 Domain Extraction Results"
                weight = "Bolder"
                size = "Medium"
                color = "Accent"
            }
        )
        actions = @()
    }
    
    if ($Results.Status -eq "Success" -and $Results.ExtractedDomains) {
        $domains = $Results.ExtractedDomains.extracted_domains
        $searchTerms = $Results.ExtractedDomains.graph_search_terms
        
        $card.body += @{
            type = "FactSet"
            facts = @(
                @{ title = "Domains Found"; value = "$($domains.Count)" },
                @{ title = "Search Terms Generated"; value = "$($searchTerms.Count)" },
                @{ title = "Extraction Time"; value = "$(Get-Date -Format 'HH:mm:ss')" }
            )
        }
        
        if ($domains.Count -gt 0) {
            $domainList = ($domains[0..9] | ForEach-Object { "• $_" }) -join "`n"
            
            $card.body += @{
                type = "Container"
                items = @(
                    @{
                        type = "TextBlock"
                        text = "**Extracted Domains:**"
                        weight = "Bolder"
                    },
                    @{
                        type = "TextBlock"
                        text = $domainList
                        wrap = $true
                    }
                )
            }
        }
        
        $card.actions = @(
            @{
                type = "Action.Submit"
                title = "🔍 Search Documents"
                data = @{ action = "search_domains"; domains = $domains }
            },
            @{
                type = "Action.Submit"
                title = "📊 Analyze All Domains"
                data = @{ action = "analyze_domains"; domains = $domains }
            }
        )
    }
    else {
        $card.body += @{
            type = "TextBlock"
            text = "❌ Domain extraction failed: $($Results.Message)"
            wrap = $true
            color = "Attention"
        }
        
        $card.actions = @(
            @{
                type = "Action.Submit"
                title = "🔄 Retry Extraction"
                data = @{ action = "retry_extraction" }
            }
        )
    }
    
    return $card
}

function Send-HelpMessage {
    param($TurnContext)
    
    $helpCard = @{
        type = "AdaptiveCard"
        version = "1.3"
        body = @(
            @{
                type = "TextBlock"
                text = "🤖 Document Discovery Agent Help"
                weight = "Bolder"
                size = "Large"
                color = "Accent"
            },
            @{
                type = "TextBlock"
                text = "I can help you discover and analyze organizational documents across Microsoft 365. Here are the available commands:"
                wrap = $true
            },
            @{
                type = "FactSet"
                facts = @(
                    @{ title = "search [organization]"; value = "Search for documents mentioning a specific organization" },
                    @{ title = "analyze [organization]"; value = "Comprehensive analysis with AI summaries and lakehouse storage" },
                    @{ title = "domains"; value = "Extract organizational identifiers from your lakehouse metadata" },
                    @{ title = "card"; value = "Open interactive configuration card" },
                    @{ title = "help"; value = "Show this help message" }
                )
            },
            @{
                type = "TextBlock"
                text = "**Examples:**"
                weight = "Bolder"
            },
            @{
                type = "TextBlock"
                text = "• `search Contoso`\n• `analyze Microsoft Partner Network`\n• `domains`\n• `card`"
                wrap = $true
            }
        )
        actions = @(
            @{
                type = "Action.Submit"
                title = "🎛️ Interactive Configuration"
                data = @{ action = "show_config_card" }
            },
            @{
                type = "Action.Submit"
                title = "🏢 Extract Domains"
                data = @{ action = "extract_domains" }
            }
        )
    }
    
    return Send-AdaptiveCard -TurnContext $TurnContext -Card $helpCard
}

function Send-InteractiveCard {
    param($TurnContext)
    
    # Load the search parameters card from agent definition
    $agentDefinitionPath = Join-Path $script:Config.AgentScriptsPath "agent_definition.json"
    if (Test-Path $agentDefinitionPath) {
        $agentDef = Get-Content $agentDefinitionPath | ConvertFrom-Json
        $searchCard = $agentDef.adaptive_cards | Where-Object { $_.name -eq "search_parameters_card" }
        
        if ($searchCard) {
            return Send-AdaptiveCard -TurnContext $TurnContext -Card $searchCard.card_schema
        }
    }
    
    # Fallback to basic interactive card
    $card = @{
        type = "AdaptiveCard"
        version = "1.3"
        body = @(
            @{
                type = "TextBlock"
                text = "🎛️ Document Search Configuration"
                weight = "Bolder"
                size = "Medium"
            },
            @{
                type = "Input.Text"
                id = "search_terms"
                label = "Search Terms (comma-separated)"
                placeholder = "e.g., Contoso, Fabrikam, Microsoft"
                isRequired = $true
            },
            @{
                type = "Input.Number"
                id = "days_back"
                label = "Search Period (days back)"
                value = 90
                min = 1
                max = 365
            }
        )
        actions = @(
            @{
                type = "Action.Submit"
                title = "🔍 Start Search"
                data = @{ action = "start_configured_search" }
            }
        )
    }
    
    return Send-AdaptiveCard -TurnContext $TurnContext -Card $card
}

function Handle-AdaptiveCardSubmit {
    param($TurnContext, $TaskModuleRequest)
    
    Write-Log "Processing adaptive card submission"
    
    try {
        $submitData = $TaskModuleRequest.Data
        
        switch ($submitData.action) {
            "start_configured_search" {
                $searchParams = @{
                    SearchTerms = $submitData.search_terms
                    DaysBack = $submitData.days_back ?? 90
                    MaxResults = $submitData.max_results ?? 50
                }
                
                $results = Start-SearchWorkflow -SearchTerms $searchParams.SearchTerms
                $responseCard = New-SearchResultsCard -Results $results
                return Send-AdaptiveCard -TurnContext $TurnContext -Card $responseCard
            }
            "generate_summaries" {
                # Handle summary generation request
                $workflowData = $submitData.workflow_data
                # Implementation depends on stored workflow state
                return Send-StatusMessage -TurnContext $TurnContext -Message "Generating summaries..." -Type "Info"
            }
            "save_lakehouse" {
                # Handle lakehouse save request
                return Send-StatusMessage -TurnContext $TurnContext -Message "Saving to lakehouse..." -Type "Info"
            }
            default {
                return Send-StatusMessage -TurnContext $TurnContext -Message "Unknown action: $($submitData.action)" -Type "Warning"
            }
        }
    }
    catch {
        Write-Log "Error handling adaptive card submit: $($_.Exception.Message)" "ERROR"
        return Send-ErrorMessage -TurnContext $TurnContext -Error "Failed to process card submission: $($_.Exception.Message)"
    }
}

function Send-AdaptiveCard {
    param($TurnContext, $Card)
    
    try {
        $attachment = @{
            ContentType = "application/vnd.microsoft.card.adaptive"
            Content = $Card
        }
        
        $activity = @{
            Type = "message"
            Attachments = @($attachment)
        }
        
        # In a real implementation, this would use the Bot Framework to send the activity
        Write-Log "Sending adaptive card to user"
        return $activity
    }
    catch {
        Write-Log "Error sending adaptive card: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Send-StatusMessage {
    param($TurnContext, [string]$Message, [string]$Type = "Info")
    
    $color = switch ($Type) {
        "Info" { "Accent" }
        "Success" { "Good" }
        "Warning" { "Warning" }
        "Error" { "Attention" }
        default { "Default" }
    }
    
    $emoji = switch ($Type) {
        "Info" { "ℹ️" }
        "Success" { "✅" }
        "Warning" { "⚠️" }
        "Error" { "❌" }
        default { "📝" }
    }
    
    $card = @{
        type = "AdaptiveCard"
        version = "1.3"
        body = @(
            @{
                type = "TextBlock"
                text = "$emoji $Message"
                wrap = $true
                color = $color
            }
        )
    }
    
    return Send-AdaptiveCard -TurnContext $TurnContext -Card $card
}

function Send-ErrorMessage {
    param($TurnContext, [string]$Error)
    
    return Send-StatusMessage -TurnContext $TurnContext -Message "Error: $Error" -Type "Error"
}

function Send-TypingIndicator {
    param($TurnContext)
    
    # Implementation would send typing indicator to Teams
    Write-Log "Sending typing indicator"
}

function Handle-MembersAdded {
    param($MembersAdded, $TurnContext)
    
    Write-Log "New members added to conversation"
    
    $welcomeCard = @{
        type = "AdaptiveCard"
        version = "1.3"
        body = @(
            @{
                type = "TextBlock"
                text = "👋 Welcome to Document Discovery Agent!"
                weight = "Bolder"
                size = "Large"
                color = "Accent"
            },
            @{
                type = "TextBlock"
                text = "I help you discover and analyze organizational documents across Microsoft 365. Type `help` to see available commands or `card` for interactive configuration."
                wrap = $true
            }
        )
        actions = @(
            @{
                type = "Action.Submit"
                title = "📖 Show Help"
                data = @{ action = "show_help" }
            },
            @{
                type = "Action.Submit"
                title = "🎛️ Interactive Setup"
                data = @{ action = "show_config_card" }
            }
        )
    }
    
    return Send-AdaptiveCard -TurnContext $TurnContext -Card $welcomeCard
}

function Send-UnknownCommandMessage {
    param($TurnContext, [string]$UserMessage)
    
    $card = @{
        type = "AdaptiveCard"
        version = "1.3"
        body = @(
            @{
                type = "TextBlock"
                text = "🤔 I didn't understand that command"
                weight = "Bolder"
                color = "Warning"
            },
            @{
                type = "TextBlock"
                text = "You said: `$UserMessage`"
                wrap = $true
            },
            @{
                type = "TextBlock"
                text = "Try one of these commands: `search [organization]`, `analyze [organization]`, `domains`, `help`, or `card`"
                wrap = $true
            }
        )
        actions = @(
            @{
                type = "Action.Submit"
                title = "📖 Show Help"
                data = @{ action = "show_help" }
            },
            @{
                type = "Action.Submit"
                title = "🎛️ Interactive Setup"
                data = @{ action = "show_config_card" }
            }
        )
    }
    
    return Send-AdaptiveCard -TurnContext $TurnContext -Card $card
}

# Main execution function
function Start-TeamsBot {
    Write-Log "Starting Teams Bot integration"
    
    try {
        # Initialize configuration
        if (-not (Initialize-BotConfiguration)) {
            throw "Failed to initialize bot configuration"
        }
        
        # Register activity handlers
        Register-ActivityHandlers
        
        Write-Log "Teams Bot integration initialized successfully"
        Write-Log "Bot endpoint: $($script:Config.BotEndpoint)"
        Write-Log "App ID: $($script:Config.AppId)"
        
        # In a real implementation, this would start the Bot Framework adapter
        Write-Log "Bot is ready to handle Teams messages"
        
        return @{
            Status = "Success"
            Message = "Teams Bot integration started successfully"
            Configuration = $script:Config
        }
    }
    catch {
        Write-Log "Failed to start Teams Bot: $($_.Exception.Message)" "ERROR"
        return @{
            Status = "Error"
            Message = $_.Exception.Message
        }
    }
}

# Execute if running as standalone script
if ($MyInvocation.InvocationName -ne '.') {
    $result = Start-TeamsBot
    
    if ($OutputFormat -eq "json") {
        $result | ConvertTo-Json -Depth 5
    }
    else {
        Write-Host "Teams Bot Integration Status: $($result.Status)"
        if ($result.Message) {
            Write-Host "Message: $($result.Message)"
        }
    }
}

# Export functions for module usage
Export-ModuleMember -Function @(
    'Start-TeamsBot',
    'Handle-MessageActivity',
    'Handle-AdaptiveCardSubmit',
    'Send-AdaptiveCard'
)