# Microsoft Fabric + Purview Data Governance Accelerator

## 🚀 Overview

This solution automates a Microsoft Fabric environment integrated with Microsoft Purview for data governance. It creates a domain aligned data platform including Fabric capacity, workspaces, domains, and Purview collections with automated governance integration.
This idea will be integrated into a larger deployment. Main point to keep in mind, I am using very atomic scripts to allow for endless configurations as I learn more about how to integrate source systems into Fabric (ie: Databricks, Oracle, SAP, etc.) and Purview domains. This should allow for a custom yaml file that can be adapted for each domain created.

### What Gets Deployed

- **Microsoft Fabric Capacity**: High-performance compute capacity for Fabric workloads and separation
- **Fabric Workspace**: Collaborative workspace for data engineering and analytics
- **Fabric Domain**: Organized data domain structure (governance-focused)
- **Purview Collections**: Data catalog collections for governance and discovery
- **Fabric Datasources**: Registered datasources for scanning and governance
- **Lakehouses**: Storage and compute layers for data lakehouse architecture

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

- **Microsoft Purview Account**: You must have an existing Purview account
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

## 📚 Solution Components

### Infrastructure (Bicep)

- `infra/main.bicep`: Main infrastructure definition
- `infra/main.bicepparam`: Configuration parameters
- `infra/core/`: Reusable infrastructure modules

### Automation Scripts

The solution uses atomic scripts for modular, testable automation:

| Script | Purpose | Dependencies |
|--------|---------|--------------|
| `ensure_active_capacity.sh` | Validate Fabric capacity | Fabric Admin |
| `create_fabric_domain.sh` | Create Fabric governance domain | Fabric Admin |
| `create_fabric_workspace.sh` | Create Fabric workspace | Fabric Capacity |
| `assign_workspace_to_domain.sh` | Assign workspace to domain | Workspace + Domain |
| `create_purview_collection.sh` | Create Purview collection | Purview Admin |
| `register_fabric_datasource.sh` | Register Fabric as datasource | Collection |
| `setup_fabric_scan_guidance.sh` | Configure scan guidance | Datasource |
| `connect_log_analytics.sh` | Connect monitoring | Log Analytics |
| `create_lakehouses.sh` | Create lakehouse storage | Workspace |

### Atomic Script Architecture

Each script is designed to be:
- **Single-purpose**: One responsibility per script
- **Idempotent**: Safe to run multiple times
- **Error-resilient**: Comprehensive error handling
- **Observable**: Detailed logging and status reporting

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

### Diagnostic Commands

```bash
# Check deployment status
azd show

# List environment variables
azd env get-values

# Test individual scripts
./scripts/create_purview_collection.sh
```

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
