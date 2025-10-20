# 🔄 azd + GitHub Actions Integration Guide

## Overview

This guide explains how to combine Azure Developer CLI (`azd`) with GitHub Actions for a complete deployment solution.

---

## 🎯 Integration Strategies

### **Strategy 1: azd for Infrastructure, GitHub Actions for Automation** ⭐ **RECOMMENDED**

Use `azd` to provision **infrastructure only** (Fabric capacity, Purview account), then trigger GitHub Actions for **configuration automation** (domains, workspaces, collections).

#### **Pros**
- ✅ Clean separation of concerns (infra vs config)
- ✅ Leverage `azd`'s infrastructure management
- ✅ Use GitHub Actions for complex orchestration
- ✅ Can still use your PowerShell scripts
- ✅ Best of both worlds

#### **Cons**
- ⚠️ Two tools to learn
- ⚠️ More complex setup

#### **When to Use**
- You have complex infrastructure (networking, private endpoints, etc.)
- You want `azd`'s environment management (`azd env`, `azd up`)
- You need both infrastructure and automation

---

### **Strategy 2: GitHub Actions Calls azd in Hooks**

Trigger GitHub Actions workflows from `azd` hooks (postprovision, postup).

#### **Pros**
- ✅ Single command: `azd up` does everything
- ✅ Familiar `azd` workflow for users
- ✅ GitHub Actions handles automation complexity

#### **Cons**
- ⚠️ Requires GitHub CLI (`gh`) installed locally
- ⚠️ Need GitHub authentication in addition to Azure
- ⚠️ Debugging is harder (two layers)

#### **When to Use**
- You're already using `azd` and want to add automation
- Users prefer single `azd up` command
- You want post-provision automation without manual steps

---

### **Strategy 3: GitHub Actions Only** ⭐ **YOUR CURRENT APPROACH**

No `azd`, just GitHub Actions calling PowerShell scripts directly.

#### **Pros**
- ✅ Simplest (one tool only)
- ✅ No local dependencies
- ✅ Full control in GitHub Actions
- ✅ Best for teams already on GitHub

#### **Cons**
- ⚠️ No infrastructure provisioning
- ⚠️ Assumes resources already exist

#### **When to Use**
- Infrastructure is managed separately (portal, Terraform, etc.)
- You only need automation, not infrastructure deployment
- **THIS IS YOUR CURRENT SETUP** ✅

---

## 📋 Comparison Table

| Feature | azd Only | azd + GitHub Actions | GitHub Actions Only |
|---------|----------|---------------------|-------------------|
| **Infrastructure** | ✅ Bicep/Terraform | ✅ azd provision | ❌ Manual/separate |
| **Automation** | ⚠️ Hooks only | ✅ Full workflows | ✅ Full workflows |
| **Local Dev** | ✅ `azd up` | ✅ `azd up` | ❌ Need `gh` CLI |
| **CI/CD** | ⚠️ Limited | ✅ Best of both | ✅ Native |
| **Debugging** | ✅ Local logs | ⚠️ Two places | ✅ GitHub UI |
| **Team Visibility** | ❌ Local only | ⚠️ Split | ✅ All in GitHub |
| **Secret Management** | ⚠️ `.env` files | ⚠️ Split | ✅ GitHub Secrets |
| **Cost** | Free | Free | Free |
| **Complexity** | Low | **High** | **Low** |

---

## 🔧 Implementation Examples

### **Example 1: azd → GitHub Actions (Post-Provision Hook)**

Use this if you want `azd up` to trigger automation after infrastructure is provisioned.

#### Setup Steps

1. **Create `azure.yaml` with hook**:

```yaml
# azure.yaml
name: fabric-purview-integration
metadata:
  template: fabric-purview-integration@0.0.1

infra:
  provider: bicep
  path: infra
  module: main

hooks:
  postprovision:
    posix:
      shell: sh
      run: |
        echo "🚀 Triggering GitHub Actions automation..."
        
        # Get infrastructure outputs
        CAPACITY_ID=$(azd env get-values | grep FABRIC_CAPACITY_ID | cut -d'=' -f2)
        RG_NAME=$(azd env get-values | grep AZURE_RESOURCE_GROUP | cut -d'=' -f2)
        
        # Trigger GitHub Actions workflow
        gh workflow run deploy-fabric-integration.yml \
          --ref main \
          --field environment=dev \
          --field skip_infrastructure=true
        
        echo "✅ GitHub Actions workflow triggered!"
        echo "   View: gh run list --workflow=deploy-fabric-integration.yml"
```

2. **Ensure GitHub CLI is authenticated**:

```bash
# One-time setup on local machine
gh auth login

# Verify
gh auth status
```

3. **Run deployment**:

```bash
# Single command provisions infrastructure AND triggers automation
azd up
```

#### What Happens

1. `azd provision` runs → Provisions Fabric capacity, Purview account via Bicep
2. `postprovision` hook triggers → Calls `gh workflow run`
3. GitHub Actions workflow runs → Creates domains, workspaces, collections
4. `azd up` completes → Everything deployed!

---

### **Example 2: GitHub Actions → azd (Infrastructure First)**

Use this if you want GitHub Actions to control the entire flow, including infrastructure.

#### Setup Steps

1. **Add azd step to workflow**:

```yaml
# .github/workflows/full-deployment.yml
jobs:
  provision-infrastructure:
    name: Provision Infrastructure with azd
    runs-on: ubuntu-latest
    outputs:
      capacity_id: ${{ steps.outputs.outputs.capacity_id }}
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Install azd
        uses: Azure/setup-azd@v1.0.0
      
      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Provision with azd
        run: |
          azd env new fabric-dev --subscription ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          azd provision --no-prompt
      
      - name: Get Outputs
        id: outputs
        run: |
          CAPACITY_ID=$(azd env get-values | grep FABRIC_CAPACITY_ID | cut -d'=' -f2)
          echo "capacity_id=$CAPACITY_ID" >> $GITHUB_OUTPUT

  # Then your existing jobs use the capacity_id output
  create-fabric-domain:
    needs: [provision-infrastructure]
    # ... rest of job
```

2. **Run from GitHub Actions UI**:

```bash
# Manual trigger
gh workflow run full-deployment.yml --ref main --field environment=dev

# Or via UI: Actions → full-deployment.yml → Run workflow
```

#### What Happens

1. GitHub Actions starts
2. Job 1: `azd provision` runs in GitHub runner → Provisions infrastructure
3. Job 2+: Your automation jobs run → Configure Fabric/Purview
4. GitHub Actions completes → Full deployment done

---

### **Example 3: Hybrid with Outputs**

Pass infrastructure outputs from `azd` to GitHub Actions automation.

#### In `main.bicep`:

```bicep
output fabricCapacityId string = fabricCapacity.id
output fabricCapacityName string = fabricCapacity.name
output purviewAccountId string = purviewAccount.id
output resourceGroupName string = resourceGroup().name
```

#### In `azure.yaml`:

```yaml
hooks:
  postprovision:
    posix:
      shell: sh
      run: |
        # Extract azd outputs
        CAPACITY_ID=$(azd env get-values | grep FABRIC_CAPACITY_ID | cut -d'=' -f2)
        CAPACITY_NAME=$(azd env get-values | grep FABRIC_CAPACITY_NAME | cut -d'=' -f2)
        PURVIEW_ID=$(azd env get-values | grep PURVIEW_ACCOUNT_ID | cut -d'=' -f2)
        RG_NAME=$(azd env get-values | grep AZURE_RESOURCE_GROUP | cut -d'=' -f2)
        
        # Create temporary config file for GitHub Actions
        cat > .github/config/azd-outputs.yml <<EOF
        azure:
          resource_group: $RG_NAME
        fabric:
          capacity:
            name: $CAPACITY_NAME
            id: $CAPACITY_ID
        purview:
          account_id: $PURVIEW_ID
        EOF
        
        # Commit and push (or use as artifact)
        git add .github/config/azd-outputs.yml
        git commit -m "chore: azd infrastructure outputs"
        git push
        
        # Trigger workflow
        gh workflow run deploy-fabric-integration.yml \
          --ref $(git branch --show-current) \
          --field config_file=.github/config/azd-outputs.yml
```

---

## 🚀 Recommended Approach for Your Project

Based on your current setup and requirements, I recommend:

### **Option A: Stay with GitHub Actions Only** ⭐ **BEST FOR YOU**

**Reasoning**:
- ✅ You've already built a clean GitHub Actions solution
- ✅ No deployment scripts needed (they failed anyway)
- ✅ Infrastructure is created separately (portal or separate Terraform)
- ✅ Simpler for your team (one tool, one place)
- ✅ Better telemetry (Log Analytics integration)

**Keep as-is**: Your current `deploy-fabric-integration.yml` workflow.

---

### **Option B: Add azd for Infrastructure** (if you want infrastructure automation)

**When to add**:
- You decide to automate Fabric capacity provisioning (currently manual)
- You want `azd`'s environment management features
- You need to provision other Azure resources (VNets, Key Vaults, etc.)

**How to add**:

1. **Create lightweight `azure.yaml`**:

```yaml
name: fabric-purview-integration
infra:
  provider: bicep
  path: infra
  module: main-infrastructure-only  # Just capacity + Purview account

hooks:
  postprovision:
    posix:
      run: |
        gh workflow run deploy-fabric-integration.yml \
          --ref main \
          --field skip_infrastructure=true
```

2. **Create `infra/main-infrastructure-only.bicep`**:

```bicep
// Provisions ONLY:
// - Fabric Capacity
// - Purview Account
// - Resource Group
// - (Optional) Networking

param location string = 'eastus'
param fabricCapacitySku string = 'F2'

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: 'fabric-capacity-${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: fabricCapacitySku
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: []  // Manually add admins
    }
  }
}

resource purviewAccount 'Microsoft.Purview/accounts@2021-12-01' = {
  name: 'purview-${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Standard'
    capacity: 1
  }
}

output fabricCapacityId string = fabricCapacity.id
output fabricCapacityName string = fabricCapacity.name
output purviewAccountId string = purviewAccount.id
output purviewAccountName string = purviewAccount.name
```

3. **Use**:

```bash
# Provision infrastructure + trigger automation
azd up

# Or separately
azd provision  # Infrastructure
azd deploy     # Triggers GitHub Actions via hook
```

---

## 📊 Decision Matrix

| If you need... | Use... |
|---------------|--------|
| Only Fabric/Purview automation | **GitHub Actions only** (current) |
| Infrastructure + automation | **azd + GitHub Actions** (hybrid) |
| Local development workflow | **azd with hooks** |
| CI/CD with full control | **GitHub Actions calling azd** |
| Simplest possible setup | **GitHub Actions only** ✅ |
| Complex infrastructure | **azd + Bicep + GitHub Actions** |

---

## 🎯 Action Items for Your Project

### **Short Term (Keep Current Approach)**

1. ✅ Continue with GitHub Actions-only workflow
2. ✅ Document manual infrastructure setup (capacity, Purview)
3. ✅ Use your existing telemetry to Log Analytics

### **Long Term (If Infrastructure Automation Needed)**

1. Create `azure.yaml` with `postprovision` hook
2. Create minimal `main-infrastructure-only.bicep` (capacity + Purview only)
3. Test `azd up` → GitHub Actions flow
4. Document hybrid approach for team

---

## 📚 Additional Resources

- [azd Hooks Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/azd-extensibility)
- [GitHub CLI Manual](https://cli.github.com/manual/)
- [Azure/setup-azd Action](https://github.com/Azure/setup-azd)
- [azd Environment Management](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/manage-environment-variables)

---

## 💡 Summary

**For your specific situation**:

- ✅ **Current approach is optimal**: GitHub Actions only
- ⚠️ **Don't add azd unless**: You need infrastructure automation
- 🎯 **If you add azd later**: Use it for infrastructure, keep GitHub Actions for automation
- 📊 **Integration is possible**: But adds complexity without clear benefit right now

**Bottom line**: Your current GitHub Actions-only approach is **perfect for your use case**. Only add `azd` if you decide to automate Fabric capacity provisioning later.
