# Microsoft Fabric + Purview Data Governance Accelerator with OneLake Indexing

## 🚀 Overview

This solution automates a Microsoft Fabric environment integrated with Microsoft Purview for data governance **and AI Search with OneLake indexing capabilities**. It creates a domain aligned data platform including Fabric capacity, workspaces, domains, Purview collections with automated governance integration, **workspace-scoped scanning**, and **intelligent document search through OneLake indexing**.

This solution features **dual script support** - both **PowerShell** and **Bash** implementations for maximum compatibility across different environments and preferences. The PowerShell implementation provides enhanced error handling and cross-platform support via PowerShell Core.

This idea will be integrated into a larger deployment. Main point to keep in mind, I am using very atomic scripts to allow for endless configurations as I learn more about how to integrate source systems into Fabric (ie: Databricks, Oracle, SAP, etc.) and Purview domains. This should allow for a custom yaml file that can be adapted for each domain created.

### What Gets Deployed (16 Automated Steps)

- **Microsoft Fabric Capacity**: High-performance compute capacity for Fabric workloads and separation
- **Fabric Workspace**: Collaborative workspace for data engineering and analytics
- **Fabric Domain**: Organized data domain structure (governance-focused)
- **Purview Collections**: Data catalog collections for governance and discovery
- **Fabric Datasources**: **Registered Fabric data source in Purview** for governance integration
- **Lakehouses**: Bronze, Silver, and Gold data lakehouse architecture
- **Workspace-Scoped Scans**: **Purview scans of the Fabric data source** configured to target only the created workspace, ensuring precise data discovery and governance
- **🆕 AI Search Service**: Azure AI Search with OneLake indexing capabilities for document discovery
- **🆕 OneLake Indexer**: Automated indexer connecting AI Search to Fabric lakehouse data using preview API
- **🆕 Document Processing**: Intelligent document extraction and search from bronze lakehouse
- **🆕 RBAC Automation**: Seamless managed identity permissions between AI Search and Fabric workspace

## 🏗️ Enhanced Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Microsoft Fabric                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────────────────┐ │
│  │  Fabric Domain  │    │ Fabric Capacity │    │     Fabric Workspace     │ │
│  │                 │    │                 │    │                          │ │
│  │ ┌─────────────┐ │    │   ┌─────────┐   │    │ ┌──────────────────────┐ │ │
│  │ │ Governance  │ │    │   │  F64     │   │    │ │    Lakehouse Data    │ │ │
│  │ │ Structure   │ │    │   │ Compute  │   │    │ │                      │ │ │
│  │ └─────────────┘ │    │   └─────────┘   │    │ │ ┌──────────────────┐ │ │ │
│  └─────────────────┘    └─────────────────┘    │ │ │ Bronze (Documents)│ │ │ │
│                                                │ │ │ Silver (Curated) │ │ │ │
│                                                │ │ │ Gold (Analytics) │ │ │ │
│                                                │ │ └──────────────────┘ │ │ │
│                                                │ └──────────────────────┘ │ │
│                                                └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                        │                                │
            Data Governance                    OneLake Indexing
                        ▼                                ▼
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│       Microsoft Purview         │      │        Azure AI Search          │
├─────────────────────────────────┤      ├─────────────────────────────────┤
│  ┌─────────────────────────────┐│      │  ┌─────────────────────────────┐│
│  │    Data Map Collections     ││      │  │      OneLake Indexer        ││
│  │                             ││      │  │                             ││
│  │ ┌─────────────────────────┐ ││      │  │ ┌─────────────────────────┐ ││
│  │ │   Fabric Collection     │ ││      │  │ │    Document Search      │ ││
│  │ │                         │ ││      │  │ │                         │ ││
│  │ │ ┌─────────────────────┐ │ ││      │  │ │ ┌─────────────────────┐ │ ││
│  │ │ │ Workspace Scans     │ │ ││      │  │ │ │ Bronze Data Index   │ │ ││
│  │ │ │ Asset Discovery     │ │ ││      │  │ │ │ Real-time Processing│ │ ││
│  │ │ │ Lineage Tracking    │ │ ││      │  │ │ │ Managed Identity    │ │ ││
│  │ │ └─────────────────────┘ │ ││      │  │ │ └─────────────────────┘ │ ││
│  │ └─────────────────────────┘ ││      │  │ └─────────────────────────┘ ││
│  └─────────────────────────────┘│      │  └─────────────────────────────┘│
└─────────────────────────────────┘      └─────────────────────────────────┘
```

## 🎯 Quick Start

### Prerequisites
- [Azure Developer CLI](https://docs.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [PowerShell Core](https://docs.microsoft.com/powershell/scripting/install/installing-powershell) (recommended)
- **Azure Subscriptions**: Fabric + Purview + AI Search in same subscription (recommended)
- **Admin Permissions**: Fabric Administrator + Purview Data Source Administrator

### Authentication

```bash
# Authenticate Azure CLI
az login

# Authenticate Azure Developer CLI  
azd auth login

# Verify authentication status
az account show
azd auth login --check-status
```

> **Note**: Standard `az login` is sufficient for most deployments. The scripts will automatically request specific API tokens (Power BI, Fabric) as needed during execution. If you encounter token issues, see the troubleshooting section for alternative authentication approaches.

### Deployment

```bash
# 🚨 ALWAYS preview first!
azd provision --preview

# Deploy the complete solution (16 automated steps)
azd up
```

This will automatically execute:
1. ✅ **Fabric Capacity Validation**: Ensure active Fabric capacity
2. ✅ **Domain Creation**: Create Fabric governance domain
3. ✅ **Workspace Creation**: Create Fabric workspace
4. ✅ **Domain Assignment**: Assign workspace to domain
5. ✅ **Purview Collection**: Create Purview collection hierarchy
6. ✅ **Data Source Registration**: Register Fabric as Purview data source
7. ✅ **Scan Configuration**: Setup workspace-scoped scan guidance
8. ✅ **Lakehouse Creation**: Create bronze, silver, gold lakehouses
9. ✅ **🆕 Document Intelligence Resolution**: Locate Document Intelligence endpoint and credentials
10. ✅ **🆕 Invoice & Bill Extraction**: Parse invoices and utility bills with Azure AI Document Intelligence
11. ✅ **🆕 Lakehouse Table Materialization**: Publish normalized invoice and utility bill tables in the document lakehouse
12. ✅ **🆕 AI Search RBAC**: Configure managed identity permissions
13. ✅ **🆕 OneLake Indexer**: Create AI Search indexer for document processing
14. ✅ **🆕 Document Indexing**: Index documents from bronze lakehouse
15. ✅ **Purview Scanning**: Execute workspace-scoped Purview scan
16. ✅ **Monitoring Setup**: Connect Log Analytics workspace

## 📋 Prerequisites

### Required Tools

1. **Azure Developer CLI (azd)**
   ```bash
   # Install azd
   curl -fsSL https://aka.ms/install-azd.sh | bash
   ```

2. **Azure CLI**
   ```bash
   # Install Azure CLI
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   ```

3. **PowerShell Core** (for PowerShell script execution)
   ```bash
   # Install PowerShell Core on Linux/macOS
   curl -sSL https://raw.githubusercontent.com/PowerShell/PowerShell/master/tools/install-powershell.sh | bash
   ```

### Authentication Setup

```bash
# Login to Azure CLI
az login

# Login to Azure Developer CLI
azd auth login

# Verify authentication status
az account show
azd auth login --check-status
```

### Permission Requirements

#### Fabric Permissions
- **Fabric Administrator**: Required for capacity, domain, and workspace operations
- **Capacity Assignment**: User must have access to assign workspaces to capacity

#### Purview Permissions  
- **Purview Data Source Administrator**: Required for data source registration and scan configuration
- **Collection Administrator**: Required for collection creation and management

#### AI Search Permissions
- **Search Service Contributor**: Required for indexer and index management
- **Storage Account permissions**: For accessing OneLake data

### Fabric Capacity SKUs

Choose the appropriate SKU based on your workload requirements:

| SKU | Memory | v-cores | Use Case |
|-----|--------|---------|----------|
| F64 | 131 GB | 8 | Development/Testing |
| F128| 262 GB | 16 | Small Production |
| F256| 524 GB | 32 | Medium Production |
| F512| 1048 GB| 64 | Large Production |

### Customization Options

The solution supports extensive customization through parameters:

- **Fabric Settings**: Capacity size, workspace names, domain structure
- **Purview Integration**: Collection names, governance domains, parent relationships
- **Admin Access**: Fabric administrators, Purview data stewards
- **Scan Scoping**: Workspace-specific scanning configuration
- **🆕 AI Search Configuration**: Service tier, indexer settings, document processing options

### Workspace-Scoped Scanning

The solution implements **precise workspace scoping** for Purview scans:

#### How It Works
1. **Fabric Data Source Registration**: The entire Fabric tenant is **first registered** as a data source in Purview (prerequisite)
2. **Dynamic Workspace Detection**: Scripts automatically detect the created workspace ID
3. **Scoped Scan Configuration**: Purview scan is configured to target only the specific workspace within the **registered data source**
4. **Asset-Aware Timing**: Scan executes after lakehouses are created to ensure complete asset discovery
5. **Scan Execution**: The scan **locates the registered data source** and catalogs only the scoped workspace assets
6. **Data Cataloging**: Discovered assets are cataloged in Purview with proper lineage and metadata

**Critical Dependency**: The data source **must be registered first** before any scan can locate and catalog assets. Without registration, Purview scans cannot find the Fabric workspace.

#### Benefits
- 🎯 **Precise Governance**: Only scan the workspace you created within the registered Fabric data source
- 🚀 **Faster Scanning**: Reduced scan time by focusing on relevant assets
- 🔒 **Security**: Avoids accidental discovery of sensitive workspaces
- 📊 **Clean Results**: Clear, focused data catalog without noise
- 🔍 **Complete Discovery**: All workspace assets (lakehouses, datasets, reports) are cataloged in Purview

#### Scan Configuration
```json
{
  "properties": {
    "includePersonalWorkspaces": false,
    "scanScope": {
      "type": "PowerBIScanScope",
      "workspaces": [
        {"id": "your-workspace-id"}
      ]
    }
  },
  "kind": "PowerBIMsi"
}
```

## 📚 Solution Components

### Infrastructure (Bicep)

- `infra/main.bicep`: Main infrastructure definition including AI Search service
- `infra/main.bicepparam`: Configuration parameters
- `infra/core/`: Reusable infrastructure modules

### Automation Scripts

The solution provides **dual script implementations** for maximum compatibility:

#### PowerShell Scripts (Recommended)
- **Cross-platform**: Works on Windows, Linux, and macOS via PowerShell Core
- **Enhanced error handling**: Detailed error reporting and recovery
- **Consistent API interaction**: Robust Azure API integration
- **Current default**: Used by `azure.yaml` configuration

#### Bash Scripts (Alternative)
- **Linux/macOS native**: Traditional shell scripting
- **Lightweight**: Minimal dependencies
- **POSIX compatible**: Works across Unix-like systems

| Script | Purpose | Dependencies |
|--------|---------|--------------|
| `ensure_active_capacity.*` | Validate Fabric capacity | Fabric Admin |
| `create_fabric_domain.*` | Create Fabric governance domain | Fabric Admin |
| `create_fabric_workspace.*` | Create Fabric workspace | Fabric Capacity |
| `assign_workspace_to_domain.*` | Assign workspace to domain | Workspace + Domain |
| `create_purview_collection.*` | Create Purview collection | Purview Admin |
| `register_fabric_datasource.*` | **Register Fabric as data source in Purview** (prerequisite for scanning) | Collection |
| `setup_fabric_scan_guidance.*` | Configure scan guidance | Datasource |
| `create_lakehouses.*` | Create bronze/silver/gold lakehouses | Workspace |
| `🆕 setup_ai_services_rbac.*` | **Configure AI Search managed identity RBAC for Fabric access** | AI Search + Workspace |
| `🆕 create_onelake_indexer.*` | **Create OneLake indexer for document processing** | AI Search + Lakehouses + RBAC |
| `🆕 setup_document_indexers.*` | **Setup document indexing and processing pipeline** | OneLake Indexer |
| `trigger_purview_scan_for_fabric_workspace.*` | **Locate registered data source and execute workspace-scoped scan** | Lakehouses + **Registered Datasource** |
| `connect_log_analytics.*` | Connect monitoring | Log Analytics |

**Key Feature**: The solution follows a **strict dependency order**: **first registers the entire Fabric tenant as a data source in Purview**, then creates a **scoped scan** that can successfully locate and scan only the specific workspace created by the deployment. **Additionally**, AI Search is configured with proper RBAC permissions to index documents from OneLake automatically.

### Atomic Script Architecture

Each script is designed to be:
- **Single-purpose**: One responsibility per script
- **Idempotent**: Safe to run multiple times
- **Error-resilient**: Comprehensive error handling
- **Observable**: Detailed logging and status reporting
- **Cross-platform**: Available in both PowerShell (.ps1) and Bash (.sh) versions

### Execution Order & Workspace Scoping

The solution follows a **strict execution order** to ensure proper dependency management:

1. **Infrastructure Setup**: Capacity → Domain → Workspace → Collection
2. **Data Source Registration**: **Register Fabric as data source in Purview** (enables scanning)
3. **Asset Creation**: Lakehouses (bronze, silver, gold)
4. **🆕 AI Search Integration**: RBAC configuration → OneLake indexer → Document processing
5. **Data Governance**: **Workspace-scoped Purview scan execution** (locates registered data source and scans workspace)

**Critical Dependencies**: 
- The Fabric data source **must be registered in Purview first** before any scan can locate it
- The Purview scan is executed **after** lakehouse creation to ensure all workspace assets are discoverable
- **🆕 AI Search RBAC** must be configured before OneLake indexer creation
- **🆕 OneLake indexer** requires active lakehouse with document content
- Scans can only find and catalog assets from **registered data sources**

## 🆕 OneLake Indexing & AI Search Features

### Intelligent Document Processing

The solution now includes **AI Search with OneLake indexing** for intelligent document discovery and search:

#### Key Features
- 🔍 **Document Indexing**: Automatically indexes documents stored in Fabric lakehouse
- 🧠 **AI-Powered Search**: Leverages Azure AI Search for intelligent document retrieval
- 🔗 **OneLake Integration**: Direct connection to Fabric lakehouse data using preview API 2024-05-01-preview
- 🔐 **Seamless RBAC**: Automated managed identity configuration for secure access
- ⚡ **Real-time Processing**: Documents are indexed as they're added to the bronze lakehouse
- 🤖 **AI Foundry Integration**: REST API automation for knowledge source connection (Chat Playground requires manual UI setup)
- 🧾 **Structured Extraction**: Azure AI Document Intelligence converts invoices and utility bills into managed Delta tables (`silver_invoice_*`, `silver_utility_bill_*`)

#### How It Works
1. **Documents**: Store documents in the bronze lakehouse within the Fabric workspace
2. **RBAC Setup**: AI Search managed identity is automatically granted Fabric workspace access
3. **OneLake Indexer**: Creates indexer connecting AI Search to lakehouse using OneLake API
4. **Document Intelligence** *(new)*: Azure AI Document Intelligence extracts invoice and utility bill data, normalizes headers and line items, and stores raw JSON in OneLake
5. **Lakehouse Tables** *(new)*: Spark automation converts normalized JSON into managed Delta tables for analytics and governance
6. **Search Index**: Creates searchable index with document content and metadata
7. **AI Foundry Ready**: Backend integration automated for AI Foundry Chat Playground
8. **Query Interface**: Search documents through Azure AI Search REST API, AI Foundry, or portal

#### Example Usage
```bash
# Documents are automatically indexed from:
# Fabric Workspace → Bronze Lakehouse → Files → Documents/

# Search via REST API:
curl -X POST "https://[search-service].search.windows.net/indexes/[index-name]/docs/search?api-version=2024-05-01-preview" \
  -H "Content-Type: application/json" \
  -H "api-key: [admin-key]" \
  -d '{"search": "your search terms"}'

# AI Foundry Integration:
# - Backend API integration fully automated
# - Chat Playground requires manual UI configuration (2-minute setup)
# - Use text search mode (semantic search requires additional index configuration)
```

### OneLake Indexing Scripts

The solution includes comprehensive OneLake indexing automation:

#### Core Scripts
- **`01_setup_ai_search_onelake_indexer.ps1`**: Complete OneLake indexer setup
- **`02_materialize_document_test_data.ps1`**: Test document creation and validation  
- **`03_test_onelake_indexer.ps1`**: Indexer testing and validation
- **`04_cleanup_onelake_environment.ps1`**: Environment cleanup and reset
- **`05_setup_ai_foundry_search_rbac.ps1`**: RBAC configuration for AI Foundry integration
- **`06_automate_ai_foundry_connection.ps1`**: REST API automation for AI Foundry knowledge sources
- **`07_playground_configuration_helper.ps1`**: Manual configuration guidance for Chat Playground UI

#### Automation Level
- **95% Automated**: Infrastructure, indexing, RBAC, and API integration
- **5% Manual**: Chat Playground UI configuration (industry standard limitation)
- **Full Integration**: REST API connections work with citations and knowledge source access

### Document Intelligence Scripts *(New)*

To enrich OneLake search with structured analytics, the deployment now executes dedicated Document Intelligence automation:

| Script | Purpose | Key Outputs |
|--------|---------|-------------|
| `00_resolve_document_intelligence.ps1` | Discovers the Azure AI Document Intelligence endpoint and writes shared configuration to `/tmp/document_intelligence.env`. | Document Intelligence endpoint + API version exported to environment variables |
| `01_extract_document_intelligence.ps1` | Reads new PDFs from `Files/documents/invoices/` and `Files/documents/utility-bills/`, invokes the `prebuilt-invoice` model, and stores normalized JSON in `Files/raw/document-intelligence/<type>/`. | Raw and normalized JSON payloads plus processing manifests |
| `02_transform_document_intelligence.ps1` | Runs a Fabric Spark session to convert normalized JSON into Delta tables (`silver_invoice_header`, `silver_invoice_line`, `silver_utility_bill_header`, `silver_utility_bill_line`). | Managed Delta tables ready for Power BI, KQL, or downstream Fabric workloads |

Each script is idempotent and can be executed independently to reprocess specific folders, enabling a repeatable ingestion loop as new statements arrive.

#### Fabric Data Factory Notebook Automation *(New)*

In addition to the PowerShell automation, the repo now ships with a Fabric-friendly notebook that can be orchestrated inside **Data Factory pipelines** for fully managed, event-driven Document Intelligence processing:

- **Notebook path**: `fabric-notebooks/document_intelligence_pipeline.ipynb`
- **Execution target**: Fabric Data Factory (Data Pipeline) → Notebook activity (Spark)
- **Trigger model**: Event-based trigger for new files landing in `Files/documents/<type>/` or scheduled runs

##### Notebook workflow

1. Resolve pipeline parameters and environment overrides for the Document Intelligence endpoint, lakehouse name, model IDs, and processing limits.
2. Enumerate new documents beneath `Files/documents/invoices/` and `Files/documents/utility-bills/` (or any document types you include in the parameter list).
3. Call Azure AI Document Intelligence with managed identity authentication, polling for completion when required.
4. Write normalized JSON plus processing manifests back to OneLake (`Files/raw/document-intelligence/...`).
5. Materialize or refresh Delta tables (`silver_invoice_*`, `silver_utility_bill_*`) to power downstream analytics.
6. Return a summary DataFrame to drive monitoring dashboards or downstream pipeline branching.

##### Pipeline parameter reference

| Parameter | Required | Default | Purpose |
|-----------|----------|---------|---------|
| `documentIntelligenceEndpoint` | ✅ | — | Azure AI Document Intelligence endpoint (https://<region>.cognitiveservices.azure.com) |
| `documentIntelligenceApiVersion` | ⭕ | `2023-07-31` | API version for analyze requests |
| `documentLakehouseName` | ✅ | — | Lakehouse name that stores documents and silver tables |
| `workspaceId` | ⭕ | — | Fabric workspace ID (set when lineage reporting is required) |
| `documentTypes` | ⭕ | `invoice,utility-bill` | Comma-separated list of document type keys to process |
| `invoiceModelId` | ⭕ | `prebuilt-invoice` | Model ID used for invoice documents |
| `utilityModelId` | ⭕ | `prebuilt-invoice` | Model ID used for utility-bill documents |
| `maxDocumentsPerType` | ⭕ | `25` | Upper bound of documents processed per run (protects pipeline duration) |
| `forceReprocess` | ⭕ | `false` | When `true`, reprocesses even if normalized JSON already exists |

> **Tip**: When invoking the notebook from ad-hoc Spark sessions (outside Data Factory), you can provide the same values through environment variables such as `DOCUMENT_INTELLIGENCE_ENDPOINT` or `DOCUMENT_LAKEHOUSE_NAME`.

##### Deploying the pipeline

1. Upload the notebook to your Fabric workspace (Lakehouse → Notebook → Upload) or directly from the Data Factory authoring experience.
2. Create a **Data Pipeline** and add a **Notebook** activity targeting the uploaded notebook.
3. Bind the parameters above to pipeline parameters or dynamic content (for example, pass `@triggerBody().folderPath` to scope processing by folder).
4. (Optional) Add a **Get Metadata** activity before the notebook to detect new files and pass a filtered list as a parameter.
5. Configure an **Event trigger** on Storage events (`Files/documents/**`) or schedule-based trigger, and publish the pipeline.
6. Monitor run history to validate the summary output; integrate with alerts or Microsoft Fabric Monitoring for production scenarios.

Because the notebook uses managed identity authentication, no keys or secrets are required inside the pipeline definition. Ensure the Fabric workspace's managed identity has the `Cognitive Services User` role on the Document Intelligence resource.

### Technical Implementation

#### OneLake API Integration
- **API Version**: `2024-05-01-preview` (latest preview with OneLake support)
- **Authentication**: Managed identity with automatic RBAC configuration
- **Data Source**: Direct OneLake connection to Fabric workspace lakehouse
- **Indexing Mode**: Real-time document processing with metadata extraction

#### RBAC Automation
The solution includes **enhanced RBAC scripts** that:
- ✅ Use current Fabric API endpoints (fixed from deprecated `/users` to `/roleAssignments`)
- ✅ Handle 409 Conflict responses (resource already exists) as success
- ✅ Provide detailed error reporting and recovery guidance
- ✅ Support cross-platform execution (PowerShell Core)

## 📊 Automation Impact Analysis

### Manual Steps Eliminated: 59-78+ Steps → Single Command

This solution transforms a complex, expert-level process into a **one-command deployment**:

#### 🎯 Before vs After Automation

| **Component** | **Before (Manual Steps)** | **After** | **Time Savings** |
|---------------|---------------------------|-----------|-------------------|
| **Infrastructure** | 15+ Azure Portal steps | ✅ `azd up` | 2-3 hours → 15 min |
| **RBAC Setup** | 8-10 permission configs | ✅ Automated | 1-2 hours → 2 min |
| **AI Skillsets** | 5-8 REST API calls | ✅ Automated | 45 min → 2 min |
| **Search Index** | 6-8 schema definitions | ✅ Automated | 30 min → 1 min |
| **Data Source** | 4-6 connection setups | ✅ Automated | 30 min → 1 min |
| **Indexer Setup** | 8-12 configuration steps | ✅ Automated | 1 hour → 2 min |
| **AI Foundry RBAC** | 6-8 permission steps | ✅ Automated | 45 min → 1 min |
| **AI Foundry API** | 4-6 REST API calls | ✅ Automated | 30 min → 1 min |
| **Configuration** | Manual documentation lookup | ✅ Automated | 15 min → instant |

#### 🔢 Total Impact
- **Manual Steps Eliminated**: **59-78+ expert-level steps**
- **Time Savings**: **6-8 hours → 20 minutes** (95-98% reduction)
- **Complexity Reduction**: **Expert-level → Anyone can deploy**
- **Error Reduction**: **Human errors → Consistent automation**

#### 🏆 Automation Success Rate
- **✅ Fully Automated**: 95-98% of the entire process
- **⚠️ Manual Remaining**: 2-5% (Chat Playground UI - industry standard)
- **🚀 Deployment**: Single command (`azd up`)
- **🔄 Repeatability**: Consistent across environments

#### 💡 Business Impact
- **🚀 Deployment Complexity**: Expert-level → Anyone can run
- **⚡ Time to Value**: Hours → Minutes  
- **🔧 Maintenance**: Manual updates → Infrastructure as Code
- **🎯 Reliability**: Human errors → Consistent automation
- **📈 Scalability**: One-off setup → Repeatable across environments

### Monitoring OneLake Indexing

```bash
# Check indexer status via Azure CLI
az search indexer status show \
  --service-name [search-service] \
  --name [indexer-name] \
  --resource-group [resource-group]

# View indexed documents
az search index show \
  --service-name [search-service] \
  --name [index-name] \
  --resource-group [resource-group]
```

## 🔍 Monitoring & Troubleshooting

### Deployment Monitoring

Monitor deployment progress through:

```bash
# Check azd logs
azd logs

# Monitor specific script execution
tail -f ~/.azd/<env-name>/logs/*.log

# 🆕 Check OneLake indexer status
az search indexer status show --service-name [search-service] --name [indexer-name]
```

### Common Issues

1. **Authentication Errors**
   ```bash
   # Ensure both tools are authenticated
   az account show
   azd auth login --check-status
   ```

2. **Fabric API Token Issues**
   ```bash
   # If standard login fails, try with specific Power BI scope
   az login --scope https://analysis.windows.net/powerbi/api/.default
   ```

3. **Purview Permission Errors**
   - Verify you have Data Source Administrator role
   - Check the Purview account name is correct
   - Ensure the account exists and is accessible

4. **🆕 OneLake Indexer Issues**
   ```bash
   # Check AI Search service logs
   az monitor activity-log list --resource-group [rg-name] --resource [search-service]
   
   # Verify RBAC permissions
   az role assignment list --assignee [managed-identity-id] --scope [fabric-workspace-scope]
   
   # Test OneLake API connectivity
   curl -H "Authorization: Bearer [token]" "https://onelake.dfs.fabric.microsoft.com/[workspace]/[lakehouse]/Files"
   ```

5. **PowerShell Execution Issues**
   ```bash
   # Verify PowerShell Core installation
   pwsh --version
   
   # Check PowerShell execution policy (Windows)
   pwsh -c "Get-ExecutionPolicy"
   ```

6. **Workspace Scoping Issues**
   - Verify workspace was created before scan execution
   - Check `/tmp/fabric_workspace.env` for workspace ID
   - Ensure lakehouses exist before scanning

### Diagnostic Commands

```bash
# 🚨 ALWAYS preview before deploying!
azd provision --preview

# Check deployment status
azd show

# List environment variables
azd env get-values

# Test individual PowerShell scripts
pwsh ./scripts/create_purview_collection.ps1

# Test individual Bash scripts (alternative)
./scripts/create_purview_collection.sh

# Check workspace scoping
cat /tmp/fabric_workspace.env
cat /tmp/fabric_scan_config.json

# 🆕 Verify OneLake indexer configuration
cat /tmp/onelake_indexer_config.json

# 🆕 Test AI Search functionality
curl -X GET "https://[search-service].search.windows.net/indexes?api-version=2024-05-01-preview" \
  -H "api-key: [admin-key]"

# Verify scan results
# (Check Purview portal: Data Map → Sources → Fabric → Scans)
```

**⚡ Best Practice**: Use `azd provision --preview` religiously! It validates your configuration, checks Bicep compilation, and shows resource changes without any risk.

## 🆕 New Features & Enhancements

### OneLake Indexing (Latest Addition)
- **AI Search Integration**: Seamless connection between Azure AI Search and Fabric OneLake
- **Document Processing**: Automatic indexing of documents stored in bronze lakehouse
- **Preview API Support**: Uses latest `2024-05-01-preview` API for OneLake connectivity
- **Managed Identity**: Secure RBAC configuration for AI Search to Fabric workspace access

### Enhanced RBAC Automation
- **Current API Endpoints**: Fixed deprecated Fabric API calls from `/users` to `/roleAssignments`
- **Error Handling**: Proper 409 Conflict handling (treats "already exists" as success)
- **Cross-platform**: PowerShell Core support for Linux/macOS environments
- **Detailed Logging**: Comprehensive error reporting and recovery guidance

### Improved Parameter Resolution
- **Environment Variables**: Enhanced azd environment variable integration
- **Dynamic Detection**: Automatic workspace ID and lakehouse ID discovery
- **Configuration Export**: Saves configuration to `/tmp/` for debugging and reuse

### Comprehensive Documentation
- **Automation Coverage**: Detailed mapping of 25+ Microsoft Learn processes
- **Best Practices**: Azure and Fabric development guidelines
- **Troubleshooting**: Enhanced diagnostic commands and common issue resolution

## 📈 Future Roadmap & Backlog Items

### High Priority Enhancements

#### 🔄 Advanced Document Processing
- **Skill Sets**: Implement Azure AI Search cognitive skills for enhanced document analysis
- **OCR Integration**: Add optical character recognition for scanned documents
- **Multi-language Support**: Extend indexing to support international document formats
- **Custom Extractors**: Domain-specific document processors (legal, financial, medical)

#### 🔗 Data Source Integrations
- **Databricks Integration**: Extend automation to include Databricks workspace integration
- **SAP Connectivity**: Add SAP system data source registration and scanning
- **Oracle Integration**: Support for Oracle database sources within Fabric domains
- **Multi-cloud Sources**: AWS S3 and Google Cloud Storage integration patterns

#### 🛡️ Enhanced Security & Governance
- **Private Endpoints**: Add private endpoint configuration for enhanced security
- **Customer-Managed Keys**: Implement CMK support for data encryption at rest
- **Advanced RBAC**: Fine-grained role assignments and policy automation
- **Compliance Templates**: Pre-configured compliance patterns (SOX, GDPR, HIPAA)

#### 📊 Advanced Analytics & Monitoring
- **Real-time Dashboards**: Power BI integration for deployment and governance monitoring
- **Cost Analytics**: Cost tracking and optimization recommendations
- **Performance Metrics**: Detailed performance monitoring and alerting
- **Usage Analytics**: Data access patterns and governance insights

### Medium Priority Features

#### 🔧 Operational Excellence
- **Blue-Green Deployments**: Zero-downtime deployment strategies
- **Disaster Recovery**: Cross-region backup and recovery automation
- **Configuration Drift**: Automated detection and remediation of configuration changes
- **Health Checks**: Comprehensive health monitoring and automated healing

#### 🌐 Enterprise Integration
- **Active Directory Integration**: Enhanced identity and access management
- **DevOps Pipeline Integration**: GitHub Actions and Azure DevOps templates
- **Infrastructure as Code**: Terraform alternative implementation
- **Multi-tenant Support**: Tenant isolation and management patterns

#### 🎯 User Experience
- **Web Portal**: Custom web interface for deployment management
- **CLI Enhancements**: Interactive deployment wizard and guided configuration
- **Documentation Site**: Comprehensive documentation portal with examples
- **Training Materials**: Video tutorials and hands-on labs

### Future Research Areas

#### 🧠 AI/ML Integration
- **Automated Data Classification**: ML-powered data sensitivity classification
- **Intelligent Data Lineage**: AI-enhanced lineage discovery and mapping
- **Predictive Analytics**: Predictive insights for data governance and quality
- **Natural Language Queries**: AI-powered data discovery through natural language

#### 🔬 Emerging Technologies
- **Edge Computing**: Fabric integration with Azure IoT and edge scenarios
- **Blockchain Integration**: Data provenance and integrity tracking
- **Quantum Computing**: Future-ready quantum algorithm integration
- **Metaverse Data**: Spatial data and virtual environment integration

## 📝 Changelog

### Version 2.0.0 (Current) - OneLake Indexing Release

#### 🆕 New Features
- **AI Search Integration**: Complete Azure AI Search service with OneLake indexing
- **Document Processing**: Automatic document indexing from Fabric lakehouse bronze layer
- **OneLake API**: Integration with preview API `2024-05-01-preview` for direct OneLake access
- **Managed Identity RBAC**: Automated permission configuration between AI Search and Fabric workspace
- **Enhanced Automation**: 16-step fully automated deployment pipeline

#### 🔧 Improvements
- **API Modernization**: Fixed deprecated Fabric API endpoints from `/users` to `/roleAssignments`
- **Error Handling**: Enhanced 409 Conflict handling (treats "already exists" as success)
- **Cross-platform Support**: Improved PowerShell Core compatibility for Linux/macOS
- **Parameter Resolution**: Enhanced azd environment variable integration and dynamic discovery
- **Logging**: Comprehensive error reporting and configuration export to `/tmp/`

#### 🐛 Bug Fixes
- **RBAC Permissions**: Fixed AI Search managed identity access to Fabric workspace
- **API Compatibility**: Updated to current Fabric API v1 endpoints
- **Script Execution**: Resolved PowerShell execution policy issues on different platforms
- **Configuration Export**: Fixed lakehouse ID detection and export functionality

#### 📚 Documentation
- **Comprehensive README**: Updated with OneLake indexing features and AI Search integration
- **Automation Coverage**: Created detailed AUTOMATION_COVERAGE.md mapping 25+ processes
- **Best Practices**: Enhanced troubleshooting and diagnostic commands
- **Architecture Diagrams**: Updated to include AI Search and OneLake indexing flow

### Version 1.0.0 - Foundation Release

#### 🆕 Initial Features
- **Fabric Integration**: Complete Fabric capacity, domain, and workspace automation
- **Purview Integration**: Automated data source registration and workspace-scoped scanning
- **Lakehouse Architecture**: Bronze, silver, gold lakehouse creation and configuration
- **Dual Script Support**: PowerShell and Bash implementations for cross-platform compatibility
- **Azure Developer CLI**: Complete azd integration with post-provision automation

#### 🏗️ Infrastructure
- **Bicep Templates**: Modular infrastructure as code implementation
- **Parameter Management**: Flexible parameter configuration system
- **Resource Organization**: Proper resource grouping and naming conventions
- **Monitoring Setup**: Log Analytics workspace integration

#### 📋 Core Processes
- **Capacity Management**: Fabric capacity validation and assignment
- **Domain Governance**: Fabric domain creation and workspace assignment
- **Data Cataloging**: Purview collection hierarchy and scan configuration
- **Asset Discovery**: Comprehensive lakehouse and dataset scanning
- **Access Control**: Basic RBAC and permission management

## 🤝 Contributing

We welcome contributions to improve this solution! Here's how you can help:

### Ways to Contribute

- 🐛 **Report Issues**: Found a bug? Open an issue with detailed reproduction steps
- 💡 **Feature Requests**: Have ideas for improvements? Share them with us
- 📖 **Documentation**: Help improve our docs and examples
- 🔧 **Code Contributions**: Submit pull requests with enhancements
- 🧪 **Testing**: Test the solution in different environments and share feedback

### Getting Started with Contributing

1. **Fork the Repository**
   ```bash
   git fork <repository-url>
   git clone <your-fork-url>
   cd fabric-purview-domain-integration
   ```

2. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Test Your Changes**
   ```bash
   # Test the solution end-to-end
   azd up
   
   # Test individual components
   ./scripts/your-modified-script.sh
   ```

4. **Submit a Pull Request**
   - Provide clear description of changes
   - Include test results
   - Reference any related issues

### Development Guidelines

- **Script Standards**: Follow the atomic script pattern
- **Error Handling**: Include comprehensive error checking
- **Documentation**: Update README and inline comments
- **Testing**: Verify changes don't break existing functionality

### Community Guidelines

- Be respectful and inclusive
- Provide constructive feedback
- Help others learn and grow
- Share your experiences and learnings

## 📞 Support & Community

- **Issues**: [GitHub Issues](../../issues)
- **Discussions**: [GitHub Discussions](../../discussions)
- **Documentation**: This README and inline script comments

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

This solution leverages:
- [Azure Verified Modules (AVM)](https://github.com/Azure/bicep-registry-modules)
- [Azure Developer CLI](https://docs.microsoft.com/azure/developer/azure-developer-cli/)
- [Microsoft Fabric](https://docs.microsoft.com/fabric/)
- [Microsoft Purview](https://docs.microsoft.com/purview/)
- [Azure AI Search](https://docs.microsoft.com/azure/search/)
- [OneLake API](https://docs.microsoft.com/fabric/onelake/onelake-api-reference)

---

## 🚀 Ready to Get Started?

1. Ensure you have the prerequisites installed
2. Authenticate with both `az login` and `azd auth login`
3. Configure your parameters in `infra/main.bicepparam`
4. Run `azd up` to deploy your data platform with OneLake indexing

**Need help?** Open an issue or start a discussion - our community is here to help! 🤝

### ⚡ What's New in This Release?
- 🔍 **AI Search with OneLake**: Intelligent document search directly from your Fabric workspace
- 🤖 **Automated RBAC**: Seamless permissions between AI Search and Fabric
- 📄 **Document Processing**: Automatic indexing of documents in bronze lakehouse
- 🛠️ **Enhanced Automation**: 16-step fully automated deployment pipeline
- 🐛 **Bug Fixes**: Updated API endpoints and improved error handling
