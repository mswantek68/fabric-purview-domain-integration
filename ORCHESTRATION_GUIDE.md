# Orchestration Guide - Running Governance & Security Scripts

## Overview

This document explains the **three ways** to run the Purview Governance and Defender for AI automation scripts in your environment.

---

## 🎯 Three Orchestration Options

### Option 1: Automated via `azure.yaml` (Recommended for Full Deployment)

**When to use**: Full infrastructure deployment with `azd up`

**How it works**:
- All scripts run automatically during `azd up` post-provisioning phase
- Executes in the correct order after infrastructure deployment
- No manual intervention required
- Integrated with Azure Developer CLI environment

**Command**:
```bash
azd up
```

**Script Execution Order**:
1. Infrastructure deployment (Bicep)
2. Fabric workspace automation
3. OneLake indexing setup
4. **→ Purview DSPM scripts** (4 scripts)
5. **→ Defender for AI scripts** (5 scripts)

**Pros**:
- ✅ Zero manual steps
- ✅ Fully automated deployment
- ✅ Guaranteed correct execution order
- ✅ Integrated with azd environment variables

**Cons**:
- ❌ Less flexibility (all-or-nothing)
- ❌ Harder to debug individual script failures
- ❌ Requires full `azd` infrastructure deployment

---

### Option 2: Standalone Orchestrator (Recommended for Governance Only)

**When to use**: 
- Infrastructure already deployed
- Want to run governance/security independently
- Need selective execution (only Purview OR only Defender)

**How it works**:
- Single orchestrator script manages execution
- Runs scripts in correct order with error tracking
- Provides detailed execution summary
- Supports skipping phases

**Commands**:
```bash
# Run both Purview and Defender scripts
pwsh scripts/run_governance_and_security.ps1

# Run only Purview DSPM scripts
pwsh scripts/run_governance_and_security.ps1 -SkipDefender

# Run only Defender for AI scripts
pwsh scripts/run_governance_and_security.ps1 -SkipPurview
```

**Execution Flow**:
```
Phase 1: Purview DSPM for AI
├── enable_purview_dspm.ps1
├── create_dspm_policies.ps1
├── connect_dspm_to_ai_foundry.ps1
└── verify_dspm_configuration.ps1

Phase 2: Microsoft Defender for AI
├── enable_defender_for_cloud.ps1
├── enable_defender_for_ai.ps1
├── enable_user_prompt_evidence.ps1
├── connect_defender_to_purview.ps1
└── verify_defender_ai_configuration.ps1
```

**Pros**:
- ✅ Flexible (skip phases as needed)
- ✅ Detailed execution tracking
- ✅ Continues on errors (doesn't fail fast)
- ✅ Comprehensive summary report
- ✅ Can run multiple times safely

**Cons**:
- ❌ Requires existing infrastructure
- ❌ Manual invocation required

**Output Example**:
```
═══════════════════════════════════════════════════════════════
  Orchestration Complete!
═══════════════════════════════════════════════════════════════

Execution Summary:
  Start Time:        2025-10-14 10:30:00
  End Time:          2025-10-14 10:45:00
  Duration:          00:15:00
  Total Scripts:     9
  Successful:        9
  Failed:            0

Successfully executed scripts:
  ✓ enable_purview_dspm.ps1
  ✓ create_dspm_policies.ps1
  ✓ connect_dspm_to_ai_foundry.ps1
  ✓ verify_dspm_configuration.ps1
  ✓ enable_defender_for_cloud.ps1
  ✓ enable_defender_for_ai.ps1
  ✓ enable_user_prompt_evidence.ps1
  ✓ connect_defender_to_purview.ps1
  ✓ verify_defender_ai_configuration.ps1
```

---

### Option 3: Manual Execution (Recommended for Debugging/Testing)

**When to use**:
- Testing individual scripts
- Debugging specific failures
- Learning how scripts work
- Custom execution order needed

**How it works**:
- Run each script individually
- Full control over execution
- Can skip scripts or retry failed ones
- Best for troubleshooting

**Commands**:

**Phase 1: Purview DSPM**
```bash
cd scripts/PurviewGovernance

# 1. Enable DSPM for AI
pwsh enable_purview_dspm.ps1

# 2. Create governance policies (requires M365 E5)
pwsh create_dspm_policies.ps1

# 3. Connect to AI Foundry projects
pwsh connect_dspm_to_ai_foundry.ps1

# 4. Verify configuration
pwsh verify_dspm_configuration.ps1
```

**Phase 2: Microsoft Defender for AI**
```bash
cd scripts/DefenderScripts

# 1. Enable Defender for Cloud (CSPM)
pwsh enable_defender_for_cloud.ps1

# 2. Enable AI services threat detection
pwsh enable_defender_for_ai.ps1

# 3. Enable user prompt evidence collection
pwsh enable_user_prompt_evidence.ps1

# 4. Integrate with Purview
pwsh connect_defender_to_purview.ps1

# 5. Verify complete configuration
pwsh verify_defender_ai_configuration.ps1
```

**Pros**:
- ✅ Maximum control
- ✅ Easy to debug
- ✅ Can skip scripts
- ✅ Can retry individual scripts
- ✅ See detailed output per script

**Cons**:
- ❌ Most manual work
- ❌ Easy to run scripts out of order
- ❌ No automatic summary
- ❌ Must remember dependencies

---

## 📋 Comparison Matrix

| Feature | azd yaml | Orchestrator | Manual |
|---------|----------|-------------|---------|
| **Automation** | Full | Partial | None |
| **Flexibility** | Low | High | Maximum |
| **Error Recovery** | Stops on failure | Continues | User-controlled |
| **Execution Summary** | No | Yes | No |
| **Selective Execution** | No | Yes | Yes |
| **Best For** | Full deployment | Post-deployment governance | Debugging |
| **Skill Level** | Beginner | Intermediate | Advanced |

---

## 🎓 Recommendations by Scenario

### Scenario 1: First-Time Deployment
**Use**: Option 1 (azd yaml)
```bash
azd up
```
Let automation handle everything from infrastructure to governance.

---

### Scenario 2: Add Governance to Existing Infrastructure
**Use**: Option 2 (Orchestrator)
```bash
pwsh scripts/run_governance_and_security.ps1
```
Clean, organized execution with comprehensive reporting.

---

### Scenario 3: Only Need Defender (Already Have Purview)
**Use**: Option 2 (Orchestrator with flag)
```bash
pwsh scripts/run_governance_and_security.ps1 -SkipPurview
```

---

### Scenario 4: Script Failed During Deployment
**Use**: Option 3 (Manual)
```bash
# Re-run just the failed script
pwsh scripts/PurviewGovernance/create_dspm_policies.ps1
```

---

### Scenario 5: Testing Changes to Scripts
**Use**: Option 3 (Manual)
```bash
# Test individual script modifications
pwsh scripts/DefenderScripts/enable_defender_for_ai.ps1
```

---

## 🔍 How to Choose

```
Do you need to deploy infrastructure?
├─ YES → Use Option 1 (azd yaml)
└─ NO
   ├─ Want automated governance setup?
   │  ├─ YES → Use Option 2 (Orchestrator)
   │  └─ NO → Use Option 3 (Manual)
   └─ Need to debug a specific script?
      └─ Use Option 3 (Manual)
```

---

## 📝 Script Dependencies

### Required for All Options:
- ✅ PowerShell 7+
- ✅ Azure CLI (authenticated)
- ✅ Proper Azure RBAC roles
- ✅ `SecurityModule.ps1` (in scripts folder)

### Purview Scripts Require:
- ✅ Microsoft 365 E5 license
- ✅ Exchange Online Management module
- ✅ Compliance Admin role

### Defender Scripts Require:
- ✅ Security Admin or Owner role
- ✅ Defender for Cloud enabled
- ✅ Valid Azure subscription

---

## 🚀 Quick Reference

### Run Everything (After azd up)
```bash
pwsh scripts/run_governance_and_security.ps1
```

### Run Only Purview
```bash
pwsh scripts/run_governance_and_security.ps1 -SkipDefender
```

### Run Only Defender
```bash
pwsh scripts/run_governance_and_security.ps1 -SkipPurview
```

### Verify Configuration
```bash
pwsh scripts/PurviewGovernance/verify_dspm_configuration.ps1
pwsh scripts/DefenderScripts/verify_defender_ai_configuration.ps1
```

---

## 📚 Additional Resources

- **Purview DSPM**: `scripts/PurviewGovernance/README.md`
- **Defender for AI**: `scripts/DefenderScripts/README.md`
- **Main Documentation**: `README.md`
- **Implementation Details**: 
  - `scripts/PurviewGovernance/IMPLEMENTATION_SUMMARY.md`
  - `scripts/DefenderScripts/` (coming soon)

---

## ❓ FAQ

**Q: Can I run the orchestrator multiple times?**  
A: Yes! All scripts are idempotent and safe to re-run.

**Q: What if a script fails during orchestration?**  
A: The orchestrator continues with remaining scripts and provides a summary of failures. You can then manually re-run failed scripts.

**Q: Do I need to run scripts in order?**  
A: Yes for dependencies within each phase, but phases are independent. Purview and Defender can run in any order.

**Q: Can I modify azure.yaml to skip scripts?**  
A: Yes! Comment out scripts you don't need in the `postprovision` hooks section.

**Q: How long does full execution take?**  
A: ~15-20 minutes for all scripts (Purview + Defender).

---

## 🎯 Next Steps

1. Choose your orchestration method based on scenario
2. Ensure prerequisites are met
3. Run scripts
4. Verify configuration with verification scripts
5. Monitor portals:
   - Defender: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade
   - Purview: https://purview.microsoft.com/purviewforai/overview
