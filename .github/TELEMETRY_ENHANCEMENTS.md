# 📊 Telemetry & Monitoring Enhancements

## Overview

This guide shows how to enhance GitHub Actions telemetry by integrating with Azure monitoring services. While GitHub Actions provides excellent built-in logging, these enhancements add:

- **Long-term storage** (beyond 90-day retention)
- **Centralized dashboards** with Azure Workbooks
- **Alerting** via Azure Monitor
- **Resource traceability** through tags
- **Cross-platform correlation** (GitHub + Azure)

---

## 🎯 Enhancement Options

| Enhancement | Benefit | Complexity | Cost |
|-------------|---------|------------|------|
| **Resource Tagging** | Link Azure resources to workflow runs | Low | Free |
| **Log Analytics Integration** | Centralized logging & search | Medium | ~$2-5/GB |
| **Application Insights** | Performance metrics & alerting | Medium | ~$2-5/GB |
| **Workbook Dashboards** | Visual deployment history | Low | Free |
| **Action Notifications** | Slack/Teams alerts | Low | Free |

---

## 1️⃣ Resource Tagging (Recommended)

Tag Azure resources with GitHub workflow metadata for easy traceability.

### Implementation

Add this step to each resource creation job in your workflow:

```yaml
# Example: After create-fabric-workspace job
- name: Tag Fabric Workspace
  if: success()
  shell: pwsh
  run: |
    # Get workspace resource ID from previous step
    $workspaceId = "${{ steps.create-workspace.outputs.workspace_id }}"
    
    # Create tags
    az tag create \
      --resource-id "$workspaceId" \
      --tags `
        "deployed_by=github-actions" `
        "workflow=${{ github.workflow }}" `
        "run_id=${{ github.run_id }}" `
        "run_number=${{ github.run_number }}" `
        "branch=${{ github.ref_name }}" `
        "commit=${{ github.sha }}" `
        "actor=${{ github.actor }}" `
        "deployed_at=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')" `
        "environment=${{ inputs.environment }}"
```

### Usage

Query resources by deployment metadata:

```bash
# Find all resources deployed by specific workflow run
az resource list \
  --tag "run_id=12345678" \
  --query "[].{Name:name, Type:type, RG:resourceGroup}" \
  --output table

# Find all resources deployed from GitHub Actions
az resource list \
  --tag "deployed_by=github-actions" \
  --query "[].{Name:name, Deployed:tags.deployed_at, Run:tags.run_id}" \
  --output table

# Find resources deployed by specific user
az resource list \
  --tag "actor=mswantek68" \
  --query "[].name" \
  --output tsv
```

### Automated Tag Cleanup

Remove tags from deleted workflow runs:

```yaml
# Add this as a scheduled workflow
name: Cleanup Orphaned Tags

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday at 2 AM

jobs:
  cleanup-tags:
    runs-on: ubuntu-latest
    steps:
      - name: Remove Tags for Deleted Runs
        shell: pwsh
        run: |
          # Get all resources with run_id tags
          $resources = az resource list --tag "run_id" | ConvertFrom-Json
          
          foreach ($resource in $resources) {
            $runId = $resource.tags.run_id
            
            # Check if workflow run still exists
            $runExists = gh api "repos/${{ github.repository }}/actions/runs/$runId" 2>/dev/null
            
            if (-not $runExists) {
              Write-Host "Removing tags from $($resource.name) (run $runId deleted)"
              az tag update \
                --resource-id $resource.id \
                --operation Delete \
                --tags "run_id" "workflow" "run_number" "deployed_by"
            }
          }
```

---

## 2️⃣ Log Analytics Integration

Send workflow telemetry to Azure Log Analytics for long-term storage and advanced queries.

### Setup

#### Step 1: Create Log Analytics Workspace

```bash
# Create workspace (if not exists)
az monitor log-analytics workspace create \
  --resource-group rg-monitoring-prod \
  --workspace-name log-github-actions \
  --location eastus \
  --retention-time 90  # Days (30-730 supported)

# Get workspace ID and key
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-monitoring-prod \
  --workspace-name log-github-actions \
  --query customerId -o tsv)

WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group rg-monitoring-prod \
  --workspace-name log-github-actions \
  --query primarySharedKey -o tsv)
```

#### Step 2: Add Secrets to GitHub

```bash
gh secret set LOG_ANALYTICS_WORKSPACE_ID --body "$WORKSPACE_ID"
gh secret set LOG_ANALYTICS_WORKSPACE_KEY --body "$WORKSPACE_KEY"
```

#### Step 3: Create PowerShell Helper Script

Create `scripts/monitoring/Send-WorkflowTelemetry.ps1`:

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,
    
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceKey,
    
    [Parameter(Mandatory = $true)]
    [hashtable]$TelemetryData
)

# Build JSON body
$json = $TelemetryData | ConvertTo-Json -Depth 10

# Create authorization signature
$method = "POST"
$contentType = "application/json"
$resource = "/api/logs"
$rfc1123date = [DateTime]::UtcNow.ToString("r")
$contentLength = $json.Length

$xHeaders = "x-ms-date:$rfc1123date"
$stringToHash = "$method`n$contentLength`n$contentType`n$xHeaders`n$resource"
$bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
$keyBytes = [Convert]::FromBase64String($WorkspaceKey)
$sha256 = New-Object System.Security.Cryptography.HMACSHA256
$sha256.Key = $keyBytes
$hash = $sha256.ComputeHash($bytesToHash)
$signature = [Convert]::ToBase64String($hash)
$authorization = "SharedKey ${WorkspaceId}:${signature}"

# Send to Log Analytics
$uri = "https://$WorkspaceId.ods.opinsights.azure.com$resource?api-version=2016-04-01"
$headers = @{
    "Authorization"        = $authorization
    "Log-Type"            = "GitHubActionsDeployment"  # Custom table name
    "x-ms-date"           = $rfc1123date
    "time-generated-field" = "Timestamp"
}

try {
    $response = Invoke-RestMethod -Uri $uri -Method POST -ContentType $contentType -Headers $headers -Body $json
    Write-Host "✅ Telemetry sent to Log Analytics"
} catch {
    Write-Warning "Failed to send telemetry: $_"
}
```

#### Step 4: Add Telemetry Job to Workflow

```yaml
# Add this job at the end of your workflow
send-telemetry:
  name: Send Telemetry to Log Analytics
  runs-on: ubuntu-latest
  if: always()  # Run even on failure
  needs: 
    - load-config
    - ensure-capacity
    - create-fabric-domain
    - create-fabric-workspace
    - create-lakehouses
    - create-purview-collection
    - deployment-summary
  
  steps:
    - name: Checkout Repository
      uses: actions/checkout@v4
    
    - name: Azure Login
      uses: azure/login@v2
      with:
        client-id: ${{ needs.load-config.outputs.azure_client_id }}
        tenant-id: ${{ needs.load-config.outputs.azure_tenant_id }}
        subscription-id: ${{ needs.load-config.outputs.azure_subscription_id }}
    
    - name: Send Workflow Telemetry
      shell: pwsh
      run: |
        $telemetry = @{
          Timestamp = (Get-Date).ToUniversalTime().ToString("o")
          RunId = "${{ github.run_id }}"
          RunNumber = "${{ github.run_number }}"
          RunAttempt = "${{ github.run_attempt }}"
          Workflow = "${{ github.workflow }}"
          Repository = "${{ github.repository }}"
          Branch = "${{ github.ref_name }}"
          Commit = "${{ github.sha }}"
          Actor = "${{ github.actor }}"
          Event = "${{ github.event_name }}"
          Environment = "${{ inputs.environment }}"
          
          # Job statuses
          EnsureCapacityStatus = "${{ needs.ensure-capacity.result }}"
          CreateDomainStatus = "${{ needs.create-fabric-domain.result }}"
          CreateWorkspaceStatus = "${{ needs.create-fabric-workspace.result }}"
          CreateLakehousesStatus = "${{ needs.create-lakehouses.result }}"
          CreateCollectionStatus = "${{ needs.create-purview-collection.result }}"
          
          # Resource IDs (from outputs)
          FabricDomainId = "${{ needs.create-fabric-domain.outputs.domain_id }}"
          FabricWorkspaceId = "${{ needs.create-fabric-workspace.outputs.workspace_id }}"
          PurviewCollectionName = "${{ needs.create-purview-collection.outputs.collection_name }}"
          
          # Timing
          StartTime = "${{ github.event.repository.created_at }}"
          Duration = "${{ github.event.workflow_run.updated_at - github.event.workflow_run.created_at }}"
          
          # Configuration
          ConfigFile = "${{ inputs.config_file }}"
          SkipInfrastructure = "${{ inputs.skip_infrastructure }}"
          DryRun = "${{ inputs.dry_run }}"
        }
        
        ./scripts/monitoring/Send-WorkflowTelemetry.ps1 `
          -WorkspaceId "${{ secrets.LOG_ANALYTICS_WORKSPACE_ID }}" `
          -WorkspaceKey "${{ secrets.LOG_ANALYTICS_WORKSPACE_KEY }}" `
          -TelemetryData $telemetry
```

### Usage

Query telemetry in Log Analytics:

```kusto
// Recent deployments
GitHubActionsDeployment_CL
| where TimeGenerated > ago(7d)
| project 
    TimeGenerated,
    Workflow_s,
    Environment_s,
    Actor_s,
    CreateWorkspaceStatus_s,
    CreateDomainStatus_s,
    Duration_s
| order by TimeGenerated desc

// Success rate by environment
GitHubActionsDeployment_CL
| where TimeGenerated > ago(30d)
| summarize 
    TotalRuns = count(),
    Successes = countif(CreateWorkspaceStatus_s == "success"),
    Failures = countif(CreateWorkspaceStatus_s == "failure")
  by Environment_s
| extend SuccessRate = Successes * 100.0 / TotalRuns
| render columnchart

// Deployment trend over time
GitHubActionsDeployment_CL
| where TimeGenerated > ago(90d)
| summarize RunCount = count() by bin(TimeGenerated, 1d), Environment_s
| render timechart

// Failed deployments with details
GitHubActionsDeployment_CL
| where CreateWorkspaceStatus_s == "failure" or CreateDomainStatus_s == "failure"
| project 
    TimeGenerated,
    RunId_s,
    Actor_s,
    Environment_s,
    FailedJobs = pack_array(
        iff(EnsureCapacityStatus_s == "failure", "ensure-capacity", ""),
        iff(CreateDomainStatus_s == "failure", "create-domain", ""),
        iff(CreateWorkspaceStatus_s == "failure", "create-workspace", "")
    )
| order by TimeGenerated desc

// Resource creation tracking
GitHubActionsDeployment_CL
| where isnotempty(FabricWorkspaceId_s)
| project 
    TimeGenerated,
    WorkspaceId = FabricWorkspaceId_s,
    DomainId = FabricDomainId_s,
    CollectionName = PurviewCollectionName_s,
    DeployedBy = Actor_s,
    RunId = RunId_s
| order by TimeGenerated desc
```

---

## 3️⃣ Application Insights Integration

Send performance metrics and custom events to Application Insights.

### Setup

#### Step 1: Create Application Insights

```bash
# Create Application Insights (links to Log Analytics workspace)
az monitor app-insights component create \
  --app github-actions-telemetry \
  --location eastus \
  --resource-group rg-monitoring-prod \
  --workspace "/subscriptions/<SUB_ID>/resourceGroups/rg-monitoring-prod/providers/Microsoft.OperationalInsights/workspaces/log-github-actions"

# Get instrumentation key
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
  --app github-actions-telemetry \
  --resource-group rg-monitoring-prod \
  --query instrumentationKey -o tsv)

# Add to GitHub secrets
gh secret set APPINSIGHTS_INSTRUMENTATION_KEY --body "$INSTRUMENTATION_KEY"
```

#### Step 2: Add Telemetry Script

Create `scripts/monitoring/Send-AppInsightsTelemetry.ps1`:

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$InstrumentationKey,
    
    [Parameter(Mandatory = $true)]
    [string]$EventName,
    
    [Parameter(Mandatory = $false)]
    [hashtable]$Properties = @{},
    
    [Parameter(Mandatory = $false)]
    [hashtable]$Metrics = @{}
)

$endpoint = "https://dc.services.visualstudio.com/v2/track"

$envelope = @{
    name = "Microsoft.ApplicationInsights.$InstrumentationKey.Event"
    time = (Get-Date).ToUniversalTime().ToString("o")
    iKey = $InstrumentationKey
    tags = @{
        "ai.cloud.role" = "github-actions"
        "ai.cloud.roleInstance" = $env:GITHUB_RUN_ID
    }
    data = @{
        baseType = "EventData"
        baseData = @{
            ver = 2
            name = $EventName
            properties = $Properties
            measurements = $Metrics
        }
    }
}

$json = $envelope | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri $endpoint -Method POST -ContentType "application/json" -Body $json
    Write-Host "✅ Sent '$EventName' event to Application Insights"
} catch {
    Write-Warning "Failed to send event: $_"
}
```

#### Step 3: Add Events to Workflow

```yaml
# After each major job, send custom event
- name: Send Create Workspace Event
  if: success()
  shell: pwsh
  run: |
    ./scripts/monitoring/Send-AppInsightsTelemetry.ps1 `
      -InstrumentationKey "${{ secrets.APPINSIGHTS_INSTRUMENTATION_KEY }}" `
      -EventName "FabricWorkspaceCreated" `
      -Properties @{
        WorkspaceId = "${{ steps.create-workspace.outputs.workspace_id }}"
        WorkspaceName = "${{ steps.create-workspace.outputs.workspace_name }}"
        DomainId = "${{ needs.create-fabric-domain.outputs.domain_id }}"
        Environment = "${{ inputs.environment }}"
        Actor = "${{ github.actor }}"
        RunId = "${{ github.run_id }}"
      } `
      -Metrics @{
        Duration = ${{ steps.create-workspace.outputs.duration_seconds }}
        RetryAttempts = ${{ steps.create-workspace.outputs.retry_count }}
      }
```

### Usage

Query events in Application Insights:

```kusto
// Recent workspace creations
customEvents
| where name == "FabricWorkspaceCreated"
| where timestamp > ago(30d)
| project 
    timestamp,
    WorkspaceName = tostring(customDimensions.WorkspaceName),
    Environment = tostring(customDimensions.Environment),
    Actor = tostring(customDimensions.Actor),
    Duration = todouble(customMeasurements.Duration)
| order by timestamp desc

// Average creation time by environment
customEvents
| where name == "FabricWorkspaceCreated"
| where timestamp > ago(30d)
| summarize 
    AvgDuration = avg(todouble(customMeasurements.Duration)),
    Count = count()
  by Environment = tostring(customDimensions.Environment)
| render barchart

// Failed operations (with dependencies)
dependencies
| where success == false
| where timestamp > ago(7d)
| project 
    timestamp,
    name,
    target,
    resultCode,
    duration,
    operation_Id
| order by timestamp desc
```

---

## 4️⃣ Azure Workbook Dashboards

Create visual dashboards for deployment history.

### Setup

#### Step 1: Create Workbook

```bash
# Create resource group if needed
az group create --name rg-monitoring-prod --location eastus

# Create workbook (via Azure Portal - no CLI support yet)
# Navigate to: Azure Portal > Monitor > Workbooks > New
```

#### Step 2: Add Visualization Queries

**Deployment Success Rate**:
```kusto
GitHubActionsDeployment_CL
| where TimeGenerated > ago(30d)
| summarize 
    Total = count(),
    Success = countif(CreateWorkspaceStatus_s == "success"),
    Failed = countif(CreateWorkspaceStatus_s == "failure")
| extend SuccessRate = Success * 100.0 / Total
| project SuccessRate, Total, Success, Failed
```

**Deployment Timeline**:
```kusto
GitHubActionsDeployment_CL
| where TimeGenerated > ago(90d)
| extend Status = case(
    CreateWorkspaceStatus_s == "success", "Success",
    CreateWorkspaceStatus_s == "failure", "Failed",
    "Unknown"
)
| summarize Count = count() by bin(TimeGenerated, 1d), Status
| render timechart
```

**Resource Inventory**:
```kusto
GitHubActionsDeployment_CL
| where isnotempty(FabricWorkspaceId_s)
| summarize 
    arg_max(TimeGenerated, *) by FabricWorkspaceId_s
| project 
    Workspace = FabricWorkspaceId_s,
    Domain = FabricDomainId_s,
    Collection = PurviewCollectionName_s,
    LastDeployed = TimeGenerated,
    DeployedBy = Actor_s,
    Environment = Environment_s
```

**Top Deployers**:
```kusto
GitHubActionsDeployment_CL
| where TimeGenerated > ago(30d)
| summarize 
    Deployments = count(),
    Successes = countif(CreateWorkspaceStatus_s == "success")
  by Actor_s
| extend SuccessRate = Successes * 100.0 / Deployments
| top 10 by Deployments desc
```

### Export and Share

```bash
# Export workbook template
az monitor workbook show \
  --resource-group rg-monitoring-prod \
  --name github-actions-dashboard \
  --query serializedData -o json > workbook-template.json

# Import to another environment
az monitor workbook create \
  --resource-group rg-monitoring-staging \
  --name github-actions-dashboard \
  --serialized-data @workbook-template.json \
  --location eastus
```

---

## 5️⃣ Microsoft Teams Notifications

Send workflow status to Microsoft Teams (recommended for Azure/Fabric projects).

### Teams Integration

#### Step 1: Create Incoming Webhook

1. Open Teams channel
2. Click **⋯** → **Connectors** → **Incoming Webhook**
3. Configure and copy webhook URL

```bash
# Add to GitHub secrets (replace with your actual Teams webhook URL)
gh secret set TEAMS_WEBHOOK_URL --body "https://contoso.example.com/your-teams-webhook"
```

#### Step 2: Add Notification Step

```yaml
- name: Send Teams Notification
  shell: pwsh
  run: |
    $status = "${{ job.status }}" -eq "success" ? "✅ Success" : "❌ Failed"
    $color = "${{ job.status }}" -eq "success" ? "00FF00" : "FF0000"
    
    $payload = @{
      "@type" = "MessageCard"
      "@context" = "https://schema.org/extensions"
      "summary" = "Deployment $status"
      "themeColor" = $color
      "title" = "Fabric-Purview Deployment"
      "sections" = @(
        @{
          "activityTitle" = "Workflow: ${{ github.workflow }}"
          "facts" = @(
            @{"name" = "Environment"; "value" = "${{ inputs.environment }}"},
            @{"name" = "Triggered by"; "value" = "${{ github.actor }}"},
            @{"name" = "Branch"; "value" = "${{ github.ref_name }}"},
            @{"name" = "Status"; "value" = $status}
          )
        },
        @{
          "title" = "Results"
          "text" = @"
    • Domain: ${{ needs.create-fabric-domain.result }}
    • Workspace: ${{ needs.create-fabric-workspace.result }}
    • Lakehouses: ${{ needs.create-lakehouses.result }}
    • Collection: ${{ needs.create-purview-collection.result }}
    "@
        }
      )
      "potentialAction" = @(
        @{
          "@type" = "OpenUri"
          "name" = "View Logs"
          "targets" = @(
            @{"os" = "default"; "uri" = "https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}"}
          )
        }
      )
    } | ConvertTo-Json -Depth 10
    
    Invoke-RestMethod -Method POST -Uri "${{ secrets.TEAMS_WEBHOOK_URL }}" -Body $payload -ContentType "application/json"
```

---

## 6️⃣ Custom Retention Policies

Extend log retention beyond GitHub's default.

### GitHub Actions Logs

```yaml
# Add this to repository settings via API
# (No UI for custom retention yet)
gh api --method PATCH \
  /repos/:owner/:repo/actions/cache/usage-policy \
  -f days_to_keep_artifacts=180 \
  -f days_to_keep_logs=180
```

### Log Analytics Retention

```bash
# Set custom retention (30-730 days)
az monitor log-analytics workspace update \
  --resource-group rg-monitoring-prod \
  --workspace-name log-github-actions \
  --retention-time 365  # 1 year

# Or use tiered retention (cheaper)
az monitor log-analytics workspace table update \
  --resource-group rg-monitoring-prod \
  --workspace-name log-github-actions \
  --name GitHubActionsDeployment_CL \
  --retention-time 730 \  # 2 years
  --total-retention-time 2555  # 7 years (archive)
```

### Export to Blob Storage

For long-term archival:

```bash
# Create storage account
az storage account create \
  --name stgithubactionslogs \
  --resource-group rg-monitoring-prod \
  --sku Standard_LRS

# Configure Log Analytics export
az monitor log-analytics workspace data-export create \
  --resource-group rg-monitoring-prod \
  --workspace-name log-github-actions \
  --name export-to-storage \
  --tables GitHubActionsDeployment_CL \
  --destination "/subscriptions/<SUB_ID>/resourceGroups/rg-monitoring-prod/providers/Microsoft.Storage/storageAccounts/stgithubactionslogs"
```

---

## 📊 Comparison Matrix

| Feature | GitHub Logs | Log Analytics | App Insights | Workbooks | Slack/Teams |
|---------|------------|---------------|--------------|-----------|-------------|
| **Real-time** | ✅ | ⚠️ 1-2 min delay | ⚠️ 1-2 min delay | ⚠️ Manual refresh | ✅ |
| **Retention** | 90 days | 30-730 days | 30-730 days | N/A (queries data) | Archive manually |
| **Cost** | Free | ~$2-5/GB | ~$2-5/GB | Free | Free |
| **Querying** | Limited | ✅ KQL | ✅ KQL | ✅ KQL | N/A |
| **Alerting** | Limited | ✅ | ✅ | ⚠️ Via queries | ✅ |
| **Dashboards** | ❌ | ⚠️ Basic | ⚠️ Basic | ✅ | ❌ |
| **API Access** | ✅ | ✅ | ✅ | ⚠️ Limited | ⚠️ Webhooks |
| **Setup Complexity** | None | Medium | Medium | Low | Low |

---

## 🎯 Recommended Configuration

For most use cases, combine:

1. **✅ Resource Tagging** (always) - Free traceability
2. **✅ GitHub Logs** (built-in) - 90-day retention
3. **✅ Slack/Teams** (notifications) - Real-time alerts
4. **⚠️ Log Analytics** (optional) - Long-term storage for compliance
5. **⚠️ Workbooks** (optional) - Executive dashboards

Skip Application Insights unless you need advanced performance monitoring.

---

## 🚀 Getting Started

### Quick Start (5 minutes)

1. Add resource tagging to workflow (copy example from section 1)
2. Set up Slack webhook (section 5)
3. Done! You now have traceability + notifications

### Full Setup (30 minutes)

1. Complete Quick Start
2. Create Log Analytics workspace (section 2)
3. Add telemetry job to workflow
4. Create Workbook dashboard (section 4)
5. Configure retention policies (section 6)

---

## 📚 Additional Resources

- [GitHub Actions Logs API](https://docs.github.com/en/rest/actions/workflow-runs#download-workflow-run-logs)
- [Log Analytics HTTP Data Collector API](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-collector-api)
- [Application Insights Custom Events](https://learn.microsoft.com/en-us/azure/azure-monitor/app/api-custom-events-metrics)
- [Azure Workbooks](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Slack Incoming Webhooks](https://api.slack.com/messaging/webhooks)
- [Teams Incoming Webhooks](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook)
