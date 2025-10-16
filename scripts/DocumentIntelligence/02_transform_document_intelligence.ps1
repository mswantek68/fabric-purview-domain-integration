[CmdletBinding()]
param(
    [string]$WorkspaceId = "",
    [string]$LakehouseId = "",
    [string]$SparkDriverMemory = "4g",
    [int]$SparkDriverCores = 4,
    [string]$SparkExecutorMemory = "4g",
    [int]$SparkExecutorCores = 4,
    [int]$SparkExecutorCount = 2
)

Set-StrictMode -Version Latest

. "$PSScriptRoot/../SecurityModule.ps1"

function Write-Info([string]$message) {
    Write-Host "[docint-transform] $message" -ForegroundColor Cyan
}

function Write-Warn([string]$message) {
    Write-Warning "[docint-transform] $message"
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
        throw "Unable to resolve Fabric workspace id."
    }
    if (-not $LakehouseId) {
        throw "Unable to resolve lakehouse id for document transforms."
    }

    return [pscustomobject]@{
        WorkspaceId = $WorkspaceId
        LakehouseId = $LakehouseId
    }
}

function Start-SparkSession {
    param(
        [string]$WorkspaceId,
        [string]$LakehouseId,
        [hashtable]$Headers,
        [string]$DriverMemory,
        [int]$DriverCores,
        [string]$ExecutorMemory,
        [int]$ExecutorCores,
        [int]$ExecutorCount
    )

    $body = @{
        name = "document-intelligence-transform"
        sessionType = "PySpark"
        lakehouse = @{
            workspaceId = $WorkspaceId
            itemId = $LakehouseId
        }
        properties = @{
            driverMemory = $DriverMemory
            driverCores = $DriverCores
            executorMemory = $ExecutorMemory
            executorCores = $ExecutorCores
            numExecutors = $ExecutorCount
        }
    } | ConvertTo-Json -Depth 6

    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/sparkSessions"
    $response = Invoke-SecureRestMethod -Uri $uri -Headers $Headers -Method Post -Body $body -Description "Create Spark session"
    return $response
}

function Wait-SparkSessionIdle {
    param(
        [string]$WorkspaceId,
        [string]$SessionId,
        [hashtable]$Headers,
        [int]$TimeoutSeconds = 300
    )

    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/sparkSessions/$SessionId"
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $status = Invoke-SecureRestMethod -Uri $uri -Headers $Headers -Method Get -Description "Poll Spark session"
        $state = $status.state
        if ($state -eq 'idle') { return $true }
        if ($state -in @('dead', 'killed', 'error')) {
            throw "Spark session terminated unexpectedly (state=$state)."
        }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }

    throw "Spark session did not become idle within $TimeoutSeconds seconds."
}

function Submit-SparkStatement {
    param(
        [string]$WorkspaceId,
        [string]$SessionId,
        [hashtable]$Headers,
        [string]$Code
    )

    $body = @{
        kind = 'pyspark'
        code = $Code
    } | ConvertTo-Json -Depth 4

    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/sparkSessions/$SessionId/statements"
    $response = Invoke-SecureRestMethod -Uri $uri -Headers $Headers -Method Post -Body $body -Description "Submit Spark statement"
    return $response
}

function Wait-SparkStatementComplete {
    param(
        [string]$WorkspaceId,
        [string]$SessionId,
        [string]$StatementId,
        [hashtable]$Headers,
        [int]$TimeoutSeconds = 1200
    )

    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/sparkSessions/$SessionId/statements/$StatementId"
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $status = Invoke-SecureRestMethod -Uri $uri -Headers $Headers -Method Get -Description "Poll Spark statement"
        $state = $status.state
        if ($state -eq 'available') {
            if ($status.output -and $status.output.status -eq 'error') {
                $errorMsg = $status.output.evalue
                throw "Spark statement failed: $errorMsg"
            }
            return $true
        }
        if ($state -in @('error', 'cancelling', 'cancelled')) {
            throw "Spark statement ended with state=$state."
        }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    throw "Spark statement did not complete within $TimeoutSeconds seconds."
}

function Stop-SparkSession {
    param(
        [string]$WorkspaceId,
        [string]$SessionId,
        [hashtable]$Headers
    )

    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/sparkSessions/$SessionId"
    try {
        Invoke-SecureRestMethod -Uri $uri -Headers $Headers -Method Delete -Description "Stop Spark session" | Out-Null
    } catch {
    Write-Warn "Failed to stop Spark session ${SessionId}: $($_.Exception.Message)"
    }
}

$sparkCode = @'
from pyspark.sql import functions as F
from pyspark.sql.utils import AnalysisException

def load_json(path):
    try:
        df = spark.read.json(path)
        if df.rdd.isEmpty():
            return None
        return df
    except AnalysisException:
        return None

def coalesce_decimal(col):
    return F.col(col).cast("double")

def write_tables(df, header_table, line_table):
    if df is None:
        return
    if df.rdd.isEmpty():
        return

    header_df = df.select(
        F.col("header.DocumentType").alias("document_type"),
        F.col("header.DocumentId").alias("document_id"),
        F.col("header.SourceFileName").alias("source_file_name"),
        F.col("header.SourceFilePath").alias("source_file_path"),
        F.col("header.InvoiceId").alias("invoice_id"),
        F.col("header.PurchaseOrder").alias("purchase_order"),
        F.col("header.InvoiceDate").alias("invoice_date"),
        F.col("header.DueDate").alias("due_date"),
        coalesce_decimal("header.Total").alias("total_amount"),
        coalesce_decimal("header.Subtotal").alias("subtotal_amount"),
        coalesce_decimal("header.Tax").alias("tax_amount"),
        coalesce_decimal("header.AmountDue").alias("amount_due"),
        F.col("header.Currency").alias("currency"),
        F.col("header.CurrencyCode").alias("currency_code"),
        F.col("header.CustomerName").alias("customer_name"),
        F.col("header.CustomerId").alias("customer_id"),
        F.col("header.VendorName").alias("vendor_name"),
        F.col("header.VendorAddress").alias("vendor_address"),
        F.col("header.BillingAddress").alias("billing_address"),
        F.col("header.ServiceAddress").alias("service_address"),
        F.col("header.BillingAddressRecipient").alias("billing_recipient"),
        F.col("header.ServiceAddressRecipient").alias("service_recipient"),
        F.col("header.RemittanceAddress").alias("remittance_address"),
        F.col("header.RemittanceAddressRecipient").alias("remittance_recipient"),
        F.col("header.Confidence").alias("confidence"),
        F.col("header.AnalyzedAt").alias("analyzed_at"),
        F.col("header.ModelId").alias("model_id"),
        F.col("header.ApiVersion").alias("api_version")
    )

    header_df = header_df.dropDuplicates(["document_id", "source_file_path"])
    header_df.write.mode("overwrite").format("delta").saveAsTable(header_table)

    line_df = df.select(
        F.col("header.DocumentType").alias("document_type"),
        F.col("header.DocumentId").alias("document_id"),
        F.explode_outer("lineItems").alias("line")
    )

    line_df = line_df.select(
        F.col("document_type"),
        F.col("document_id"),
        F.coalesce(F.col("line.LineNumber").cast("int"), F.lit(0)).alias("line_number"),
        F.col("line.Description").alias("description"),
        F.col("line.ProductCode").alias("product_code"),
        coalesce_decimal("line.Quantity").alias("quantity"),
        F.col("line.Unit").alias("unit"),
        coalesce_decimal("line.UnitPrice").alias("unit_price"),
        coalesce_decimal("line.Amount").alias("line_amount"),
        coalesce_decimal("line.Tax").alias("line_tax"),
        F.col("line.Date").alias("line_date"),
        F.col("line.Currency").alias("line_currency"),
        F.col("line.Confidence").alias("confidence")
    )

    line_df = line_df.dropDuplicates(["document_id", "line_number", "description"])
    line_df.write.mode("overwrite").format("delta").saveAsTable(line_table)

invoice_df = load_json("Files/raw/document-intelligence/invoices/*.json")
write_tables(invoice_df, "silver_invoice_header", "silver_invoice_line")

utility_df = load_json("Files/raw/document-intelligence/utility-bills/*.json")
write_tables(utility_df, "silver_utility_bill_header", "silver_utility_bill_line")
'@

$session = $null
$sessionId = $null
$context = $null
try {
    $azdValues = Get-AzdEnvValues
    $context = Resolve-FabricContext -WorkspaceId $WorkspaceId -LakehouseId $LakehouseId -AzdValues $azdValues

    $fabricToken = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric"
    $headers = New-SecureHeaders -Token $fabricToken -AdditionalHeaders @{ 'Content-Type' = 'application/json' }

    try {
        $session = Start-SparkSession -WorkspaceId $context.WorkspaceId -LakehouseId $context.LakehouseId -Headers $headers -DriverMemory $SparkDriverMemory -DriverCores $SparkDriverCores -ExecutorMemory $SparkExecutorMemory -ExecutorCores $SparkExecutorCores -ExecutorCount $SparkExecutorCount
    } catch {
        $errMessage = $_.Exception.Message
        if ($errMessage -match '404' -or $errMessage -match 'EntityNotFound') {
            Write-Warn "Spark session endpoint returned 404. Fabric workspace may not have Spark preview enabled; skipping Document Intelligence transform."
            return
        }
        throw
    }

    $sessionId = $session.id
    Write-Info "Spark session created: $sessionId"

    Wait-SparkSessionIdle -WorkspaceId $context.WorkspaceId -SessionId $sessionId -Headers $headers | Out-Null
    Write-Info "Spark session is idle. Submitting transform code."

    $statement = Submit-SparkStatement -WorkspaceId $context.WorkspaceId -SessionId $sessionId -Headers $headers -Code $sparkCode
    $statementId = $statement.id

    Wait-SparkStatementComplete -WorkspaceId $context.WorkspaceId -SessionId $sessionId -StatementId $statementId -Headers $headers | Out-Null
    Write-Info "Document intelligence transform completed successfully."
}
catch {
    $errMessage = $_.Exception.Message
    if ($errMessage -match '404' -or $errMessage -match 'EntityNotFound') {
        Write-Warn "Document intelligence transform skipped: $errMessage"
    } else {
        Write-Warn "Document intelligence transform failed: $errMessage"
        throw
    }
}
finally {
    if ($sessionId -and $context) {
        try {
            $token = Get-SecureApiToken -Resource $SecureApiResources.Fabric -Description "Fabric"
            $cleanupHeaders = New-SecureHeaders -Token $token -AdditionalHeaders @{ 'Content-Type' = 'application/json' }
            Stop-SparkSession -WorkspaceId $context.WorkspaceId -SessionId $sessionId -Headers $cleanupHeaders
        } catch {
            Write-Warn "Unable to cleanup Spark session ${sessionId}: $($_.Exception.Message)"
        }
    }
    Clear-SensitiveVariables -VariableNames @('fabricToken', 'token')
}
