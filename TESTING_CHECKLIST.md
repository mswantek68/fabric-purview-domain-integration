# Pre-Deployment Testing Checklist

## ✅ Code Review Complete

### What We Built (Summary)
- ✅ User-assigned managed identity module
- ✅ Secure AVM storage account (allowSharedKeyAccess: false)
- ✅ Removed storage account keys from all 14 deployment scripts
- ✅ Automated Fabric RBAC assignment via REST API
- ✅ Automated Purview RBAC assignment via REST API
- ✅ Updated orchestration to use all secure modules
- ✅ Comprehensive documentation (RBAC_REQUIREMENTS.md)

### Commits
```
c1b1b5c - feat: migrate to managed identity authentication (WAF-compliant)
2056780 - docs: add comprehensive RBAC requirements for managed identity
98bdd61 - feat: add automated RBAC assignment modules for Fabric and Purview
```

### Files Changed
```
20 files changed, 882 insertions(+), 159 deletions(-)

NEW:
+ infra/modules/shared/managedIdentity.bicep
+ infra/modules/shared/assignFabricRoles.bicep
+ infra/modules/shared/assignPurviewRoles.bicep
+ RBAC_REQUIREMENTS.md
+ TESTING_CHECKLIST.md (this file)

MODIFIED:
• infra/main-with-modules.bicep - Orchestration with automated RBAC
• infra/modules/shared/deploymentScriptStorage.bicep - AVM with RBAC
• All 14 deployment script modules - Removed storageAccountKey
```

---

## 🚀 Pre-Flight Checks

### Environment Status
- [x] Old storage account deleted (stdeployxm2dtcohpl62g)
- [x] Git branch: feature/bicep-deployment-modules
- [x] All changes committed
- [x] No Bicep compilation errors

### Parameters Ready (main-with-modules.bicepparam)
- [x] fabricCapacityName: swancapacitytest1016
- [x] fabricWorkspaceName: workspacetest1016
- [x] purviewAccountName: swantekPurview
- [x] capacityAdminMembers: ['admin@MngEnv282784.onmicrosoft.com']
- [x] location: eastus2

### Azure Environment
- [x] Subscription: ME-MngEnv282784-mikeswantek-dev (48ab3756...)
- [x] Resource Group: rg-dev101625
- [x] Region: eastus2

---

## 🧪 Testing Plan

### Phase 1: Infrastructure Deployment (Expected: ~5-10 minutes)
```bash
azd provision
```

**Expected Results:**
1. ✅ Fabric Capacity created
2. ✅ Managed Identity created (id-fabric-automation-{unique})
3. ✅ Storage Account created with allowSharedKeyAccess=false
4. ✅ RBAC: Storage File Data Privileged Contributor assigned automatically

### Phase 2: Automated RBAC Assignment (Expected: ~2-3 minutes)
**Expected Results:**
5. ✅ Fabric Administrator role assigned via API
   - If fails: Check deployment script logs for manual instructions
6. ✅ Purview roles assigned via API (Collection Admin, Data Source Admin, Data Curator)
   - If fails: Check deployment script logs for manual instructions

### Phase 3: Fabric Resources (Expected: ~10-15 minutes)
**Expected Results:**
7. ✅ Fabric Domain created
8. ✅ Fabric Workspace created and attached to capacity
9. ✅ Capacity verified as active
10. ✅ Workspace assigned to domain
11. ✅ Lakehouses created (bronze, silver, gold)

### Phase 4: Purview Integration (Expected: ~5-10 minutes)
**Expected Results:**
12. ✅ Purview Collection created
13. ✅ Fabric datasource registered in Purview
14. ✅ Purview scan triggered (if enabled)

### Phase 5: Optional Features (if enabled)
**Expected Results:**
15. ✅ Log Analytics connected (if enableLogAnalytics: true)
16. ✅ OneLake indexes created (if AI services configured)

---

## 🔍 Validation Commands

### 1. Verify Managed Identity
```bash
# Get managed identity details
az identity list \
  --resource-group rg-dev101625 \
  --query "[?contains(name, 'fabric-automation')].{Name:name, PrincipalId:principalId, ClientId:clientId}" \
  -o table
```

### 2. Verify Storage Account Security
```bash
# Should show: allowSharedKeyAccess = false
az storage account show \
  --name stdeploy<uniqueString> \
  --resource-group rg-dev101625 \
  --query "{Name:name, AllowSharedKeyAccess:allowSharedKeyAccess, PublicNetworkAccess:publicNetworkAccess}" \
  -o table
```

### 3. Verify Storage RBAC
```bash
# Should show: Storage File Data Privileged Contributor
PRINCIPAL_ID=$(az identity list --resource-group rg-dev101625 --query "[?contains(name, 'fabric-automation')].principalId" -o tsv)

az role assignment list \
  --assignee $PRINCIPAL_ID \
  --resource-group rg-dev101625 \
  --query "[].{Role:roleDefinitionName, Scope:scope}" \
  -o table
```

### 4. Check Deployment Script Logs
```bash
# Find deployment script resources
az resource list \
  --resource-group rg-dev101625 \
  --resource-type Microsoft.Resources/deploymentScripts \
  --query "[].{Name:name, Status:properties.status.containerInstanceId}" \
  -o table

# View specific script logs (replace with actual name)
az deployment-scripts show-log \
  --resource-group rg-dev101625 \
  --name <deployment-script-name>
```

### 5. Verify Fabric Resources
```bash
# Check Fabric capacity
az fabric capacity show \
  --name swancapacitytest1016 \
  --resource-group rg-dev101625 \
  --query "{Name:name, State:properties.state, SKU:sku.name}" \
  -o table
```

### 6. Verify Purview Integration
- Go to https://web.purview.azure.com/
- Open account: swantekPurview
- Check Data Map → Collections for new collection
- Check Data Map → Sources for Fabric datasource

---

## 🐛 Troubleshooting Guide

### Issue: "Insufficient permissions" in Fabric operations
**Symptoms**: Fabric domain/workspace creation fails with 403 Forbidden
**Solution**: Check assignFabricRoles deployment script logs
```bash
# View Fabric RBAC script logs
az deployment-scripts show-log \
  --resource-group rg-dev101625 \
  --name assign-fabric-roles-<uniqueString>
```

If automated assignment failed, manually assign in Fabric Portal:
1. Go to https://app.fabric.microsoft.com/admin
2. Navigate to Capacity settings → swancapacitytest1016
3. Add Principal ID from managed identity as Administrator

### Issue: "Access denied" in Purview operations
**Symptoms**: Purview collection creation or datasource registration fails
**Solution**: Check assignPurviewRoles deployment script logs
```bash
# View Purview RBAC script logs
az deployment-scripts show-log \
  --resource-group rg-dev101625 \
  --name assign-purview-roles-<uniqueString>
```

If automated assignment failed, manually assign in Purview Portal:
1. Go to https://web.purview.azure.com/
2. Open account: swantekPurview
3. Assign roles: Collection Admin, Data Source Administrator, Data Curator

### Issue: Storage account still has shared key access enabled
**Symptoms**: Storage account shows allowSharedKeyAccess: true
**Root Cause**: AVM module failed to apply setting
**Solution**: Manually disable
```bash
az storage account update \
  --name stdeploy<uniqueString> \
  --resource-group rg-dev101625 \
  --allow-shared-key-access false
```

### Issue: Deployment script can't write to storage
**Symptoms**: Error "Key based authentication is not permitted"
**Root Cause**: Storage RBAC not assigned
**Solution**: Verify and assign manually if needed
```bash
PRINCIPAL_ID=<your-principal-id>
STORAGE_ID=/subscriptions/.../storageAccounts/stdeploy...

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage File Data Privileged Contributor" \
  --scope $STORAGE_ID
```

---

## 📊 Success Criteria

### ✅ Deployment Completes Successfully
- All 14 deployment scripts execute without errors
- No manual RBAC assignments required
- Storage account has allowSharedKeyAccess: false

### ✅ Security Validation
- No storage account keys in parameters or outputs
- Managed identity authentication working
- RBAC roles properly assigned

### ✅ Functional Validation
- Fabric capacity active
- Fabric workspace created and attached
- Fabric domain with workspace assigned
- Lakehouses created and accessible
- Purview collection created
- Fabric datasource registered in Purview

### ✅ Documentation Complete
- RBAC_REQUIREMENTS.md reflects actual deployment
- ORCHESTRATION_GUIDE.md updated with managed identity approach
- All manual steps documented (if any API calls failed)

---

## 🎯 Next Steps After Successful Deployment

1. **Verify All Resources**
   - Check Azure Portal for all resources
   - Verify Fabric Portal shows workspace and domain
   - Verify Purview Portal shows collection and datasource

2. **Test Functionality**
   - Upload sample data to lakehouses
   - Trigger Purview scan
   - Verify metadata appears in Purview

3. **Update Documentation**
   - Document any manual steps that were required
   - Update ORCHESTRATION_GUIDE.md with lessons learned

4. **Prepare for Production**
   - Review security settings
   - Plan for CI/CD pipeline integration
   - Consider additional environments (dev/staging/prod)

---

## 🚀 Ready to Deploy!

Everything is prepared and ready for testing. Run:

```bash
cd /workspaces/fabric-purview-domain-integration
azd provision
```

Monitor the deployment and check off items as they complete. Good luck! 🎉
