# GitHub Actions Automation for Fabric-Purview Integration

This branch contains **GitHub Actions workflows** that replicate the same automation as the PowerShell scripts, but run in the cloud with full visibility and no local dependencies.

## 🚀 Why GitHub Actions?

**Deployment Scripts Problem**: We tried using Azure Deployment Scripts in Bicep, but hit a subscription constraint that blocks `allowSharedKeyAccess` on storage accounts. Deployment scripts require this, so that approach is dead.

**GitHub Actions Solution**: 
- ✅ **No storage accounts needed** - logs stored by GitHub
- ✅ **Uses your existing PowerShell scripts** - no rewrite needed
- ✅ **Federated credentials** - OIDC authentication, no secrets!
- ✅ **Full visibility** - every step logged in GitHub UI
- ✅ **Customizable** - enable/disable any step via config file
- ✅ **Runs after Fabric capacity** is installed

## 📁 What's in This Branch?

```
.github/
├── config/
│   └── deployment-config.yml      # User configuration - customize here!
└── workflows/
    └── deploy-fabric-integration.yml  # Main orchestration workflow

scripts/
└── Fabric_Purview_Automation/     # Your existing PowerShell scripts (unchanged!)
```

**What's NOT in this branch:**
- ❌ No Bicep deployment script modules (they don't work)
- ❌ No bash scripts (we use your PowerShell)
- ❌ No storage accounts or managed identities for scripts

## 🛠️ Setup Instructions

### Step 1: Run Setup Script

This creates the Azure App Registration with federated credentials:

```bash
cd .github/scripts
chmod +x setup-federated-credentials.sh
./setup-federated-credentials.sh mswantek68/fabric-purview-domain-integration
```

**What it does:**
1. Creates App Registration `github-actions-fabric-automation`
2. Creates Service Principal
3. Assigns Azure RBAC roles (Contributor, User Access Administrator)
4. Creates federated credentials for:
   - `main` branch
   - `feature/*` branches  
   - Pull requests
   - Production environment

**Outputs:**
- `AZURE_CLIENT_ID` - copy to config file
- `AZURE_TENANT_ID` - copy to config file
- `AZURE_SUBSCRIPTION_ID` - copy to config file

### Step 2: Manual Role Assignments (Required)

Some roles CANNOT be automated and must be assigned manually:

#### Fabric Administrator Role
1. Go to https://app.fabric.microsoft.com
2. Click ⚙️ Settings → Admin Portal
3. Navigate to: Tenant settings → Admin API settings
4. Enable "Service principals can use Fabric APIs"
5. Add service principal: `github-actions-fabric-automation`
6. In Capacity settings, add as admin

#### Purview Data Curator Role
```bash
PURVIEW_ACCOUNT="your-purview-account"
RESOURCE_GROUP="your-rg"

az role assignment create \
  --assignee <AZURE_CLIENT_ID from step 1> \
  --role "Purview Data Curator" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Purview/accounts/$PURVIEW_ACCOUNT"
```

### Step 3: Configure Deployment

Edit `.github/config/deployment-config.yml`:

```yaml
azure:
  tenant_id: "YOUR_TENANT_ID"           # From setup script
  subscription_id: "YOUR_SUBSCRIPTION_ID"
  client_id: "YOUR_APP_REGISTRATION_CLIENT_ID"
  resource_group: "rg-dev101725"
  location: "eastus2"

fabric:
  capacity:
    name: "swancapacitytest1017"        # Must exist before running workflow
  
  domain:
    enabled: true                       # Set false to skip
    name: "Analytics Domain"
  
  workspace:
    enabled: true
    name: "analytics-workspace-dev"
  
  assign_to_domain:
    enabled: true                       # Assign workspace to domain
  
  lakehouses:
    enabled: true
    names:
      - bronze
      - silver
      - gold

purview:
  account_name: "YOUR_PURVIEW_ACCOUNT"
  
  collection:
    enabled: true
    name: "fabric-analytics-collection"
  
  register_datasource:
    enabled: true
  
  trigger_scan:
    enabled: false                      # Optional - enable to auto-scan

monitoring:
  log_analytics:
    enabled: false                      # Optional
```

### Step 4: Push Configuration

```bash
git add .github/config/deployment-config.yml
git commit -m "Configure deployment settings"
git push origin feature/github-actions-automation
```

### Step 5: Run Workflow

1. Go to GitHub: **Actions** → **Deploy Fabric-Purview Integration**
2. Click **Run workflow**
3. Select:
   - **Branch:** `feature/github-actions-automation`
   - **Environment:** `dev`
   - **Config file:** `.github/config/deployment-config.yml` (default)
   - **Dry run:** Leave unchecked
4. Click **Run workflow**

## 🎯 Customization

### Enable/Disable Steps

In `deployment-config.yml`, set `enabled: false` for any step you want to skip:

```yaml
fabric:
  domain:
    enabled: false    # Skip domain creation
  lakehouses:
    enabled: false    # Skip lakehouse creation

purview:
  trigger_scan:
    enabled: true     # Enable scan triggering
```

### Change Resource Names

All resource names are parameterized:

```yaml
fabric:
  domain:
    name: "My Custom Domain"
  workspace:
    name: "my-workspace-prod"
  lakehouses:
    names:
      - raw
      - curated
      - analytics
```

### Multiple Environments

Create different config files:

```
.github/config/
├── deployment-config-dev.yml
├── deployment-config-staging.yml
└── deployment-config-prod.yml
```

Run with:
```yaml
workflow_dispatch:
  inputs:
    config_file: '.github/config/deployment-config-prod.yml'
```

## 📊 Workflow Visualization

```
┌──────────────────────┐
│  Load Configuration  │
└──────────┬───────────┘
           ↓
┌──────────────────────┐
│ Get Capacity Info    │ ← Capacity must exist!
└──────────┬───────────┘
           ↓
┌──────────────────────┐
│ Ensure Capacity      │ ← Resume if paused
│    Active            │
└──────────┬───────────┘
           ↓
     ┌─────┴─────┐
     ↓           ↓
┌─────────┐  ┌──────────┐
│ Fabric  │  │ Purview  │
│  RBAC   │  │   RBAC   │
│(verify) │  │ (verify) │
└────┬────┘  └─────┬────┘
     ↓             ↓
┌─────────┐  ┌──────────┐
│ Create  │  │  Create  │
│ Domain  │  │Collection│
└────┬────┘  └─────┬────┘
     ↓             ↓
┌─────────┐  ┌──────────┐
│ Create  │  │ Register │
│Workspace│  │Datasource│
└────┬────┘  └─────┬────┘
     ↓             ↓
┌─────────┐  ┌──────────┐
│ Assign  │  │ Trigger  │
│to Domain│  │   Scan   │
└────┬────┘  └──────────┘
     ↓
┌─────────┐
│ Create  │
│Lakehouses│
└──────────┘
```

## 🔍 Monitoring & Logs

### GitHub Actions UI

All logs visible in:
- **Actions tab** → Workflow run
- Each job shows:
  - Status (✅ Success, ❌ Failed, ⏭️ Skipped)
  - Duration
  - Full console output
  - PowerShell script output

### Deployment Summary

After workflow completes, see summary with:
- All step statuses
- Resource names created
- Links to workflow run
- Triggered by user

## 🆚 Comparison: GitHub Actions vs. azd

| Aspect | `azd provision` | GitHub Actions |
|--------|----------------|----------------|
| **Runs where** | Local machine | GitHub cloud runners |
| **Prerequisites** | azd CLI, Azure CLI, PowerShell | None (runs in cloud) |
| **Authentication** | User login (device code) | Federated credentials (automatic) |
| **Logs** | Terminal output (lost after close) | Persistent GitHub UI logs |
| **Resumability** | Manual re-run from scratch | Individual job retry |
| **Visibility** | Only to person running | Entire team can see |
| **Customization** | Edit Bicep/scripts locally | Config file in repo |
| **Approval gates** | None | GitHub Environments with approvals |
| **Notifications** | None | GitHub notifications, Slack, Teams |
| **Storage account issue** | ❌ BLOCKED | ✅ Not needed! |

## 🚦 Next Steps

After successful run:

1. **Verify in Azure Portal:**
   - Fabric capacity is active
   - Domain created
   - Workspace exists and assigned to domain
   - Lakehouses created (bronze, silver, gold)

2. **Verify in Purview:**
   - Collection created
   - Fabric workspace registered as datasource
   - (Optional) Scan completed if enabled

3. **Monitor ongoing:**
   - Re-run workflow anytime to ensure consistency
   - Enable `skip_existing: true` to only create missing resources

## 🐛 Troubleshooting

### "Failed to get Fabric API token"
- **Cause:** Service principal not assigned Fabric Administrator role
- **Fix:** Complete Step 2 (Manual Role Assignments) above

### "Failed to create domain"
- **Cause:** Service principal lacks Fabric Admin permissions
- **Fix:** Verify in Fabric Portal → Admin → Capacity settings

### "Purview collection creation failed"
- **Cause:** Service principal lacks Purview Data Curator role
- **Fix:** Run the `az role assignment create` command from Step 2

### Workflow doesn't start
- **Cause:** Federated credentials not set up
- **Fix:** Run setup script from Step 1

## 📚 Additional Resources

- [GitHub OIDC with Azure](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Fabric REST API](https://learn.microsoft.com/en-us/rest/api/fabric/)
- [Purview REST API](https://learn.microsoft.com/en-us/rest/api/purview/)
- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)

---

**Note:** This branch contains NO Bicep deployment script modules. Those were attempted in `feature/bicep-deployment-modules` but failed due to subscription storage account constraints. This approach uses GitHub Actions + your existing PowerShell scripts instead.
