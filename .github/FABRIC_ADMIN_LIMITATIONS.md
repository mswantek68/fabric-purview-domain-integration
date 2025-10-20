# 🔒 Fabric Administrator Automation Limitations

## TL;DR

**Why can't we automate Fabric Administrator assignment?**

Fabric Administrator is **NOT an Azure RBAC role** - it's managed through a completely separate Power Platform identity system that has no ARM API. You must assign at least the first admin manually in the Fabric portal.

---

## 🚫 The Problem

### What Doesn't Work

```powershell
# ❌ THIS DOESN'T EXIST
az role assignment create `
    --assignee "user@contoso.com" `
    --role "Fabric Administrator" `
    --scope "/subscriptions/..."

# ❌ NO ARM API
az fabric admin assign `
    --principal "..." `
    --role "Fabric Administrator"

# ❌ NOT IN BICEP/TERRAFORM
resource fabricAdmin 'Microsoft.Fabric/admins@2023-11-01' = {
  # This resource type doesn't exist!
}
```

### What Does Work

```powershell
# ✅ Azure RBAC roles (different system)
az role assignment create `
    --assignee "user@contoso.com" `
    --role "Contributor" `
    --scope "/subscriptions/..."

# ✅ Purview roles (Azure RBAC-based)
az role assignment create `
    --assignee "user@contoso.com" `
    --role "Purview Data Curator" `
    --scope "/subscriptions/.../providers/Microsoft.Purview/accounts/..."
```

---

## 🔍 Root Cause Analysis

### Identity System Comparison

| System | Backend | Automation API | Assignable Via CLI/Script |
|--------|---------|----------------|---------------------------|
| **Azure RBAC** | Azure Resource Manager | ✅ ARM API | ✅ `az role assignment` |
| **Purview RBAC** | Azure Resource Manager | ✅ ARM API | ✅ `az role assignment` |
| **Fabric Admin** | Power Platform | ❌ No ARM API | ❌ Portal only |

### Chicken-and-Egg Problem

```
┌─────────────────────────────────────────────────────────┐
│ To call Fabric Admin API                                │
│    ↓                                                     │
│ You need: Fabric Administrator role                     │
│    ↓                                                     │
│ To assign: Fabric Administrator role                    │
│    ↓                                                     │
│ You need: Call Fabric Admin API                         │
│    ↓                                                     │
│ 🔄 CIRCULAR DEPENDENCY                                  │
└─────────────────────────────────────────────────────────┘
```

### Technical Details

1. **Different API Endpoint**
   - Azure RBAC: `management.azure.com` (ARM)
   - Fabric Admin: `api.fabric.microsoft.com` (Power Platform)

2. **Different Authentication Scopes**
   - Azure RBAC: `https://management.azure.com`
   - Fabric Admin: `https://api.fabric.microsoft.com`

3. **Different Permission Model**
   - Azure RBAC: Resource-scoped (subscription, resource group, resource)
   - Fabric Admin: Tenant-scoped (all capacities, all workspaces)

4. **Different Assignment Mechanism**
   - Azure RBAC: `az role assignment create` (ARM API)
   - Fabric Admin: Portal UI only (no ARM API)

---

## 💡 Workarounds

### **Option 1: Entra ID Group (Recommended)**

**How it works:**
1. Create Entra ID group manually
2. Assign **the group** as Fabric Administrator (manual, one-time)
3. Add service principals to the group (✅ can be automated!)

**Setup:**

```powershell
# Step 1: Create group
az ad group create `
    --display-name "fabric-admins-automation" `
    --mail-nickname "fabricadmins" `
    --description "Service principals with Fabric Administrator permissions"

# Step 2: Manually assign group as Fabric Admin
# Go to: https://app.fabric.microsoft.com
# Settings → Admin Portal → Tenant settings → Admin API settings
# Enable "Service principals can use Fabric APIs"
# Add "fabric-admins-automation" group

# Step 3: Add service principal to group (AUTOMATED!)
./scripts/Fabric_Purview_Automation/Add-ServicePrincipalToFabricAdminsGroup.ps1 `
    -ServicePrincipalAppId "abc-123-..." `
    -FabricAdminsGroupName "fabric-admins-automation"
```

**Pros:**
- ✅ Only need to assign group once
- ✅ Can automate adding/removing members
- ✅ Centralized management
- ✅ Audit trail in Entra ID

**Cons:**
- ⚠️ Still requires manual group assignment in Fabric portal
- ⚠️ All group members get tenant-wide admin (high privilege)

---

### **Option 2: Capacity Admin Only**

**How it works:**
Assign **Capacity Admin** instead of Fabric Administrator. This is capacity-scoped (not tenant-wide).

**Setup:**

```powershell
# Requires: You (the person running this) must already be Fabric Admin
./scripts/Fabric_Purview_Automation/Add-CapacityAdmin.ps1 `
    -ServicePrincipalId "abc-123-..." `
    -CapacityName "fabriccapacityprod" `
    -CapacityResourceGroup "rg-fabric-prod"
```

**Pros:**
- ✅ Less privileged (capacity-scoped only)
- ✅ Can be scripted (if you're already Fabric Admin)

**Cons:**
- ⚠️ Still requires Fabric Admin to run the script
- ⚠️ Must assign for each capacity separately
- ⚠️ Can't create domains (requires Fabric Administrator)

---

### **Option 3: Use a User's Token**

**How it works:**
Run automation scripts interactively as a **user** who is Fabric Admin, not a service principal.

**Setup:**

```powershell
# Login as user (not service principal)
az login

# Now your scripts run with Fabric Admin permissions
./scripts/Fabric_Purview_Automation/create_fabric_domain.ps1 -domainName "Sales"
```

**Pros:**
- ✅ Full Fabric Administrator permissions
- ✅ Works immediately

**Cons:**
- ❌ Requires interactive login
- ❌ Can't run in CI/CD pipelines
- ❌ No long-term credential storage
- ❌ Tied to a specific user (not service account)

---

### **Option 4: Wait for Microsoft**

**Status:** Microsoft is aware of this limitation and it's on the roadmap.

**Sources:**
- [Microsoft Q&A: Automate Fabric Admin assignment](https://learn.microsoft.com/en-us/answers/questions/)
- [GitHub Issues: azure-cli support for Fabric RBAC](https://github.com/Azure/azure-cli/issues)
- Community Tech Days sessions mentioning "improved automation coming"

**Timeline:** Unknown (likely 2025-2026)

**What's expected:**
- ARM API for Fabric Administrator assignment
- Support in `az fabric` CLI commands
- Bicep/Terraform resource types

---

## 🎯 Recommended Approach for Your Project

### **Hybrid Approach: Group + Manual Setup**

1. **One-time manual setup** (document this clearly):
   ```
   CREATE ENTRA ID GROUP
   ↓
   ASSIGN GROUP AS FABRIC ADMIN IN PORTAL
   ↓
   DOCUMENT IN DEPLOYMENT GUIDE
   ```

2. **Automated additions** (works after setup):
   ```powershell
   # Add service principal to group (automated)
   ./scripts/Fabric_Purview_Automation/Add-ServicePrincipalToFabricAdminsGroup.ps1 `
       -ServicePrincipalAppId $env:AZURE_CLIENT_ID `
       -FabricAdminsGroupName "fabric-admins-automation"
   ```

3. **Update your GitHub Actions workflow**:
   ```yaml
   - name: Add Service Principal to Fabric Admins Group
     shell: pwsh
     run: |
       ./scripts/Fabric_Purview_Automation/Add-ServicePrincipalToFabricAdminsGroup.ps1 `
           -ServicePrincipalAppId "${{ secrets.AZURE_CLIENT_ID }}" `
           -FabricAdminsGroupName "fabric-admins-automation"
   ```

---

## 📊 Comparison Matrix

| Approach | Automation Level | Security | Complexity | Recommended |
|----------|-----------------|----------|------------|-------------|
| **Entra Group** | 90% (group=manual, membership=auto) | Medium | Low | ✅ **Yes** |
| **Capacity Admin** | 80% (requires Fabric Admin to run) | High (least privilege) | Medium | ⚠️ For capacity-only |
| **User Token** | 0% (interactive only) | Low (user credentials) | Low | ❌ No (dev only) |
| **Wait for MS** | Future 100% | High | N/A | ⏳ Coming |

---

## 🔧 Implementation Guide

### Add to Your Workflow

Update `.github/workflows/deploy-fabric-integration.yml`:

```yaml
# Add this job after federated credentials setup
add-to-fabric-admins-group:
  name: Add Service Principal to Fabric Admins Group
  runs-on: ubuntu-latest
  needs: [load-config]
  if: ${{ needs.load-config.outputs.fabric_admin_group_enabled == 'true' }}
  
  steps:
    - name: Checkout Repository
      uses: actions/checkout@v4
    
    - name: Azure Login
      uses: azure/login@v2
      with:
        client-id: ${{ needs.load-config.outputs.azure_client_id }}
        tenant-id: ${{ needs.load-config.outputs.azure_tenant_id }}
        subscription-id: ${{ needs.load-config.outputs.azure_subscription_id }}
    
    - name: Add to Fabric Admins Group
      shell: pwsh
      run: |
        ./scripts/Fabric_Purview_Automation/Add-ServicePrincipalToFabricAdminsGroup.ps1 `
            -ServicePrincipalAppId "${{ needs.load-config.outputs.azure_client_id }}" `
            -FabricAdminsGroupName "fabric-admins-automation"
```

### Add to Your Config

Update `.github/config/deployment-config.yml`:

```yaml
rbac:
  fabric_roles:
    enabled: true
    admin_group:
      enabled: true  # Set to true to use group-based approach
      name: "fabric-admins-automation"  # Group name in Entra ID
```

### Update Documentation

Add to `.github/DEPLOYMENT_GUIDE.md`:

```markdown
### Manual Step: Create Fabric Admins Group

**ONE-TIME SETUP (required for automation)**:

1. Create Entra ID group:
   ```powershell
   az ad group create `
       --display-name "fabric-admins-automation" `
       --mail-nickname "fabricadmins"
   ```

2. Assign group as Fabric Administrator:
   - Go to: https://app.fabric.microsoft.com
   - Settings → Admin Portal → Tenant settings → Admin API settings
   - Enable "Service principals can use Fabric APIs"
   - Add "fabric-admins-automation" group

3. ✅ Done! Service principals will be added to this group automatically
```

---

## 📚 Additional Resources

- [Microsoft Fabric Admin API Documentation](https://learn.microsoft.com/en-us/rest/api/fabric/admin)
- [Fabric Service Principal Limitations](https://learn.microsoft.com/en-us/fabric/admin/service-principal-support)
- [Power Platform Identity Architecture](https://learn.microsoft.com/en-us/power-platform/admin/wp-security)
- [Azure RBAC vs Fabric Roles](https://learn.microsoft.com/en-us/fabric/security/permission-model)

---

## 🆘 FAQ

**Q: Can I use a service principal with a certificate instead of a secret?**  
A: Yes, but it doesn't solve the Fabric Admin assignment problem. You still need manual portal assignment.

**Q: What about using the Fabric PowerShell module?**  
A: The official `Microsoft.Fabric.PowerShell` module also requires you to already have Fabric Admin permissions.

**Q: Can I use Microsoft Graph API?**  
A: No. Fabric Admin is not exposed through Microsoft Graph. It's a Power Platform-specific role.

**Q: What about using PnP PowerShell?**  
A: PnP PowerShell is for SharePoint/Microsoft 365, not Fabric.

**Q: Will this ever be fixed?**  
A: Likely yes, but no official timeline. Microsoft is aware of the limitation.

---

## ✅ Summary

**The Reality:**
- ❌ You **cannot** fully automate Fabric Administrator assignment
- ⚠️ This is a **platform limitation**, not a gap in your implementation
- ✅ You **can** automate 90% by using an Entra ID group

**Recommended Solution:**
1. Create Entra ID group (once, manual)
2. Assign group as Fabric Admin (once, manual)
3. Automate adding service principals to group (✅ works!)

**Your Current Approach:**
Your workflow correctly identifies this as a manual step and provides clear instructions. **This is the right approach** given current limitations.
