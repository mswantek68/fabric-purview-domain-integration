# 🚀 GitHub Actions Deployment Guide

## Overview

This guide walks you through deploying the Fabric-Purview integration using GitHub Actions. Unlike the Bicep deployment scripts (which failed due to storage constraints), this approach runs your existing PowerShell scripts in GitHub Actions with federated authentication.

**⏱️ Setup Time**: ~30 minutes (one-time)  
**🔄 Deployment Time**: ~15 minutes per run

---

## 📋 Prerequisites

Before starting, ensure you have:

- ✅ **Azure Subscription** with:
  - Contributor or Owner role
  - User Access Administrator role (for RBAC assignments)
- ✅ **Existing Fabric Capacity** (F2 or higher, actively running)
- ✅ **Existing Purview Account** (with Data Curator role for yourself)
- ✅ **GitHub Repository** with:
  - Admin access
  - Actions enabled
- ✅ **Local Tools**:
  - Azure CLI (`az`) version 2.50+
  - `jq` for JSON parsing
  - Git

### ⚠️ Important Notes

1. **Fabric capacity must exist BEFORE running workflows** - this automation does NOT deploy infrastructure
2. **Manual RBAC required** - Fabric Administrator and Purview Data Curator roles cannot be automated
3. **GitHub Actions free tier**: 2,000 minutes/month for private repos, unlimited for public repos

---

## 🔧 Setup (One-Time)

### Step 1: Create Federated Credentials

Run the setup script to create Azure App Registration with OIDC authentication.

**Choose your preferred method:**

#### Option A: PowerShell (Windows/Mac/Linux)

```powershell
# Navigate to repository
cd /workspaces/fabric-purview-domain-integration

# Run setup script
./.github/scripts/setup-federated-credentials.ps1 `
    -RepositoryFullName "YOUR_ORG/YOUR_REPO"

# Example:
./.github/scripts/setup-federated-credentials.ps1 `
    -RepositoryFullName "mswantek68/fabric-purview-domain-integration"
```

#### Option B: Bash (Linux/Mac/WSL)

```bash
# Navigate to repository
cd /workspaces/fabric-purview-domain-integration

# Make script executable
chmod +x .github/scripts/setup-federated-credentials.sh

# Run setup
./.github/scripts/setup-federated-credentials.sh YOUR_ORG/YOUR_REPO

# Example:
./.github/scripts/setup-federated-credentials.sh mswantek68/fabric-purview-domain-integration
```

**What this creates**:
- App Registration: `github-actions-fabric-automation`
- Service Principal with Contributor + User Access Administrator roles
- Federated credentials for: `main` branch, `feature/github-actions-automation`, pull requests

**Script output** (save these values):
```
✅ Setup Complete!

Add these secrets to your GitHub repository:
  AZURE_CLIENT_ID: <guid>
  AZURE_TENANT_ID: <guid>
  AZURE_SUBSCRIPTION_ID: <guid>
```

### Step 2: Manual RBAC Assignments

GitHub Actions **cannot** automate these roles (they require different APIs):

#### 2a. Fabric Administrator Role

1. Open [Fabric Admin Portal](https://app.fabric.microsoft.com/admin)
2. Navigate to **Tenant settings** → **Admin API settings**
3. Enable **"Service principals can use Fabric APIs"**
4. Navigate to **Users** → **Manage Roles**
5. Add your service principal to **Fabric Administrator** role:
   - Search for: `github-actions-fabric-automation`
   - Select the app
   - Assign **Fabric Administrator**

**Verification**:
```bash
# Check if service principal is Fabric admin
az ad sp show --id <CLIENT_ID> --query "appRoles[?value=='FabricAdministrator']"
```

#### 2b. Purview Data Curator Role

```bash
# Get your Purview account resource ID
PURVIEW_ID=$(az purview account show \
  --name YOUR_PURVIEW_ACCOUNT \
  --resource-group YOUR_RESOURCE_GROUP \
  --query id -o tsv)

# Assign Data Curator to service principal
az role assignment create \
  --assignee <CLIENT_ID_FROM_STEP_1> \
  --role "Purview Data Curator" \
  --scope "$PURVIEW_ID"

# Verify assignment
az role assignment list \
  --assignee <CLIENT_ID> \
  --scope "$PURVIEW_ID" \
  --query "[?roleDefinitionName=='Purview Data Curator']"
```

### Step 3: Configure Deployment Settings

Edit the configuration file to match your environment:

```bash
# Open config in editor
code .github/config/deployment-config.yml
```

**Required changes**:

```yaml
azure:
  tenant_id: "<TENANT_ID_FROM_STEP_1>"
  subscription_id: "<SUBSCRIPTION_ID_FROM_STEP_1>"
  client_id: "<CLIENT_ID_FROM_STEP_1>"
  resource_group: "rg-fabric-prod"  # Your resource group

fabric:
  capacity:
    name: "fabriccapacityprod"  # Your existing capacity name
    resource_group: "rg-fabric-infrastructure"  # May differ from main RG
  
  domain:
    enabled: true  # Set to false to skip domain creation
    name: "Sales Analytics"
    description: "Sales team data domain"
  
  workspace:
    enabled: true
    name: "ws-sales-analytics-prod"
    description: "Production workspace for sales analytics"
  
  lakehouses:
    enabled: true
    names:
      - "bronze_sales"
      - "silver_sales"
      - "gold_sales"

purview:
  account:
    name: "purview-prod"  # Your existing Purview account
    resource_group: "rg-governance-prod"
  
  collection:
    enabled: true
    name: "fabric-sales-collection"
    parent_collection: "root"  # Or your custom parent
  
  datasource:
    enabled: true
    scan_enabled: true  # Set to false to skip automatic scan

monitoring:
  log_analytics:
    enabled: true
    workspace_name: "log-fabric-prod"
    resource_group: "rg-monitoring-prod"

options:
  skip_existing: true  # Don't fail if resources already exist
  retry_attempts: 3
  debug: false  # Set true for verbose output
  dry_run: false  # Set true to preview without changes
```

**Configuration validation**:

```bash
# Check YAML syntax
yq eval '.azure.tenant_id' .github/config/deployment-config.yml

# Verify capacity exists
az fabric capacity show \
  --name $(yq eval '.fabric.capacity.name' .github/config/deployment-config.yml) \
  --resource-group $(yq eval '.fabric.capacity.resource_group' .github/config/deployment-config.yml)

# Verify Purview exists
az purview account show \
  --name $(yq eval '.purview.account.name' .github/config/deployment-config.yml) \
  --resource-group $(yq eval '.purview.account.resource_group' .github/config/deployment-config.yml)
```

### Step 4: Commit and Push Configuration

```bash
# Stage config file
git add .github/config/deployment-config.yml

# Commit
git commit -m "chore: configure deployment for production environment"

# Push to GitHub
git push origin feature/github-actions-automation
```

---

## 🚢 Deployment (Every Run)

### Option A: GitHub UI (Recommended for First Run)

1. **Navigate to Actions**:
   - Open your repository in GitHub
   - Click **Actions** tab
   - Select **Deploy Fabric-Purview Integration** workflow

2. **Trigger Workflow**:
   - Click **Run workflow** dropdown
   - Select branch: `feature/github-actions-automation`
   - Set inputs:
     - **Environment**: `production`
     - **Config file**: `.github/config/deployment-config.yml`
     - **Skip infrastructure**: ✅ (checked)
     - **Dry run**: ☐ (unchecked for actual deployment)
   - Click **Run workflow**

3. **Monitor Execution**:
   - Click on the running workflow
   - Watch jobs execute in sequence:
     ```
     load-config → get-capacity-info → ensure-capacity → verify-fabric-rbac
     → create-fabric-domain → create-fabric-workspace → assign-workspace-to-domain
     → create-lakehouses → verify-purview-rbac → create-purview-collection
     → register-fabric-datasource → trigger-purview-scan → deployment-summary
     ```

4. **View Logs**:
   - Click any job to see detailed logs
   - Expand steps to see PowerShell output
   - Look for ✅/❌ status indicators

5. **Check Summary**:
   - Scroll to bottom of run page
   - View **Deployment Summary** table with all resource details

### Option B: GitHub CLI

```bash
# Trigger deployment
gh workflow run deploy-fabric-integration.yml \
  --ref feature/github-actions-automation \
  --field environment=production \
  --field config_file=.github/config/deployment-config.yml \
  --field skip_infrastructure=true \
  --field dry_run=false

# Watch progress
gh run watch

# View logs after completion
gh run view --log
```

### Option C: REST API (for CI/CD integration)

```bash
# Get workflow ID
WORKFLOW_ID=$(gh api repos/:owner/:repo/actions/workflows \
  --jq '.workflows[] | select(.name=="Deploy Fabric-Purview Integration") | .id')

# Trigger run
curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/:owner/:repo/actions/workflows/$WORKFLOW_ID/dispatches" \
  -d '{
    "ref": "feature/github-actions-automation",
    "inputs": {
      "environment": "production",
      "config_file": ".github/config/deployment-config.yml",
      "skip_infrastructure": "true",
      "dry_run": "false"
    }
  }'
```

---

## 📊 Telemetry & Monitoring

### Where Logs Are Stored

GitHub Actions provides **superior visibility** compared to Bicep deployment scripts:

| Feature | GitHub Actions | Bicep Deployment Scripts |
|---------|---------------|-------------------------|
| **Log Storage** | GitHub (90-day retention) | Azure Storage file shares |
| **Access** | Anyone with repo access | Azure Portal + subscription access |
| **Search** | Full-text across all runs | Manual file searching |
| **Real-time** | Live streaming in UI | Container logs only |
| **Artifacts** | JSON/CSV downloads | Manual copy from storage |
| **Summaries** | Markdown tables | None |
| **Notifications** | Slack/Teams/Email | None |

### Accessing Telemetry

#### 1. GitHub UI (Primary Method)

**Workflow Run Overview**:
- Navigate to **Actions** → Select run → View summary
- See job status, duration, and artifacts
- Download JSON summaries

**Job Logs**:
- Click job name → Expand steps
- See PowerShell script output in real-time
- Filter by keyword (search icon in log viewer)

**Resource Outputs**:
- Scroll to **Deployment Summary** section
- View table with:
  - Resource names
  - Resource IDs
  - Status (Created/Updated/Skipped)
  - Timestamps

**Artifacts**:
- Scroll to **Artifacts** section
- Download:
  - `deployment-outputs.json` - Machine-readable results
  - `deployment-summary.md` - Human-readable report
  - `error-logs.txt` - Failure details (if any)

#### 2. GitHub CLI

```bash
# List recent runs
gh run list --workflow=deploy-fabric-integration.yml --limit 10

# View specific run
gh run view 12345678

# View logs for specific job
gh run view 12345678 --job=create-fabric-workspace --log

# Download all artifacts
gh run download 12345678

# Get run status in JSON
gh api repos/:owner/:repo/actions/runs/12345678 | jq
```

#### 3. GitHub API

```bash
# Get workflow runs
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/:owner/:repo/actions/workflows/deploy-fabric-integration.yml/runs"

# Get specific run details
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/:owner/:repo/actions/runs/12345678"

# Download logs (ZIP file)
curl -L -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/:owner/:repo/actions/runs/12345678/logs" \
  -o logs.zip
```

### Log Retention

- **Default**: 90 days
- **Enterprise**: Up to 400 days
- **Artifacts**: 90 days (configurable)
- **Tip**: Archive critical runs as artifacts in releases

### Custom Telemetry (Optional)

Enhance telemetry by sending workflow data to Azure:

#### Send Logs to Log Analytics

```yaml
# Add this job to your workflow
- name: Send Telemetry to Log Analytics
  if: always()  # Run even on failure
  shell: pwsh
  run: |
    $workspaceId = "${{ env.LOG_ANALYTICS_WORKSPACE_ID }}"
    $sharedKey = "${{ secrets.LOG_ANALYTICS_KEY }}"
    
    $json = @{
      RunId = "${{ github.run_id }}"
      RunNumber = "${{ github.run_number }}"
      Workflow = "${{ github.workflow }}"
      Status = "${{ job.status }}"
      Duration = "${{ steps.load-config.outputs.duration }}"
      FabricWorkspace = "${{ steps.create-fabric-workspace.outputs.workspace_id }}"
      Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json
    
    # Send to Log Analytics using HTTP Data Collector API
    # (Implementation details in scripts/monitoring/send_telemetry.ps1)
```

#### Tag Azure Resources

```yaml
# Add tags to created resources for traceability
- name: Tag Resources with Run ID
  shell: pwsh
  run: |
    az tag create \
      --resource-id "${{ steps.create-fabric-workspace.outputs.workspace_id }}" \
      --tags "github_run_id=${{ github.run_id }}" \
              "github_workflow=${{ github.workflow }}" \
              "deployed_by=github-actions" \
              "deployed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

#### Create Custom Dashboards

Use Azure Workbooks to visualize deployment history:

```kusto
// Query Log Analytics for GitHub Actions telemetry
GitHubActionsDeployments_CL
| where Workflow_s == "Deploy Fabric-Purview Integration"
| where TimeGenerated > ago(30d)
| summarize 
    TotalRuns = count(),
    SuccessRate = countif(Status_s == "success") * 100.0 / count(),
    AvgDuration = avg(Duration_d)
  by bin(TimeGenerated, 1d)
| render timechart
```

---

## ✅ Verification

After deployment, verify each component:

### 1. Fabric Domain

```bash
# List domains
az rest --method GET \
  --url "https://api.fabric.microsoft.com/v1/admin/domains" \
  --header "Authorization=Bearer $(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)"

# Expected output:
# {
#   "domains": [
#     {
#       "id": "<guid>",
#       "displayName": "Sales Analytics",
#       "description": "Sales team data domain"
#     }
#   ]
# }
```

### 2. Fabric Workspace

```bash
# Get workspace details
az rest --method GET \
  --url "https://api.fabric.microsoft.com/v1/workspaces/<WORKSPACE_ID>" \
  --header "Authorization=Bearer $(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)"

# Verify workspace is assigned to domain
az rest --method GET \
  --url "https://api.fabric.microsoft.com/v1/admin/workspaces/<WORKSPACE_ID>" \
  --header "Authorization=Bearer $(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)" \
  | jq '.properties.domainId'
```

### 3. Lakehouses

```bash
# List lakehouses in workspace
az rest --method GET \
  --url "https://api.fabric.microsoft.com/v1/workspaces/<WORKSPACE_ID>/lakehouses" \
  --header "Authorization=Bearer $(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)"

# Expected output:
# {
#   "value": [
#     {"displayName": "bronze_sales", "id": "<guid>"},
#     {"displayName": "silver_sales", "id": "<guid>"},
#     {"displayName": "gold_sales", "id": "<guid>"}
#   ]
# }
```

### 4. Purview Collection

```bash
# List collections
az purview collection list \
  --account-name YOUR_PURVIEW_ACCOUNT \
  --query "value[?friendlyName=='fabric-sales-collection']"

# Expected output:
# [
#   {
#     "friendlyName": "fabric-sales-collection",
#     "name": "<guid>",
#     "parentCollection": {"referenceName": "root"}
#   }
# ]
```

### 5. Purview Data Source

```bash
# List data sources
az purview data-source list \
  --account-name YOUR_PURVIEW_ACCOUNT \
  --query "value[?properties.fabricWorkspaceId=='<WORKSPACE_ID>']"

# Expected output:
# [
#   {
#     "name": "fabric-ws-sales-analytics-prod",
#     "properties": {
#       "fabricWorkspaceId": "<guid>",
#       "collection": {"referenceName": "<collection_guid>"}
#     }
#   }
# ]
```

### 6. Purview Scan (Optional)

```bash
# Get scan status
az purview scan show \
  --account-name YOUR_PURVIEW_ACCOUNT \
  --data-source-name fabric-ws-sales-analytics-prod \
  --scan-name initial-scan

# Expected output:
# {
#   "name": "initial-scan",
#   "scanResults": {
#     "status": "Succeeded",
#     "assetsDiscovered": 3,  # 3 lakehouses
#     "lastModifiedAt": "2024-01-15T10:30:00Z"
#   }
# }
```

### 7. Log Analytics Connection (Optional)

```bash
# Verify diagnostic settings
az monitor diagnostic-settings list \
  --resource <FABRIC_WORKSPACE_RESOURCE_ID> \
  --query "value[?workspaceId=='<LOG_ANALYTICS_WORKSPACE_ID>']"
```

---

## 🔧 Troubleshooting

### Common Issues

#### 1. Federated Credential Not Working

**Symptom**: `AADSTS70021: No matching federated identity record found`

**Solution**:
```bash
# Verify federated credential exists
az ad app federated-credential list --id <CLIENT_ID>

# Check subject claim matches
# Expected: "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/feature/github-actions-automation"

# Recreate if needed
az ad app federated-credential create \
  --id <CLIENT_ID> \
  --parameters '{
    "name": "github-actions-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/feature/github-actions-automation",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

#### 2. Fabric Administrator Role Not Working

**Symptom**: `Insufficient permissions to create domain/workspace`

**Solution**:
1. Verify service principal is **Fabric Administrator** (not just Contributor)
2. Check tenant settings allow service principals to use Fabric APIs
3. Wait 10-15 minutes for role propagation

```bash
# Test Fabric API access
az rest --method GET \
  --url "https://api.fabric.microsoft.com/v1/admin/capacities" \
  --header "Authorization=Bearer $(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)"
```

#### 3. Capacity Not Active

**Symptom**: `Capacity is paused or unavailable`

**Solution**:
```bash
# Check capacity state
az fabric capacity show \
  --name YOUR_CAPACITY \
  --resource-group YOUR_RG \
  --query "properties.state"

# Resume if paused
az fabric capacity resume \
  --name YOUR_CAPACITY \
  --resource-group YOUR_RG

# Wait for resume (takes 1-2 minutes)
while [[ $(az fabric capacity show --name YOUR_CAPACITY --resource-group YOUR_RG --query "properties.state" -o tsv) != "Active" ]]; do
  echo "Waiting for capacity to become active..."
  sleep 10
done
```

#### 4. Purview Data Curator Role Not Working

**Symptom**: `Insufficient permissions to create collection`

**Solution**:
```bash
# Verify role assignment
az role assignment list \
  --assignee <CLIENT_ID> \
  --scope <PURVIEW_RESOURCE_ID> \
  --query "[?roleDefinitionName=='Purview Data Curator']"

# Reassign if missing
az role assignment create \
  --assignee <CLIENT_ID> \
  --role "Purview Data Curator" \
  --scope <PURVIEW_RESOURCE_ID>

# Wait 5-10 minutes for propagation
```

#### 5. PowerShell Script Errors

**Symptom**: Script fails with "Command not found" or parameter errors

**Solution**:
```bash
# Check PowerShell version in workflow logs
# Should be 7.x (Core)

# If using old syntax, update scripts to use:
# - `pwsh` instead of `powershell`
# - `-AsPlainText -Force` for `ConvertTo-SecureString`
# - `Get-AzAccessToken` instead of `Get-AzContext`
```

#### 6. Workflow Times Out

**Symptom**: Jobs exceed 6-hour GitHub Actions limit

**Solution**:
- Enable `options.skip_existing: true` in config (skip already-created resources)
- Disable optional steps (e.g., `purview.datasource.scan_enabled: false`)
- Break into multiple workflows (Fabric-only, Purview-only)

#### 7. Rate Limiting

**Symptom**: `429 Too Many Requests` from Azure APIs

**Solution**:
```yaml
# Add retry logic (already in workflow)
options:
  retry_attempts: 5  # Increase retries
  retry_delay: 30    # Increase delay (seconds)
```

---

## 🔄 Re-Running Failed Deployments

### Option 1: Re-run Entire Workflow

```bash
# GitHub UI: Click "Re-run all jobs"

# Or via CLI
gh run rerun <RUN_ID>
```

### Option 2: Re-run Failed Jobs Only

```bash
# GitHub UI: Click "Re-run failed jobs"

# Or via CLI
gh run rerun <RUN_ID> --failed
```

### Option 3: Skip Successful Steps

Edit config to disable already-completed steps:

```yaml
fabric:
  domain:
    enabled: false  # Already created
  workspace:
    enabled: true   # Still needs to run
```

Then trigger new workflow run.

---

## 🎯 Next Steps

After successful deployment:

1. **✅ Verify Resources**: Run verification commands above
2. **📊 Set Up Dashboards**: Configure Log Analytics/Application Insights
3. **🔔 Configure Notifications**: Add Slack/Teams webhooks to workflow
4. **🔒 Review RBAC**: Assign users to Fabric workspace and Purview collection
5. **📚 Document Custom Settings**: Update this guide with environment-specific notes
6. **🚀 Create Additional Environments**: Copy config for dev/staging/prod
7. **🔄 Schedule Automated Scans**: Set up recurring Purview scans

---

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Azure Federated Identity](https://learn.microsoft.com/en-us/azure/active-directory/workload-identities/workload-identity-federation)
- [Fabric REST API](https://learn.microsoft.com/en-us/rest/api/fabric/)
- [Purview REST API](https://learn.microsoft.com/en-us/rest/api/purview/)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)

---

## 🆘 Getting Help

If you encounter issues not covered here:

1. **Check Workflow Logs**: Most errors have detailed messages
2. **Review Configuration**: Ensure all IDs and names are correct
3. **Test PowerShell Scripts Locally**: Run scripts manually to isolate issues
4. **Check Azure Portal**: Verify resources exist and are accessible
5. **Open GitHub Issue**: Provide run ID, error message, and config (sanitized)
