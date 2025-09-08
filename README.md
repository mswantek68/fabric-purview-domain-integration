# Microsoft Fabric + Purview Data Governance Accelerator

## 🚀 Overview

This solution automates a Microsoft Fabric environment integrated with Microsoft Purview for data governance. It creates a domain aligned data platform including Fabric capacity, workspaces, domains, and Purview collections with automated governance integration and **workspace-scoped scanning**.

This solution features **dual script support** - both **PowerShell** and **Bash** implementations for maximum compatibility across different environments and preferences. The PowerShell implementation provides enhanced error handling and cross-platform support via PowerShell Core.

This idea will be integrated into a larger deployment. Main point to keep in mind, I am using very atomic scripts to allow for endless configurations as I learn more about how to integrate source systems into Fabric (ie: Databricks, Oracle, SAP, etc.) and Purview domains. This should allow for a custom yaml file that can be adapted for each domain created.

### What Gets Deployed

- **Microsoft Fabric Capacity**: High-performance compute capacity for Fabric workloads and separation
- **Fabric Workspace**: Collaborative workspace for data engineering and analytics
- **Fabric Domain**: Organized data domain structure (governance-focused)
- **Purview Collections**: Data catalog collections for governance and discovery
- **Fabric Datasources**: **Registered Fabric data source in Purview** for governance integration
- **Lakehouses**: Bronze, Silver, and Gold data lakehouse architecture
- **Workspace-Scoped Scans**: **Purview scans of the Fabric data source** configured to target only the created workspace, ensuring precise data discovery and governance

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Microsoft Fabric                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐               │
│  │  Fabric Domain  │    │ Fabric Capacity │               │
│  │                 │    │                 │               │
│  │ ┌─────────────┐ │    │   ┌─────────┐   │               │
│  │ │ Workspace   │ │    │   │  F64     │   │               │
│  │ │             │ │    │   │ Compute  │   │               │
│  │ │ ┌─────────┐ │ │    │   └─────────┘   │               │
│  │ │ │Lakehouse│ │ │    └─────────────────┘               │
│  │ │ └─────────┘ │ │                                      │
│  │ └─────────────┘ │                                      │
│  └─────────────────┘                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Data Governance
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Microsoft Purview                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Data Map Collections                       ││
│  │                                                         ││
│  │  ┌─────────────────┐    ┌─────────────────┐           ││
│  │  │ Fabric Collection│    │ Registered      │           ││
│  │  │                 │    │ Datasources     │           ││
│  │  │ ┌─────────────┐ │    │                 │           ││
│  │  │ │ Scans       │ │    │ ┌─────────────┐ │           ││
│  │  │ └─────────────┘ │    │ │ Fabric/     │ │           ││
│  │  └─────────────────┘    │ │ PowerBI     │ │           ││
│  │                         │ └─────────────┘ │           ││
│  │                         └─────────────────┘           ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

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
   
   # Or use package managers:
   # Ubuntu: sudo apt install powershell
   # macOS: brew install powershell
   ```

### Required Authentication & Permissions

⚠️ **CRITICAL**: You must authenticate with **both** Azure CLI and Azure Developer CLI:
This will be replaced with SPN to handle configurations and API calls.

```bash
# 1. Authenticate with Azure CLI (required for Fabric/Power BI API calls)
az login

# 2. Authenticate with Azure Developer CLI
azd auth login
```

### Required Azure Permissions

Your Azure account needs the following permissions:

- **Azure Subscription**: Contributor or Owner role
- **Microsoft Fabric**: Fabric Administrator or equivalent
- **Microsoft Purview**: Data Source Administrator role
- **Power BI**: Power BI Administrator (for Fabric workspace operations)

### Existing Resources Required

- **Microsoft Purview Account**: You must have an existing Purview account. It should be registered as the tenant default.
  - Update the `purviewAccountName` parameter in `infra/main.bicepparam`
  - Ensure your account has appropriate Purview permissions

## 🚀 Quick Start

### 1. Clone and Initialize

```bash
git clone <repository-url>
cd AVM-Deploy-Tests
azd init
```

### 2. Configure Parameters

Edit `infra/main.bicepparam` to customize your deployment:

```bicep
param fabricCapacityName = 'your-capacity-name'
param fabricWorkspaceName = 'your-workspace-name'
param domainName = 'your-domain-name'
param purviewAccountName = 'your-existing-purview-account'
param fabricCapacitySKU = 'F64'  // Adjust based on your needs
```

### 3. Deploy

```bash
# Ensure you're authenticated
az login
azd auth login

# Deploy the solution
azd up
```

**💡 Pro Tip**: Always run `azd provision --preview` first! This catches configuration errors, validates Bicep compilation, and shows you exactly what resources will be created without making any actual changes. It's a lifesaver for catching issues before deployment.

## 🔧 Configuration

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

- `infra/main.bicep`: Main infrastructure definition
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
| `trigger_purview_scan_for_fabric_workspace.*` | **Locate registered data source and execute workspace-scoped scan** | Lakehouses + **Registered Datasource** |
| `connect_log_analytics.*` | Connect monitoring | Log Analytics |

**Key Feature**: The solution follows a **strict dependency order**: **first registers the entire Fabric tenant as a data source in Purview**, then creates a **scoped scan** that can successfully locate and scan only the specific workspace created by the deployment. This ensures comprehensive data governance while maintaining precise control over what gets scanned and cataloged.

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
4. **Data Governance**: **Workspace-scoped Purview scan execution** (locates registered data source and scans workspace)

**Critical Dependencies**: 
- The Fabric data source **must be registered in Purview first** before any scan can locate it
- The Purview scan is executed **after** lakehouse creation to ensure all workspace assets are discoverable
- Scans can only find and catalog assets from **registered data sources**

## 🔍 Monitoring & Troubleshooting

### Deployment Monitoring

Monitor deployment progress through:

```bash
# Check azd logs
azd logs

# Monitor specific script execution
tail -f ~/.azd/<env-name>/logs/*.log
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
   # Re-authenticate with Power BI scope
   az login --scope https://analysis.windows.net/powerbi/api/.default
   ```

3. **Purview Permission Errors**
   - Verify you have Data Source Administrator role
   - Check the Purview account name is correct
   - Ensure the account exists and is accessible

4. **PowerShell Execution Issues**
   ```bash
   # Verify PowerShell Core installation
   pwsh --version
   
   # Check PowerShell execution policy (Windows)
   pwsh -c "Get-ExecutionPolicy"
   ```

5. **Workspace Scoping Issues**
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

# Verify scan results
# (Check Purview portal: Data Map → Sources → Fabric → Scans)
```

**⚡ Best Practice**: Use `azd provision --preview` religiously! It validates your configuration, checks Bicep compilation, and shows resource changes without any risk.

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
   cd AVM-Deploy-Tests
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

---

## 🚀 Ready to Get Started?

1. Ensure you have the prerequisites installed
2. Authenticate with both `az login` and `azd auth login`
3. Configure your parameters in `infra/main.bicepparam`
4. Run `azd up` to deploy your data platform

**Need help?** Open an issue or start a discussion - our community is here to help! 🤝
