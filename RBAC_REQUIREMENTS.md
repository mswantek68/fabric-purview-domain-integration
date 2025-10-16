# Managed Identity RBAC Requirements

This document outlines the Azure RBAC roles that must be assigned to the managed identity created by the deployment for proper operation of all deployment scripts.

## Managed Identity Information

The managed identity is created with the following naming pattern:
- **Name**: `id-fabric-automation-{uniqueString}`
- **Type**: User-Assigned Managed Identity
- **Location**: Same as resource group

### How to Find Your Managed Identity

After deployment:
1. Go to Azure Portal → Resource Groups → Your Resource Group
2. Look for resource type "Managed Identity"
3. Note the **Principal ID** (Object ID) - you'll need this for role assignments

Or use Azure CLI:
```bash
# Get managed identity details
az identity list --resource-group <your-rg> --query "[?contains(name, 'fabric-automation')].{name:name, principalId:principalId, clientId:clientId}" -o table
```

## Required Role Assignments

### 1. Storage Account Roles (✅ Auto-Assigned)

These roles are **automatically assigned** by the Bicep deployment:

| Role | Scope | Purpose | Status |
|------|-------|---------|--------|
| Storage File Data Privileged Contributor | Deployment Storage Account | Allows deployment scripts to write files to storage | ✅ Auto-assigned |

**Role ID**: `69566ab7-960f-475b-8e7c-b3118f30c6bd`

---

### 2. Microsoft Fabric Roles (⚠️ Manual Assignment Required)

These roles must be assigned **manually** after deployment:

| Role | Scope | Purpose | Assignment Method |
|------|-------|---------|-------------------|
| Fabric Administrator | Subscription or Fabric Capacity | Create domains, workspaces, lakehouses | Azure Portal / Fabric Admin Portal |
| Workspace Admin | Specific Workspace (after creation) | Manage workspace settings and content | Fabric Portal |

#### How to Assign Fabric Roles

**Option A: Using Fabric Admin Portal** (Recommended)
1. Go to [Microsoft Fabric Admin Portal](https://app.fabric.microsoft.com/admin)
2. Navigate to **Capacity settings** → Select your capacity
3. Under **Permissions**, add the managed identity's **Object ID**
4. Grant **Admin** permissions

**Option B: Using PowerShell with Fabric REST API**
```powershell
# Get access token
$token = (Get-AzAccessToken -ResourceUrl "https://api.fabric.microsoft.com").Token

# Get managed identity principal ID
$principalId = "<your-managed-identity-principal-id>"

# Assign Fabric Administrator role (example - API may vary)
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Note: Exact API endpoints depend on your Fabric configuration
# Consult Microsoft Fabric documentation for current API endpoints
```

**Option C: Manual Assignment via Azure RBAC** (if available)
```bash
# Note: Fabric-specific roles may not be available in Azure RBAC
# Check with your Fabric administrator for the correct role definition ID

az role assignment create \
  --assignee <managed-identity-principal-id> \
  --role "Fabric Administrator" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.Fabric/capacities/<capacity-name>
```

---

### 3. Microsoft Purview Roles (⚠️ Manual Assignment Required)

These roles must be assigned **manually** in Purview:

| Role | Scope | Purpose | Assignment Method |
|------|-------|---------|-------------------|
| Collection Admin | Purview Collection | Create collections, manage metadata | Purview Governance Portal |
| Data Source Administrator | Purview Account | Register data sources | Purview Governance Portal |
| Data Curator | Purview Collection | Edit metadata, manage classifications | Purview Governance Portal |

#### How to Assign Purview Roles

**Using Purview Governance Portal** (Recommended)
1. Go to [Microsoft Purview Governance Portal](https://web.purview.azure.com/)
2. Select your Purview account: `swantekPurview`
3. Navigate to **Data Map** → **Collections**
4. Select the root collection or specific collection
5. Go to **Role assignments** tab
6. Click **Add** → Search for your managed identity by **Object ID**
7. Assign the following roles:
   - ✅ **Collection Admin** - For creating sub-collections
   - ✅ **Data Source Administrator** - For registering Fabric as a data source
   - ✅ **Data Curator** - For managing metadata and classifications

**Using Azure CLI** (if Purview CLI is available)
```bash
# Note: Purview role assignments typically require the Purview Governance Portal
# Azure CLI may have limited support for Purview role assignments

# Get managed identity Object ID
PRINCIPAL_ID=$(az identity show --name id-fabric-automation-{uniqueString} --resource-group <rg-name> --query principalId -o tsv)

echo "Assign the following roles in Purview Portal for Principal ID: $PRINCIPAL_ID"
echo "- Collection Admin"
echo "- Data Source Administrator"  
echo "- Data Curator"
```

---

### 4. Azure Monitor / Log Analytics Roles (⚠️ Optional)

Only required if using Log Analytics integration (`enableLogAnalytics: true`):

| Role | Scope | Purpose | Assignment Method |
|------|-------|---------|-------------------|
| Log Analytics Contributor | Log Analytics Workspace | Connect Fabric workspace to Log Analytics | Azure RBAC |

```bash
az role assignment create \
  --assignee <managed-identity-principal-id> \
  --role "Log Analytics Contributor" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>
```

---

### 5. Azure AI Services Roles (⚠️ Optional)

Only required if using OneLake Index features with AI Search:

| Role | Scope | Purpose | Assignment Method |
|------|-------|---------|-------------------|
| Search Service Contributor | AI Search Service | Create indexes, indexers, skillsets | Azure RBAC |
| Cognitive Services Contributor | AI Services Account | Access AI services for enrichment | Azure RBAC |

```bash
# AI Search
az role assignment create \
  --assignee <managed-identity-principal-id> \
  --role "Search Service Contributor" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.Search/searchServices/<search-service-name>

# AI Services (if using skillsets)
az role assignment create \
  --assignee <managed-identity-principal-id> \
  --role "Cognitive Services Contributor" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.CognitiveServices/accounts/<ai-service-name>
```

---

## Post-Deployment Checklist

After running `azd provision`, complete these steps:

### Step 1: Get Managed Identity Details
```bash
az identity list --resource-group rg-dev101625 --query "[?contains(name, 'fabric-automation')].{Name:name, PrincipalId:principalId, ClientId:clientId}" -o table
```

### Step 2: Verify Storage RBAC (Should be automatic)
```bash
# Check storage account role assignments
az role assignment list --assignee <principal-id> --scope <storage-account-resource-id> -o table
```

Expected: Should see "Storage File Data Privileged Contributor" role

### Step 3: Assign Fabric Roles
- [ ] Navigate to Fabric Admin Portal
- [ ] Add managed identity to Fabric Capacity as Administrator
- [ ] Verify identity appears in capacity permissions

### Step 4: Assign Purview Roles
- [ ] Navigate to Purview Governance Portal
- [ ] Open your Purview account: `swantekPurview`
- [ ] Assign Collection Admin role
- [ ] Assign Data Source Administrator role
- [ ] Assign Data Curator role

### Step 5: Test Deployment Scripts
```bash
# Re-run deployment to execute scripts with new permissions
azd provision
```

### Step 6: Verify Role Assignments Work
```bash
# Check if deployment scripts execute successfully
# Look for successful completion of:
# - Fabric domain creation
# - Fabric workspace creation
# - Lakehouse creation
# - Purview collection creation
# - Purview datasource registration
```

---

## Troubleshooting

### Issue: "Insufficient permissions" error during Fabric operations

**Solution**: Verify Fabric Administrator role is assigned to the managed identity in the Fabric Admin Portal.

```powershell
# Test Fabric API access with managed identity
$token = (Get-AzAccessToken -ResourceUrl "https://api.fabric.microsoft.com").Token
# Use token to test API calls
```

### Issue: "Access denied" during Purview operations

**Solution**: Ensure all three Purview roles are assigned (Collection Admin, Data Source Administrator, Data Curator).

```bash
# Verify Purview role assignments (manual check in portal)
# Go to: Purview Portal → Collections → Role assignments
```

### Issue: Storage account access denied

**Solution**: Verify the AVM module deployed the Storage File Data Privileged Contributor role:

```bash
# Check if role assignment exists
az role assignment list \
  --assignee <principal-id> \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage-name> \
  --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
```

### Issue: "AllowSharedKeyAccess is false" error (should NOT occur anymore)

**Status**: ✅ FIXED - We now use managed identity authentication, no shared keys required.

---

## Security Benefits of Managed Identity Approach

✅ **No Storage Account Keys**: Eliminates risk of key exposure in code or parameters
✅ **RBAC-Based Access**: Granular, auditable permissions using Azure RBAC
✅ **WAF Compliant**: Follows Well-Architected Framework security best practices
✅ **Automatic Rotation**: Managed identity credentials are automatically rotated by Azure
✅ **Least Privilege**: Each script only has permissions it needs via identity
✅ **Audit Trail**: All actions logged with managed identity principal ID

---

## References

- [Azure Managed Identity Documentation](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)
- [Deployment Scripts with Managed Identity](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-vnet)
- [Microsoft Fabric Admin Portal](https://app.fabric.microsoft.com/admin)
- [Microsoft Purview Governance Portal](https://web.purview.azure.com/)
- [Storage File Data Privileged Contributor Role](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-privileged-contributor)
