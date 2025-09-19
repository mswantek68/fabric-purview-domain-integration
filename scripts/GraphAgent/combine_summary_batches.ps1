# Combine Summary Batches Script
# This script combines individual summary batch files into a single consolidated file

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,
    
    [Parameter(Mandatory = $true)]
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "Combining summary batches from: $WorkingDirectory"
    
    # Find all summary batch files
    $batchFiles = Get-ChildItem -Path $WorkingDirectory -Filter "summaries_batch_*.json" -ErrorAction SilentlyContinue
    
    if ($batchFiles.Count -eq 0) {
        Write-Warning "No summary batch files found in $WorkingDirectory"
        return @{
            Status = "Warning"
            Message = "No batch files to combine"
            TotalDocuments = 0
        }
    }
    
    Write-Host "Found $($batchFiles.Count) batch files to combine"
    
    # Initialize combined structure
    $combinedData = @{
        summaries = @()
        statistics = @{
            total_summaries = 0
            successful_summaries = 0
            failed_summaries = 0
            total_tokens_used = 0
            average_confidence = 0
            processing_time_seconds = 0
            batch_count = $batchFiles.Count
            combination_timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }
    
    $totalConfidence = 0
    $documentCount = 0
    
    # Process each batch file
    foreach ($batchFile in $batchFiles) {
        Write-Host "Processing batch file: $($batchFile.Name)"
        
        try {
            $batchContent = Get-Content $batchFile.FullName | ConvertFrom-Json
            
            if ($batchContent.summaries) {
                $combinedData.summaries += $batchContent.summaries
                $documentCount += $batchContent.summaries.Count
                
                # Sum confidence scores for average calculation
                $batchContent.summaries | ForEach-Object {
                    if ($_.confidence_score) {
                        $totalConfidence += $_.confidence_score
                    }
                }
            }
            
            if ($batchContent.statistics) {
                $combinedData.statistics.total_summaries += $batchContent.statistics.total_summaries ?? 0
                $combinedData.statistics.successful_summaries += $batchContent.statistics.successful_summaries ?? 0
                $combinedData.statistics.failed_summaries += $batchContent.statistics.failed_summaries ?? 0
                $combinedData.statistics.total_tokens_used += $batchContent.statistics.total_tokens_used ?? 0
                $combinedData.statistics.processing_time_seconds += $batchContent.statistics.processing_time_seconds ?? 0
            }
        }
        catch {
            Write-Warning "Failed to process batch file $($batchFile.Name): $($_.Exception.Message)"
            $combinedData.statistics.failed_summaries++
        }
    }
    
    # Calculate average confidence
    if ($documentCount -gt 0) {
        $combinedData.statistics.average_confidence = [Math]::Round($totalConfidence / $documentCount, 3)
    }
    
    # Save combined data
    $combinedData | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputFile -Encoding UTF8
    
    Write-Host "Successfully combined $documentCount summaries into: $OutputFile"
    
    return @{
        Status = "Success"
        TotalDocuments = $documentCount
        OutputFile = $OutputFile
        Statistics = $combinedData.statistics
    }
}
catch {
    Write-Error "Failed to combine summary batches: $($_.Exception.Message)"
    return @{
        Status = "Error"
        Message = $_.Exception.Message
        TotalDocuments = 0
    }
}