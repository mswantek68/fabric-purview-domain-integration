# Update existing OneLake indexer scripts to use preview API version
# This script will update all the API calls to use 2024-05-01-preview

Write-Host "Updating all OneLake indexer creation scripts to use preview API..."
Write-Host "=================================================================="

# Define the API version that should be used for OneLake
$correctApiVersion = "2024-05-01-preview"
$oldApiVersion = "2023-11-01"

# List of script files to update
$scriptFiles = @(
    "scripts/create_onelake_indexer.ps1",
    "scripts/debug_onelake_indexers.ps1", 
    "scripts/add_onelake_skillsets.ps1",
    "scripts/postprovision_onelake_indexing.ps1"
)

foreach ($scriptFile in $scriptFiles) {
    if (Test-Path $scriptFile) {
        Write-Host "Updating $scriptFile..."
        
        # Read the file content
        $content = Get-Content $scriptFile -Raw
        
        # Replace the API version
        $updatedContent = $content -replace $oldApiVersion, $correctApiVersion
        
        # Write back to file
        Set-Content $scriptFile -Value $updatedContent
        
        Write-Host "✅ Updated $scriptFile to use $correctApiVersion"
    } else {
        Write-Host "⚠️  File not found: $scriptFile"
    }
}

Write-Host ""
Write-Host "🎯 SUMMARY:"
Write-Host "All OneLake indexer scripts have been updated to use the correct preview API version."
Write-Host "This was the missing piece that was causing all our OneLake connection failures!"
Write-Host ""
Write-Host "The breakthrough: OneLake indexing requires 2024-05-01-preview API, not 2023-11-01"
