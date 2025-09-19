# Cleanup Temp Files Script
# This script cleans up temporary files while preserving recent pipeline runs

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,
    
    [Parameter(Mandatory = $false)]
    [int]$RetentionDays = 7
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "Starting cleanup of temporary files in: $WorkingDirectory"
    Write-Host "Retention period: $RetentionDays days"
    
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $totalSize = 0
    $fileCount = 0
    $directoriesProcessed = 0
    
    # Clean up old pipeline working directories
    $parentDir = Split-Path $WorkingDirectory -Parent
    if (Test-Path $parentDir) {
        $allWorkingDirs = Get-ChildItem -Path $parentDir -Directory -Filter "*pipeline_*" -ErrorAction SilentlyContinue
        
        foreach ($dir in $allWorkingDirs) {
            if ($dir.CreationTime -lt $cutoffDate) {
                Write-Host "Cleaning up old directory: $($dir.Name)"
                
                # Calculate size before deletion
                $dirSize = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $dirFileCount = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
                
                try {
                    Remove-Item -Path $dir.FullName -Recurse -Force
                    $totalSize += $dirSize
                    $fileCount += $dirFileCount
                    $directoriesProcessed++
                    Write-Host "✓ Removed directory: $($dir.Name) ($([Math]::Round($dirSize/1MB, 2)) MB, $dirFileCount files)"
                }
                catch {
                    Write-Warning "Failed to remove directory $($dir.Name): $($_.Exception.Message)"
                }
            }
            else {
                Write-Host "Keeping recent directory: $($dir.Name) (Created: $($dir.CreationTime))"
            }
        }
    }
    
    # Clean up specific temporary file types across the workspace
    $tempFilePatterns = @(
        "*.tmp",
        "*.temp", 
        "*_batch_*.json",
        "search_results_*.json",
        "metadata_*.json"
    )
    
    foreach ($pattern in $tempFilePatterns) {
        $tempFiles = Get-ChildItem -Path $WorkingDirectory -Filter $pattern -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -lt $cutoffDate }
        
        foreach ($file in $tempFiles) {
            try {
                $fileSize = $file.Length
                Remove-Item -Path $file.FullName -Force
                $totalSize += $fileSize
                $fileCount++
                Write-Host "✓ Removed temp file: $($file.Name) ($([Math]::Round($fileSize/1KB, 2)) KB)"
            }
            catch {
                Write-Warning "Failed to remove file $($file.Name): $($_.Exception.Message)"
            }
        }
    }
    
    # Clean up empty directories
    $emptyDirs = Get-ChildItem -Path $WorkingDirectory -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { (Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 }
    
    foreach ($emptyDir in $emptyDirs) {
        try {
            Remove-Item -Path $emptyDir.FullName -Force
            Write-Host "✓ Removed empty directory: $($emptyDir.Name)"
        }
        catch {
            Write-Warning "Failed to remove empty directory $($emptyDir.Name): $($_.Exception.Message)"
        }
    }
    
    # Generate cleanup summary
    $cleanupSummary = @{
        cleanup_timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        retention_days = $RetentionDays
        cutoff_date = $cutoffDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
        directories_processed = $directoriesProcessed
        files_removed = $fileCount
        total_size_removed_mb = [Math]::Round($totalSize / 1MB, 2)
        working_directory = $WorkingDirectory
        status = "Success"
    }
    
    # Save cleanup log
    $logFile = Join-Path $WorkingDirectory "cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $cleanupSummary | ConvertTo-Json -Depth 5 | Set-Content -Path $logFile -Encoding UTF8
    
    Write-Host "Cleanup completed successfully"
    Write-Host "Summary - Directories: $directoriesProcessed, Files: $fileCount, Size freed: $($cleanupSummary.total_size_removed_mb) MB"
    
    return $cleanupSummary
}
catch {
    Write-Error "Cleanup failed: $($_.Exception.Message)"
    return @{
        status = "Error"
        message = $_.Exception.Message
        cleanup_timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
}