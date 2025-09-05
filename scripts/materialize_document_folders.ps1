param(
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceId = "66bf0752-f3f3-4ec8-b8fa-29d1f885815e",
    
    [Parameter(Mandatory=$false)]
    [string]$LakehouseName = "bronze"
)

# Get access token for OneLake (uses Storage scope)
$storageToken = az account get-access-token --resource=https://storage.azure.com/ --query accessToken -o tsv
if (!$storageToken) {
    Write-Error "Failed to get storage access token"
    exit 1
}

# Get Fabric API token to resolve lakehouse ID
$fabricToken = az account get-access-token --resource=https://api.fabric.microsoft.com/ --query accessToken -o tsv
if (!$fabricToken) {
    Write-Error "Failed to get Fabric API access token"
    exit 1
}

Write-Host "[materialize] Getting lakehouse ID for '$LakehouseName'..."

$fabricHeaders = @{
    'Authorization' = "Bearer $fabricToken"
    'Content-Type' = 'application/json'
}

try {
    $lakehousesResponse = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/lakehouses" -Headers $fabricHeaders -Method Get
    $lakehouse = $lakehousesResponse.value | Where-Object { $_.displayName -eq $LakehouseName }
    
    if (!$lakehouse) {
        Write-Error "Lakehouse '$LakehouseName' not found in workspace"
        exit 1
    }
    
    $lakehouseId = $lakehouse.id
    Write-Host "[materialize] Found lakehouse '$LakehouseName' with ID: $lakehouseId"
    
} catch {
    Write-Error "Failed to get lakehouse information: $($_.Exception.Message)"
    exit 1
}

# OneLake headers for ADLS Gen2 API
$onelakeHeaders = @{
    'Authorization' = "Bearer $storageToken"
    'x-ms-version' = '2023-01-03'
}

# Base URI for OneLake access
$baseUri = "https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$lakehouseId"

# Define folder structure to create
$foldersToCreate = @(
    "Files/documents",
    "Files/documents/contracts", 
    "Files/documents/reports",
    "Files/documents/presentations"
)

Write-Host "[materialize] Creating folder structure in OneLake..."

foreach ($folderPath in $foldersToCreate) {
    try {
        # OneLake uses the ADLS Gen2 directory API
        $createFolderUri = "$baseUri/$folderPath" + "?resource=directory"
        
        Write-Host "[materialize] Creating folder: $folderPath"
        
        # Create directory using ADLS Gen2 API
        Invoke-RestMethod -Uri $createFolderUri -Headers $onelakeHeaders -Method PUT | Out-Null
        
        Write-Host "[materialize] ✓ Created folder: $folderPath"
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        if ($statusCode -eq 409) {
            Write-Host "[materialize] ✓ Folder already exists: $folderPath"
        } else {
            $errorMsg = $_.Exception.Message
            Write-Warning "[materialize] Failed to create folder '$folderPath': $errorMsg"
        }
    }
}

Write-Host "[materialize] Verifying folder structure..."

# List the Files folder to verify creation
try {
    $listUri = "$baseUri/Files" + "?resource=filesystem&recursive=true"
    $listResponse = Invoke-RestMethod -Uri $listUri -Headers $onelakeHeaders -Method GET
    
    Write-Host "[materialize] Current folder structure:"
    if ($listResponse.paths) {
        $listResponse.paths | Where-Object { $_.isDirectory } | ForEach-Object {
            Write-Host "  📁 $($_.name)"
        }
        
        $fileCount = ($listResponse.paths | Where-Object { !$_.isDirectory }).Count
        $folderCount = ($listResponse.paths | Where-Object { $_.isDirectory }).Count
        Write-Host "[materialize] Summary: $folderCount folders, $fileCount files"
    } else {
        Write-Host "  (No items found - this may be normal for a new lakehouse)"
    }
    
} catch {
    $errorMsg = $_.Exception.Message
    Write-Warning "[materialize] Could not list folder contents: $errorMsg"
}

Write-Host "[materialize] ✅ Folder materialization complete!"
Write-Host "[materialize] You can now drop PDF files into any of these folders:"
$foldersToCreate | ForEach-Object {
    Write-Host "  • $_"
}
