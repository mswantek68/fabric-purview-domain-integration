# 📊 Log Analytics Query Examples

## Overview

After workflows run, telemetry is stored in your Log Analytics workspace in the custom table:
**`GitHubActionsFabricDeployment_CL`**

Data appears **~5 minutes** after workflow completion (Log Analytics ingestion delay).

---

## 🔍 Basic Queries

### Recent Deployments

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(7d)
| project 
    TimeGenerated,
    Workflow = Workflow_s,
    Environment = Environment_s,
    Actor = Actor_s,
    Status = OverallStatus_s,
    Duration = DurationSeconds_d
| order by TimeGenerated desc
```

### Deployment Success Rate

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| summarize 
    Total = count(),
    Successes = countif(OverallStatus_s == "success"),
    Failures = countif(OverallStatus_s == "failure")
  by Environment_s
| extend SuccessRate = round(Successes * 100.0 / Total, 2)
| project Environment = Environment_s, Total, Successes, Failures, SuccessRate
```

### Average Deployment Time by Environment

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| where OverallStatus_s == "success"
| summarize 
    AvgDuration = avg(DurationSeconds_d),
    MinDuration = min(DurationSeconds_d),
    MaxDuration = max(DurationSeconds_d),
    Count = count()
  by Environment_s
| extend 
    AvgMinutes = round(AvgDuration / 60, 2),
    MinMinutes = round(MinDuration / 60, 2),
    MaxMinutes = round(MaxDuration / 60, 2)
| project Environment = Environment_s, Count, AvgMinutes, MinMinutes, MaxMinutes
```

---

## 📈 Trend Analysis

### Deployment Frequency Over Time

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(90d)
| summarize DeploymentCount = count() by bin(TimeGenerated, 1d), Environment_s
| render timechart
```

### Success Rate Trend

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| summarize 
    Total = count(),
    Successes = countif(OverallStatus_s == "success")
  by bin(TimeGenerated, 1d)
| extend SuccessRate = Successes * 100.0 / Total
| project TimeGenerated, SuccessRate
| render timechart
```

### Deployment Duration Trend

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| where OverallStatus_s == "success"
| extend DurationMinutes = DurationSeconds_d / 60
| summarize AvgDuration = avg(DurationMinutes) by bin(TimeGenerated, 1d)
| render timechart
```

---

## 🚨 Failure Analysis

### Failed Deployments with Details

```kusto
GitHubActionsFabricDeployment_CL
| where OverallStatus_s == "failure"
| where TimeGenerated > ago(7d)
| project 
    TimeGenerated,
    RunId = RunId_s,
    Environment = Environment_s,
    Actor = Actor_s,
    Branch = Branch_s,
    
    // Job statuses
    CreateWorkspaceStatus = CreateWorkspaceStatus_s,
    CreateDomainStatus = CreateDomainStatus_s,
    CreateLakehousesStatus = CreateLakehousesStatus_s,
    CreateCollectionStatus = CreateCollectionStatus_s,
    
    // Link to logs
    WorkflowUrl = WorkflowUrl_s
| order by TimeGenerated desc
```

### Most Common Failure Points

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| where OverallStatus_s == "failure"
| extend FailedJobs = pack_array(
    iff(EnsureCapacityStatus_s == "failure", "ensure-capacity", ""),
    iff(CreateDomainStatus_s == "failure", "create-domain", ""),
    iff(CreateWorkspaceStatus_s == "failure", "create-workspace", ""),
    iff(AssignToDomainStatus_s == "failure", "assign-to-domain", ""),
    iff(CreateLakehousesStatus_s == "failure", "create-lakehouses", ""),
    iff(CreateCollectionStatus_s == "failure", "create-collection", ""),
    iff(RegisterDatasourceStatus_s == "failure", "register-datasource", "")
)
| mv-expand FailedJob = FailedJobs
| where isnotempty(FailedJob)
| summarize FailureCount = count() by tostring(FailedJob)
| order by FailureCount desc
| render barchart
```

### Failure Rate by Actor

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| summarize 
    Total = count(),
    Failures = countif(OverallStatus_s == "failure")
  by Actor_s
| extend FailureRate = round(Failures * 100.0 / Total, 2)
| where Total >= 3  // Only show users with 3+ deployments
| order by FailureRate desc
```

---

## 🏗️ Resource Tracking

### Workspaces Created by Environment

```kusto
GitHubActionsFabricDeployment_CL
| where CreateWorkspaceStatus_s == "success"
| where TimeGenerated > ago(90d)
| summarize 
    WorkspaceCount = count(),
    LastCreated = max(TimeGenerated),
    Creators = make_set(Actor_s)
  by Environment_s, FabricWorkspaceName_s
| order by LastCreated desc
```

### Purview Collections Created

```kusto
GitHubActionsFabricDeployment_CL
| where CreateCollectionStatus_s == "success"
| where TimeGenerated > ago(90d)
| project 
    TimeGenerated,
    CollectionName = PurviewCollectionName_s,
    PurviewAccount = PurviewAccount_s,
    Environment = Environment_s,
    CreatedBy = Actor_s
| order by TimeGenerated desc
```

### Fabric Capacity Usage

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| summarize 
    WorkspaceCount = countif(CreateWorkspaceStatus_s == "success"),
    LastUsed = max(TimeGenerated)
  by FabricCapacityName_s
| order by WorkspaceCount desc
```

---

## 👥 User Activity

### Top Deployers

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| summarize 
    Deployments = count(),
    Successes = countif(OverallStatus_s == "success"),
    Failures = countif(OverallStatus_s == "failure")
  by Actor_s
| extend SuccessRate = round(Successes * 100.0 / Deployments, 2)
| order by Deployments desc
| take 10
```

### Deployment Activity by Hour of Day

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| extend Hour = datetime_part('hour', TimeGenerated)
| summarize DeploymentCount = count() by Hour
| order by Hour asc
| render columnchart
```

### Deployment Activity by Day of Week

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| extend DayOfWeek = dayofweek(TimeGenerated)
| extend DayName = case(
    DayOfWeek == 0, "Sunday",
    DayOfWeek == 1, "Monday",
    DayOfWeek == 2, "Tuesday",
    DayOfWeek == 3, "Wednesday",
    DayOfWeek == 4, "Thursday",
    DayOfWeek == 5, "Friday",
    DayOfWeek == 6, "Saturday",
    "Unknown"
)
| summarize DeploymentCount = count() by DayName, DayOfWeek
| order by DayOfWeek asc
| project DayName, DeploymentCount
| render columnchart
```

---

## 🔗 Cross-Service Correlation

### Link GitHub Actions to Fabric Workspace Logs

If you have Fabric workspace diagnostic logs in Log Analytics:

```kusto
// Get workflow run that created workspace
let workspaceCreation = GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(7d)
| where CreateWorkspaceStatus_s == "success"
| where FabricWorkspaceName_s == "ws-sales-analytics-prod"
| project WorkflowTime = TimeGenerated, RunId = RunId_s, Actor = Actor_s;

// Get Fabric workspace activity after creation
FabricWorkspaceActivity_CL  // Your custom table name
| where TimeGenerated > ago(7d)
| where WorkspaceName_s == "ws-sales-analytics-prod"
| join kind=leftouter (workspaceCreation) on $left.TimeGenerated >= $right.WorkflowTime
| project 
    TimeGenerated,
    Activity = ActivityType_s,
    User = UserPrincipalName_s,
    DeployedByWorkflow = RunId,
    DeployedByActor = Actor
| order by TimeGenerated desc
```

### Link to Purview Scan Results

```kusto
// Get workflow that registered datasource
let datasourceRegistration = GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(7d)
| where RegisterDatasourceStatus_s == "success"
| project 
    WorkflowTime = TimeGenerated, 
    RunId = RunId_s, 
    PurviewAccount = PurviewAccount_s,
    FabricWorkspace = FabricWorkspaceName_s;

// Get Purview scan results (if you're sending Purview logs to Log Analytics)
PurviewScanResults_CL  // Your custom table name
| where TimeGenerated > ago(7d)
| join kind=inner (datasourceRegistration) 
    on $left.PurviewAccountName_s == $right.PurviewAccount
| project 
    ScanTime = TimeGenerated,
    WorkspaceName = FabricWorkspace,
    AssetsDiscovered = AssetCount_d,
    ScanStatus = Status_s,
    RegisteredByWorkflow = RunId,
    RegisteredAt = WorkflowTime
| order by ScanTime desc
```

---

## 🎯 Alerts

### Create Alert Rule: Failed Deployments

```kusto
// Query for alert
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(5m)
| where OverallStatus_s == "failure"
| project 
    TimeGenerated,
    RunId_s,
    Environment_s,
    Actor_s,
    WorkflowUrl_s
```

**Alert Configuration**:
- **Frequency**: Every 5 minutes
- **Time range**: Last 5 minutes  
- **Threshold**: Greater than 0 failures
- **Actions**: Email/SMS/Webhook

### Create Alert Rule: Slow Deployments

```kusto
// Query for alert
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(5m)
| where DurationSeconds_d > 1800  // > 30 minutes
| project 
    TimeGenerated,
    RunId_s,
    Environment_s,
    DurationMinutes = DurationSeconds_d / 60,
    WorkflowUrl_s
```

---

## 📊 Performance Metrics

### Job-Level Performance

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| where OverallStatus_s == "success"
| summarize 
    AvgTotalTime = avg(DurationSeconds_d),
    // Could add per-job durations if we capture them
    Count = count()
  by Environment_s
| extend AvgMinutes = round(AvgTotalTime / 60, 2)
| project Environment = Environment_s, Deployments = Count, AvgMinutes
```

### Retry Analysis

If you add retry counts to telemetry:

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| where RetryCount_d > 0  // Jobs that needed retries
| summarize 
    TotalRetries = sum(RetryCount_d),
    AvgRetries = avg(RetryCount_d),
    MaxRetries = max(RetryCount_d)
  by Job = FailedJobName_s
| order by TotalRetries desc
```

---

## 🔍 Investigation Queries

### Find Specific Workflow Run

```kusto
GitHubActionsFabricDeployment_CL
| where RunId_s == "12345678"
| project-away Type, TenantId, SourceSystem, MG, ManagementGroupName, Computer
```

### Find Deployments by Commit

```kusto
GitHubActionsFabricDeployment_CL
| where Commit_s == "a1b2c3d4"
| project 
    TimeGenerated,
    Environment_s,
    Status = OverallStatus_s,
    WorkflowUrl_s
| order by TimeGenerated desc
```

### Find Deployments to Specific Resource

```kusto
GitHubActionsFabricDeployment_CL
| where FabricWorkspaceName_s == "ws-sales-analytics-prod"
| where TimeGenerated > ago(90d)
| project 
    TimeGenerated,
    Environment = Environment_s,
    Actor = Actor_s,
    Status = OverallStatus_s,
    Duration = DurationSeconds_d / 60,
    WorkflowUrl = WorkflowUrl_s
| order by TimeGenerated desc
```

---

## 💾 Export Queries

### Export to CSV

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated > ago(30d)
| project 
    Date = format_datetime(TimeGenerated, 'yyyy-MM-dd HH:mm:ss'),
    RunId = RunId_s,
    Environment = Environment_s,
    Actor = Actor_s,
    Status = OverallStatus_s,
    DurationMinutes = round(DurationSeconds_d / 60, 2),
    WorkspaceCreated = CreateWorkspaceStatus_s,
    CollectionCreated = CreateCollectionStatus_s
| order by TimeGenerated desc
```

### Export for Compliance Report

```kusto
GitHubActionsFabricDeployment_CL
| where TimeGenerated between (datetime(2024-01-01) .. datetime(2024-12-31))
| project 
    Date = format_datetime(TimeGenerated, 'yyyy-MM-dd'),
    Time = format_datetime(TimeGenerated, 'HH:mm:ss'),
    Environment = Environment_s,
    User = Actor_s,
    Action = "Deploy Fabric-Purview Integration",
    Status = OverallStatus_s,
    ResourceGroup = ResourceGroup_s,
    FabricWorkspace = FabricWorkspaceName_s,
    PurviewAccount = PurviewAccount_s,
    AuditTrail = WorkflowUrl_s
| order by Date desc, Time desc
```

---

## 🎨 Visualization Tips

1. **Pin to Dashboard**: Click "Pin to dashboard" in Log Analytics to add charts to Azure Dashboard
2. **Create Workbook**: Use queries in Azure Monitor Workbooks for interactive reports
3. **Export to Power BI**: Use Log Analytics connector in Power BI Desktop
4. **API Access**: Query via REST API for custom dashboards

---

## 📝 Query Best Practices

1. **Always use time ranges**: `where TimeGenerated > ago(7d)` to limit data scanned
2. **Filter early**: Put `where` clauses before `summarize` or `join`
3. **Use `project`**: Only select columns you need
4. **Index fields**: Fields ending in `_s` (string), `_d` (double), `_b` (bool)
5. **Test incrementally**: Build complex queries step-by-step

---

## 🔗 Additional Resources

- [Kusto Query Language (KQL) Reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- [Log Analytics Query Examples](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/example-queries)
- [Create Alerts from Queries](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-log-alert-rule)
- [Export to Power BI](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-powerbi)
