# Document Intelligence Automation Scripts

This folder contains automation steps that extract structured invoice and utility bill data from OneLake documents using Azure AI Document Intelligence, and land normalized tables inside the Fabric lakehouse.

## Script Order

1. `00_resolve_document_intelligence.ps1`
   - Resolves the deployed Document Intelligence account endpoint and writes shared values to `/tmp/document_intelligence.env`.
   - Safe to re-run; exits gracefully if Document Intelligence is not configured.

2. `01_extract_document_intelligence.ps1`
   - Scans `Files/documents/invoices/` and `Files/documents/utility-bills/` within the document lakehouse.
   - Sends new PDFs to the `prebuilt-invoice` model and writes normalized JSON outputs under `Files/raw/document-intelligence/<type>/`.
   - Idempotent: skips files that already have normalized results unless `-Force` is provided.

3. `02_transform_document_intelligence.ps1`
   - Submits a Fabric Spark session that converts normalized JSON into managed Delta tables:
     - `silver_invoice_header`
     - `silver_invoice_line`
     - `silver_utility_bill_header`
     - `silver_utility_bill_line`
   - Leaves the Spark session cleanly stopped even when failures occur.

All scripts rely on shared helpers in `../SecurityModule.ps1` and expect Azure CLI, Fabric, and Storage tokens to be available via `az login`.

## Environment Variables

The scripts automatically resolve required IDs by checking, in order:

1. Explicit parameter values
2. Session environment variables (e.g. `FABRIC_WORKSPACE_ID`, `FABRIC_LAKEHOUSE_ID`)
3. `/tmp/fabric_workspace.env` and `/tmp/fabric_lakehouses.env`
4. `azd env get-values` outputs

Resolved values are exported to `/tmp/document_intelligence.env` for reuse across steps.

## Output Locations

- Raw normalized JSON: `Files/raw/document-intelligence/<type>/<file>.json`
- Processing manifests: `Files/raw/document-intelligence/_processed/<type>/<file>.json`
- Managed Delta tables: `Tables/silver_invoice_header`, `Tables/silver_invoice_line`, `Tables/silver_utility_bill_header`, `Tables/silver_utility_bill_line`

## Manual Execution

```pwsh
pwsh ./scripts/DocumentIntelligence/00_resolve_document_intelligence.ps1
pwsh ./scripts/DocumentIntelligence/01_extract_document_intelligence.ps1
pwsh ./scripts/DocumentIntelligence/02_transform_document_intelligence.ps1
```

Each script is safe to execute multiple times and includes verbose logging plus detailed error handling for quick diagnostics.
