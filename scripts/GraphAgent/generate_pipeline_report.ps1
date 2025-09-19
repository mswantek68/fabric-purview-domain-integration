# Generate Pipeline Report Script
# This script generates a comprehensive report of the pipeline execution

param(
    [Parameter(Mandatory = $true)]
    [string]$PipelineRunId,
    
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,
    
    [Parameter(Mandatory = $true)]
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "Generating pipeline report for run: $PipelineRunId"
    
    # Initialize report structure
    $report = @{
        pipeline_run_id = $PipelineRunId
        execution_timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        working_directory = $WorkingDirectory
        stages = @{
            metadata_extraction = @{ status = "Unknown"; details = @{} }
            document_search = @{ status = "Unknown"; details = @{} }
            ai_summarization = @{ status = "Unknown"; details = @{} }
            lakehouse_ingestion = @{ status = "Unknown"; details = @{} }
        }
        summary = @{
            total_execution_time = ""
            documents_discovered = 0
            summaries_generated = 0
            records_ingested = 0
            success_rate = 0
        }
        files_generated = @()
        recommendations = @()
        errors = @()
    }
    
    # Check metadata extraction results
    $metadataFile = Join-Path $WorkingDirectory "metadata.json"
    if (Test-Path $metadataFile) {
        $metadata = Get-Content $metadataFile | ConvertFrom-Json
        $report.stages.metadata_extraction.status = "Success"
        $report.stages.metadata_extraction.details = @{
            domains_found = $metadata.extracted_domains.Count
            search_terms_generated = $metadata.graph_search_terms.Count
            data_sources = $metadata.data_sources -join ", "
        }
        $report.files_generated += $metadataFile
    }
    else {
        $report.stages.metadata_extraction.status = "Failed"
        $report.errors += "Metadata extraction file not found"
    }
    
    # Check search results
    $searchFile = Join-Path $WorkingDirectory "search_results.json"
    if (Test-Path $searchFile) {
        $searchResults = Get-Content $searchFile | ConvertFrom-Json
        $report.stages.document_search.status = "Success"
        $report.stages.document_search.details = @{
            total_results = $searchResults.statistics.total_results
            sharepoint_results = $searchResults.statistics.sharepoint_results ?? 0
            onedrive_results = $searchResults.statistics.onedrive_results ?? 0
            teams_results = $searchResults.statistics.teams_results ?? 0
            average_relevance = $searchResults.statistics.average_relevance
        }
        $report.summary.documents_discovered = $searchResults.statistics.total_results
        $report.files_generated += $searchFile
    }
    else {
        $report.stages.document_search.status = "Failed"
        $report.errors += "Search results file not found"
    }
    
    # Check combined summaries
    $summariesFile = Join-Path $WorkingDirectory "combined_summaries.json"
    if (Test-Path $summariesFile) {
        $summaries = Get-Content $summariesFile | ConvertFrom-Json
        $report.stages.ai_summarization.status = "Success"
        $report.stages.ai_summarization.details = @{
            total_summaries = $summaries.statistics.total_summaries
            successful_summaries = $summaries.statistics.successful_summaries
            failed_summaries = $summaries.statistics.failed_summaries
            average_confidence = $summaries.statistics.average_confidence
            total_tokens_used = $summaries.statistics.total_tokens_used
            processing_time_seconds = $summaries.statistics.processing_time_seconds
        }
        $report.summary.summaries_generated = $summaries.statistics.successful_summaries
        
        # Calculate success rate
        if ($summaries.statistics.total_summaries -gt 0) {
            $report.summary.success_rate = [Math]::Round(($summaries.statistics.successful_summaries / $summaries.statistics.total_summaries) * 100, 2)
        }
        
        $report.files_generated += $summariesFile
    }
    else {
        $report.stages.ai_summarization.status = "Failed"
        $report.errors += "Combined summaries file not found"
    }
    
    # Check for lakehouse ingestion logs (would be created by the ingestion script)
    $ingestionLogPattern = Join-Path $WorkingDirectory "ingestion_*.log"
    $ingestionLogs = Get-ChildItem -Path $ingestionLogPattern -ErrorAction SilentlyContinue
    if ($ingestionLogs) {
        $report.stages.lakehouse_ingestion.status = "Success"
        # Parse ingestion details from log files if needed
        $report.stages.lakehouse_ingestion.details = @{
            log_files = $ingestionLogs.Count
            latest_log = $ingestionLogs[-1].Name
        }
    }
    
    # Generate recommendations based on results
    if ($report.summary.documents_discovered -eq 0) {
        $report.recommendations += "No documents were discovered. Consider broadening search terms or checking data source permissions."
    }
    
    if ($report.summary.success_rate -lt 80) {
        $report.recommendations += "AI summarization success rate is below 80%. Consider reviewing document formats and OpenAI model configuration."
    }
    
    if ($report.stages.metadata_extraction.details.domains_found -lt 5) {
        $report.recommendations += "Few domain identifiers were extracted. Consider enriching lakehouse metadata or manual domain specification."
    }
    
    # Calculate overall execution time (approximate)
    $startTime = (Get-Date).AddMinutes(-30) # Approximate pipeline duration
    $endTime = Get-Date
    $report.summary.total_execution_time = "{0:mm\:ss}" -f ($endTime - $startTime)
    
    # Add performance insights
    $report.performance_insights = @{
        documents_per_minute = if ($report.stages.ai_summarization.details.processing_time_seconds -gt 0) {
            [Math]::Round(($report.summary.summaries_generated / ($report.stages.ai_summarization.details.processing_time_seconds / 60)), 2)
        } else { 0 }
        average_tokens_per_document = if ($report.summary.summaries_generated -gt 0) {
            [Math]::Round(($report.stages.ai_summarization.details.total_tokens_used / $report.summary.summaries_generated), 0)
        } else { 0 }
    }
    
    # Save report
    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputFile -Encoding UTF8
    
    Write-Host "Pipeline report generated successfully: $OutputFile"
    Write-Host "Summary - Documents: $($report.summary.documents_discovered), Summaries: $($report.summary.summaries_generated), Success Rate: $($report.summary.success_rate)%"
    
    return @{
        Status = "Success"
        ReportFile = $OutputFile
        Summary = $report.summary
    }
}
catch {
    Write-Error "Failed to generate pipeline report: $($_.Exception.Message)"
    return @{
        Status = "Error"
        Message = $_.Exception.Message
    }
}