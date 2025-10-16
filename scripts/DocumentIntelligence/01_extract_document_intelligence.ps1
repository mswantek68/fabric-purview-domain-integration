[CmdletBinding()]
param(
    [string]$WorkspaceId = "",
    [string]$LakehouseId = "",
    [string[]]$DocumentTypes = @('invoices', 'utility-bills'),
    [switch]$Force,
    [int]$MaxDocumentsPerType = 50
)

Set-StrictMode -Version Latest

. "$PSScriptRoot/../SecurityModule.ps1"

function Write-Info([string]$message) {
    Write-Host "[docint-extract] $message" -ForegroundColor Cyan
}

function Write-Warn([string]$message) {
    Write-Warning "[docint-extract] $message"
}

function Write-ErrorRecord([string]$message) {
    Write-Host "[docint-extract][error] $message" -ForegroundColor Red
}

function Get-AzdEnvValues {
    try {
        $values = @{}
        $raw = azd env get-values 2>$null
        foreach ($line in $raw) {
            if ($line -match '^([^=]+)=(.*)$') {
                $values[$Matches[1]] = $Matches[2].Trim('"')
            }
        }
        return $values
    } catch {
        Write-Warn "Unable to read azd environment values: $($_.Exception.Message)"
        return @{}
    }
}

function Resolve-DocumentIntelligenceSettings {
    param([hashtable]$AzdValues)

    $settings = [ordered]@{
        Name = $env:DOCUMENT_INTELLIGENCE_NAME
        Endpoint = $env:DOCUMENT_INTELLIGENCE_ENDPOINT
        ApiVersion = $env:DOCUMENT_INTELLIGENCE_API_VERSION
    }

    if (-not $settings.Name -and $AzdValues.ContainsKey('documentIntelligenceName')) {
        $settings.Name = $AzdValues['documentIntelligenceName']
    }
    if (-not $settings.Endpoint -and $AzdValues.ContainsKey('documentIntelligenceEndpoint')) {
        $settings.Endpoint = $AzdValues['documentIntelligenceEndpoint']
    }
    if (-not $settings.ApiVersion) {
        if ($AzdValues.ContainsKey('DOCUMENT_INTELLIGENCE_API_VERSION')) {
            $settings.ApiVersion = $AzdValues['DOCUMENT_INTELLIGENCE_API_VERSION']
        } else {
            $settings.ApiVersion = '2023-07-31'
        }
    }

    if (Test-Path '/tmp/document_intelligence.env') {
        Get-Content '/tmp/document_intelligence.env' | ForEach-Object {
            if ($_ -match '^DOCUMENT_INTELLIGENCE_NAME=(.+)$' -and -not $settings.Name) { $settings.Name = $Matches[1].Trim() }
            if ($_ -match '^DOCUMENT_INTELLIGENCE_ENDPOINT=(.+)$' -and -not $settings.Endpoint) { $settings.Endpoint = $Matches[1].Trim() }
            if ($_ -match '^DOCUMENT_INTELLIGENCE_API_VERSION=(.+)$' -and -not $settings.ApiVersion) { $settings.ApiVersion = $Matches[1].Trim() }
        }
    }

    if ([string]::IsNullOrWhiteSpace($settings.Name) -or [string]::IsNullOrWhiteSpace($settings.Endpoint)) {
        Write-Info "Document Intelligence configuration missing. Skipping extraction."
        return $null
    }

    $settings.Endpoint = $settings.Endpoint.TrimEnd('/')
    return $settings
}

function Resolve-FabricContext {
    param(
        [string]$WorkspaceId,
        [string]$LakehouseId,
        [hashtable]$AzdValues
    )

    $documentLakehouseName = $env:DOCUMENT_LAKEHOUSE_NAME
    if (-not $documentLakehouseName -and $AzdValues.ContainsKey('documentLakehouseName')) {
        $documentLakehouseName = $AzdValues['documentLakehouseName']
    }
    if (-not $documentLakehouseName) { $documentLakehouseName = 'bronze' }

    if (-not $WorkspaceId -and $env:FABRIC_WORKSPACE_ID) { $WorkspaceId = $env:FABRIC_WORKSPACE_ID }
    if (-not $LakehouseId -and $env:FABRIC_LAKEHOUSE_ID) { $LakehouseId = $env:FABRIC_LAKEHOUSE_ID }

    if (Test-Path '/tmp/fabric_workspace.env') {
        Get-Content '/tmp/fabric_workspace.env' | ForEach-Object {
            if (-not $WorkspaceId -and $_ -match '^FABRIC_WORKSPACE_ID=(.+)$') { $WorkspaceId = $Matches[1].Trim() }
            if (-not $LakehouseId -and $_ -match "^FABRIC_LAKEHOUSE_${documentLakehouseName}_ID=(.+)$") { $LakehouseId = $Matches[1].Trim() }
        }
    }

    if (Test-Path '/tmp/fabric_lakehouses.env') {
        Get-Content '/tmp/fabric_lakehouses.env' | ForEach-Object {
            if (-not $LakehouseId -and $_ -match "^FABRIC_LAKEHOUSE_${documentLakehouseName}_ID=(.+)$") { $LakehouseId = $Matches[1].Trim() }
            if (-not $LakehouseId -and $_ -match '^FABRIC_LAKEHOUSE_ID=(.+)$') { $LakehouseId = $Matches[1].Trim() }
        }
    }

    if (-not $WorkspaceId -and $AzdValues.ContainsKey('FABRIC_WORKSPACE_ID')) {
        $WorkspaceId = $AzdValues['FABRIC_WORKSPACE_ID']
    }
    if (-not $LakehouseId -and $AzdValues.ContainsKey('FABRIC_LAKEHOUSE_ID')) {
        $LakehouseId = $AzdValues['FABRIC_LAKEHOUSE_ID']
    }

    if (-not $WorkspaceId) {
        throw "Unable to resolve Fabric workspace id. Ensure previous automation steps completed successfully."
    }
    if (-not $LakehouseId) {
        throw "Unable to resolve target lakehouse id (expected lakehouse '${documentLakehouseName}')."
    }

    return [pscustomobject]@{
        WorkspaceId = $WorkspaceId
        LakehouseId = $LakehouseId
        DocumentLakehouseName = $documentLakehouseName
    }
}

function Format-OneLakePath {
    param([string]$Path)

    $segments = $Path.Trim('/').Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
    $encodedSegments = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
    return [string]::Join('/', $encodedSegments)
}

function Clone-Header {
    param([hashtable]$Headers)
    $clone = @{}
    foreach ($key in $Headers.Keys) { $clone[$key] = $Headers[$key] }
    return $clone
}

function Ensure-OneLakeDirectory {
    param(
        [string]$BaseUri,
        [hashtable]$BaseHeaders,
        [string]$DirectoryPath
    )

    $encodedPath = Format-OneLakePath $DirectoryPath
    $uri = "$BaseUri/$encodedPath?resource=directory"
    $headers = Clone-Header $BaseHeaders
    try {
        Invoke-WebRequest -Uri $uri -Headers $headers -Method Put -ErrorAction Stop | Out-Null
    } catch {
        $response = $null
        try { $response = $_.Exception.Response } catch { $response = $null }
        if ($response -and $response.StatusCode -eq 409) {
            return
        }
        throw $_
    }
}

function Test-OneLakeFileExists {
    param(
        [string]$BaseUri,
        [hashtable]$BaseHeaders,
        [string]$FilePath
    )

    $encodedPath = Format-OneLakePath $FilePath
    $uri = "$BaseUri/$encodedPath"
    $headers = Clone-Header $BaseHeaders
    try {
        Invoke-WebRequest -Uri $uri -Headers $headers -Method Head -ErrorAction Stop | Out-Null
        return $true
    } catch {
        $response = $null
        try { $response = $_.Exception.Response } catch { $response = $null }
        if ($response -and $response.StatusCode -eq 404) { return $false }
        throw $_
    }
}

function Get-OneLakeFiles {
    param(
        [string]$BaseUri,
        [hashtable]$Headers,
        [string]$DirectoryPath
    )

    $encodedDirectory = [System.Uri]::EscapeDataString($DirectoryPath)
    $uri = "$BaseUri?resource=filesystem&directory=$encodedDirectory&recursive=true"
    try {
        $response = Invoke-SecureRestMethod -Uri $uri -Headers $Headers -Method Get -Description "OneLake list $DirectoryPath"
        if ($response.paths) {
            return $response.paths | Where-Object { -not $_.isDirectory }
        }
        return @()
    } catch {
        $response = $null
        try { $response = $_.Exception.Response } catch { $response = $null }
        if ($response -and $response.StatusCode -eq 404) {
            return @()
        }
        throw $_
    }
}

function Download-OneLakeFile {
    param(
        [string]$BaseUri,
        [hashtable]$BaseHeaders,
        [string]$FilePath
    )

    $encodedPath = Format-OneLakePath $FilePath
    $uri = "$BaseUri/$encodedPath"
    $headers = Clone-Header $BaseHeaders
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -OutFile $tempFile -ErrorAction Stop | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($tempFile)
        return $bytes
    } finally {
        Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
    }
}

function New-OneLakeFile {
    param(
        [string]$BaseUri,
        [hashtable]$BaseHeaders,
        [string]$FilePath
    )

    $encodedPath = Format-OneLakePath $FilePath
    $uri = "$BaseUri/$encodedPath?resource=file"
    $headers = Clone-Header $BaseHeaders
    try {
        Invoke-WebRequest -Uri $uri -Headers $headers -Method Put -ErrorAction Stop | Out-Null
    } catch {
        $response = $null
        try { $response = $_.Exception.Response } catch { $response = $null }
        if ($response -and $response.StatusCode -ne 409) { throw $_ }
    }
}

function Set-OneLakeFileContent {
    param(
        [string]$BaseUri,
        [hashtable]$BaseHeaders,
        [string]$FilePath,
        [byte[]]$Content
    )

    New-OneLakeFile -BaseUri $BaseUri -BaseHeaders $BaseHeaders -FilePath $FilePath

    $encodedPath = Format-OneLakePath $FilePath
    $appendUri = "$BaseUri/$encodedPath?action=append&position=0"
    $flushUri = "$BaseUri/$encodedPath?action=flush&position=$($Content.Length)"

    $appendHeaders = Clone-Header $BaseHeaders
    $appendHeaders['Content-Type'] = 'application/octet-stream'
    $appendHeaders['Content-Length'] = $Content.Length

    Invoke-WebRequest -Uri $appendUri -Headers $appendHeaders -Method Patch -Body $Content -ErrorAction Stop | Out-Null

    $flushHeaders = Clone-Header $BaseHeaders
    $flushHeaders['Content-Length'] = 0
    Invoke-WebRequest -Uri $flushUri -Headers $flushHeaders -Method Patch -ErrorAction Stop | Out-Null
}

function Set-OneLakeJson {
    param(
        [string]$BaseUri,
        [hashtable]$BaseHeaders,
        [string]$FilePath,
        [object]$Payload
    )

    $json = $Payload | ConvertTo-Json -Depth 20
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Set-OneLakeFileContent -BaseUri $BaseUri -BaseHeaders $BaseHeaders -FilePath $FilePath -Content $bytes
}

function Get-FieldValue {
    param(
        [object]$Fields,
        [string]$Name
    )

    if (-not $Fields -or -not $Fields.PSObject.Properties.Name.Contains($Name)) {
        return $null
    }
    $field = $Fields.$Name
    if (-not $field) { return $null }

    if ($field.PSObject.Properties['valueString']) { return $field.valueString }
    if ($field.PSObject.Properties['valueCurrency']) {
        if ($field.valueCurrency.PSObject.Properties['amount']) { return $field.valueCurrency.amount }
        if ($field.valueCurrency.PSObject.Properties['value']) { return $field.valueCurrency.value }
    }
    if ($field.PSObject.Properties['valueNumber']) { return $field.valueNumber }
    if ($field.PSObject.Properties['valueInteger']) { return $field.valueInteger }
    if ($field.PSObject.Properties['valueDate']) { return $field.valueDate }
    if ($field.PSObject.Properties['valueSelectionMarkState']) { return $field.valueSelectionMarkState }
    if ($field.PSObject.Properties['valuePhoneNumber']) { return $field.valuePhoneNumber }
    if ($field.PSObject.Properties['valueSignature']) { return $field.valueSignature }
    if ($field.PSObject.Properties['content']) { return $field.content }
    return $null
}

function Get-FieldCurrencyCode {
    param(
        [object]$Fields,
        [string]$Name
    )
    if (-not $Fields -or -not $Fields.PSObject.Properties.Name.Contains($Name)) {
        return $null
    }
    $field = $Fields.$Name
    if ($field -and $field.PSObject.Properties['valueCurrency']) {
        return $field.valueCurrency.code
    }
    return $null
}

function Convert-AddressField {
    param([object]$Field)

    if (-not $Field) { return $null }
    if ($Field.PSObject.Properties['valueAddress']) {
        $addr = $Field.valueAddress
        $parts = @()
        foreach ($key in 'houseNumber', 'road', 'city', 'state', 'postalCode', 'countryRegion') {
            if ($addr.PSObject.Properties[$key] -and $addr.$key) { $parts += $addr.$key }
        }
        return ($parts -join ', ')
    }
    if ($Field.PSObject.Properties['content']) { return $Field.content }
    return $null
}

function Convert-ToNormalizedResult {
    param(
        [string]$DocumentCategory,
        [string]$SourcePath,
        [string]$FileName,
        [object]$Analysis
    )

    $analyzeResult = $Analysis.analyzeResult
    $document = $analyzeResult.documents | Select-Object -First 1
    $fields = if ($document) { $document.fields } else { $null }

    $invoiceId = Get-FieldValue -Fields $fields -Name 'InvoiceId'
    if (-not $invoiceId) { $invoiceId = Get-FieldValue -Fields $fields -Name 'BillId' }
    if (-not $invoiceId) { $invoiceId = [Guid]::NewGuid().ToString() }

    $currency = Get-FieldCurrencyCode -Fields $fields -Name 'Total'
    if (-not $currency) { $currency = Get-FieldCurrencyCode -Fields $fields -Name 'AmountDue' }

    $header = [ordered]@{
        DocumentType = $DocumentCategory
        DocumentId = $invoiceId
        SourceFileName = $FileName
        SourceFilePath = $SourcePath
        InvoiceId = Get-FieldValue -Fields $fields -Name 'InvoiceId'
        PurchaseOrder = Get-FieldValue -Fields $fields -Name 'PurchaseOrder'
        InvoiceDate = Get-FieldValue -Fields $fields -Name 'InvoiceDate'
        DueDate = Get-FieldValue -Fields $fields -Name 'DueDate'
        Total = Get-FieldValue -Fields $fields -Name 'Total'
        Subtotal = Get-FieldValue -Fields $fields -Name 'SubTotal'
        Tax = Get-FieldValue -Fields $fields -Name 'TotalTax'
        AmountDue = Get-FieldValue -Fields $fields -Name 'AmountDue'
        Currency = $currency
        CustomerName = Get-FieldValue -Fields $fields -Name 'CustomerName'
        CustomerId = Get-FieldValue -Fields $fields -Name 'CustomerId'
        VendorName = Get-FieldValue -Fields $fields -Name 'VendorName'
        VendorAddress = Convert-AddressField -Field $fields.VendorAddress
        BillingAddress = Convert-AddressField -Field $fields.BillingAddress
        ServiceAddress = Convert-AddressField -Field $fields.ServiceAddress
        BillingAddressRecipient = Get-FieldValue -Fields $fields -Name 'BillingAddressRecipient'
        ServiceAddressRecipient = Get-FieldValue -Fields $fields -Name 'ServiceAddressRecipient'
        RemittanceAddress = Convert-AddressField -Field $fields.RemittanceAddress
        RemittanceAddressRecipient = Get-FieldValue -Fields $fields -Name 'RemittanceAddressRecipient'
        CurrencyCode = $currency
        Confidence = if ($document) { $document.confidence } else { $null }
        AnalyzedAt = (Get-Date).ToString('o')
        ModelId = $analyzeResult.modelId
        ApiVersion = $analyzeResult.apiVersion
    }

    $lineItems = @()
    if ($fields -and $fields.PSObject.Properties.Name.Contains('Items')) {
        $itemsField = $fields.Items
        if ($itemsField -and $itemsField.PSObject.Properties['valueArray']) {
            $index = 0
            foreach ($item in $itemsField.valueArray) {
                $index++
                if (-not $item.PSObject.Properties['valueObject']) { continue }
                $valueObject = $item.valueObject
                $line = [ordered]@{
                    DocumentType = $DocumentCategory
                    DocumentId = $invoiceId
                    SourceFileName = $FileName
                    LineNumber = $index
                    Description = Get-FieldValue -Fields $valueObject -Name 'Description'
                    ProductCode = Get-FieldValue -Fields $valueObject -Name 'ProductCode'
                    Quantity = Get-FieldValue -Fields $valueObject -Name 'Quantity'
                    Unit = Get-FieldValue -Fields $valueObject -Name 'Unit'
                    UnitPrice = Get-FieldValue -Fields $valueObject -Name 'UnitPrice'
                    Amount = Get-FieldValue -Fields $valueObject -Name 'Amount'
                    Date = Get-FieldValue -Fields $valueObject -Name 'Date'
                    Tax = Get-FieldValue -Fields $valueObject -Name 'Tax'
                    Currency = $currency
                    Confidence = $item.confidence
                }
                $lineItems += $line
            }
        }
    }

    return [ordered]@{
        header = $header
        lineItems = $lineItems
        raw = $Analysis
    }
}

function Invoke-DocumentIntelligence {
    param(
        [string]$Endpoint,
        [string]$ApiVersion,
        [string]$ModelId,
        [byte[]]$Content,
        [string]$ContentType,
        [string]$AccessToken
    )

    $analysisUrl = "$Endpoint/formrecognizer/documentModels/${ModelId}:analyze?api-version=$ApiVersion&stringIndexType=unicodeCodePoint"
    $headers = @{
        Authorization = "Bearer $AccessToken"
        'Content-Type' = $ContentType
    }

    $initialResponse = Invoke-WebRequest -Uri $analysisUrl -Method Post -Headers $headers -Body $Content -ErrorAction Stop
    $operationLocation = $initialResponse.Headers['operation-location']
    if (-not $operationLocation) {
        throw "Document Intelligence analysis did not return an operation-location header."
    }

    $pollHeaders = @{ Authorization = "Bearer $AccessToken" }
    $attempt = 0
    $maxAttempts = 40
    $waitSeconds = 3

    do {
        Start-Sleep -Seconds $waitSeconds
        $attempt++
        $result = Invoke-RestMethod -Uri $operationLocation -Method Get -Headers $pollHeaders -ErrorAction Stop
        $status = $result.status
    } while (($status -eq 'running' -or $status -eq 'notStarted') -and $attempt -lt $maxAttempts)

    if ($status -ne 'succeeded') {
        $errorMessage = if ($result.error) { $result.error.message } else { "status=$status" }
        throw "Document analysis failed: $errorMessage"
    }

    return $result
}

try {
    $azdValues = Get-AzdEnvValues
    $settings = Resolve-DocumentIntelligenceSettings -AzdValues $azdValues
    if (-not $settings) { return }

    $context = Resolve-FabricContext -WorkspaceId $WorkspaceId -LakehouseId $LakehouseId -AzdValues $azdValues

    $storageToken = Get-SecureApiToken -Resource $SecureApiResources.Storage -Description "OneLake"
    $docToken = Get-SecureApiToken -Resource $SecureApiResources.DocumentIntelligence -Description "Document Intelligence"

    $storageHeaders = New-SecureHeaders -Token $storageToken
    $storageHeaders.Remove('Content-Type')
    $storageHeaders['x-ms-version'] = '2023-01-03'

    $baseUri = "https://onelake.dfs.fabric.microsoft.com/$($context.WorkspaceId)/$($context.LakehouseId)"

    $docTypeConfigs = @{
        'invoices' = @{ ModelId = 'prebuilt-invoice'; SourcePath = 'Files/documents/invoices'; OutputPath = 'Files/raw/document-intelligence/invoices'; ProcessedPath = 'Files/raw/document-intelligence/_processed/invoices' }
        'utility-bills' = @{ ModelId = 'prebuilt-invoice'; SourcePath = 'Files/documents/utility-bills'; OutputPath = 'Files/raw/document-intelligence/utility-bills'; ProcessedPath = 'Files/raw/document-intelligence/_processed/utility-bills' }
    }

    $processedSummary = @()

    foreach ($docType in $DocumentTypes) {
        if (-not $docTypeConfigs.ContainsKey($docType)) {
            Write-Warn "Unsupported document type '$docType' requested; skipping."
            continue
        }

        $config = $docTypeConfigs[$docType]
        Write-Info "Processing document type '$docType' using model '$($config.ModelId)'"

        Ensure-OneLakeDirectory -BaseUri $baseUri -BaseHeaders $storageHeaders -DirectoryPath $config.OutputPath
        Ensure-OneLakeDirectory -BaseUri $baseUri -BaseHeaders $storageHeaders -DirectoryPath $config.ProcessedPath.Trim('/')

        $files = Get-OneLakeFiles -BaseUri $baseUri -Headers $storageHeaders -DirectoryPath $config.SourcePath
        if (-not $files -or $files.Count -eq 0) {
            Write-Info "No source files found under $($config.SourcePath)."
            continue
        }

        $documentsHandled = 0
        foreach ($file in $files) {
            if ($documentsHandled -ge $MaxDocumentsPerType) { break }

            $sourcePath = $file.name
            $fileName = [System.IO.Path]::GetFileName($sourcePath)
            $outputFile = "$($config.OutputPath.Trim('/'))/$fileName.json"
            $processedFile = "$($config.ProcessedPath.Trim('/'))/$fileName.json"

            $exists = Test-OneLakeFileExists -BaseUri $baseUri -BaseHeaders $storageHeaders -FilePath $outputFile
            if ($exists -and -not $Force) {
                Write-Info "Skipping already processed file $fileName"
                continue
            }

            Write-Info "Analyzing $sourcePath"

            $bytes = $null
            try {
                $bytes = Download-OneLakeFile -BaseUri $baseUri -BaseHeaders $storageHeaders -FilePath $sourcePath
            } catch {
                Write-ErrorRecord "Failed to download ${sourcePath}: $($_.Exception.Message)"
                continue
            }

            if (-not $bytes -or $bytes.Length -eq 0) {
                Write-Warn "File $sourcePath is empty; skipping."
                continue
            }

            $extension = [System.IO.Path]::GetExtension($fileName).ToLowerInvariant()
            $contentType = switch ($extension) {
                '.pdf' { 'application/pdf' }
                '.png' { 'image/png' }
                '.jpg' { 'image/jpeg' }
                '.jpeg' { 'image/jpeg' }
                default { 'application/octet-stream' }
            }

            $analysis = $null
            try {
                $analysis = Invoke-DocumentIntelligence -Endpoint $settings.Endpoint -ApiVersion $settings.ApiVersion -ModelId $config.ModelId -Content $bytes -ContentType $contentType -AccessToken $docToken
            } catch {
                Write-ErrorRecord "Document Intelligence failed for ${fileName}: $($_.Exception.Message)"
                continue
            }

            try {
                $normalized = Convert-ToNormalizedResult -DocumentCategory $docType -SourcePath $sourcePath -FileName $fileName -Analysis $analysis
                Set-OneLakeJson -BaseUri $baseUri -BaseHeaders $storageHeaders -FilePath $outputFile -Payload $normalized

                $manifest = [ordered]@{
                    documentType = $docType
                    sourcePath = $sourcePath
                    outputPath = $outputFile
                    processedAt = (Get-Date).ToString('o')
                    modelId = $normalized.header.ModelId
                    apiVersion = $normalized.header.ApiVersion
                    header = $normalized.header
                    lineItemCount = $normalized.lineItems.Count
                }
                Set-OneLakeJson -BaseUri $baseUri -BaseHeaders $storageHeaders -FilePath $processedFile -Payload $manifest

                $processedSummary += [pscustomobject]@{
                    DocumentType = $docType
                    FileName = $fileName
                    LineItems = $normalized.lineItems.Count
                }

                $documentsHandled++
            } catch {
                Write-ErrorRecord "Failed to persist results for ${fileName}: $($_.Exception.Message)"
                continue
            }
        }

        Write-Info "Completed '$docType': processed $documentsHandled document(s)."
    }

    if ($processedSummary.Count -gt 0) {
        Write-Info "Summary of processed documents:"
        $processedSummary | ForEach-Object {
            Write-Info "  - $($_.DocumentType): $($_.FileName) (line items: $($_.LineItems))"
        }
    } else {
        Write-Info "No documents were processed during this run."
    }
}
catch {
    Write-ErrorRecord $_.Exception.Message
    throw
}
finally {
    Clear-SensitiveVariables -VariableNames @('storageToken', 'docToken')
}
