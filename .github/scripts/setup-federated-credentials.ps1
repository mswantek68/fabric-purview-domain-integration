<#
.SYNOPSIS
    Setup Federated Credentials for GitHub Actions OIDC authentication.

.DESCRIPTION
    Creates an Azure App Registration with federated credentials for GitHub Actions.
    This enables OIDC authentication without storing secrets in GitHub.
    
    Creates credentials for:
    - main branch
    - feature/github-actions-automation branch
    - Pull requests
    - Production environment

.PARAMETER RepositoryFullName
    GitHub repository in format: org/repo (e.g., mswantek68/fabric-purview-domain-integration)

.PARAMETER AppName
    Name for the App Registration (default: github-actions-fabric-automation)

.EXAMPLE
    ./setup-federated-credentials.ps1 -RepositoryFullName "mswantek68/fabric-purview-domain-integration"
    
.EXAMPLE
    ./setup-federated-credentials.ps1 `
        -RepositoryFullName "myorg/myrepo" `
        -AppName "my-github-actions-app"

.NOTES
    Requires:
    - Azure CLI installed and authenticated (az login)
    - Permissions to create App Registrations
    - Subscription Owner or User Access Administrator role
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryFullName,
    
    [Parameter(Mandatory = $false)]
    [string]$AppName = "github-actions-fabric-automation"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "GitHub Actions Federated Credential Setup" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Repository: $RepositoryFullName" -ForegroundColor Yellow
Write-Host "App Registration: $AppName" -ForegroundColor Yellow
Write-Host ""

# Parse repository name
$githubOrg = $RepositoryFullName.Split('/')[0]
$githubRepo = $RepositoryFullName.Split('/')[1]

# Get current Azure context
Write-Host "🔍 Getting Azure context..." -ForegroundColor Gray
$subscriptionId = (az account show --query id -o tsv)
$tenantId = (az account show --query tenantId -o tsv)

Write-Host "Azure Subscription: $subscriptionId" -ForegroundColor Gray
Write-Host "Azure Tenant: $tenantId" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Step 1: Create App Registration
# ============================================================================
Write-Host "📝 Step 1: Creating App Registration..." -ForegroundColor Cyan

$appId = az ad app list --display-name $AppName --query "[0].appId" -o tsv

if ([string]::IsNullOrEmpty($appId)) {
    $appId = az ad app create --display-name $AppName --query appId -o tsv
    Write-Host "  ✅ Created new app registration: $appId" -ForegroundColor Green
} else {
    Write-Host "  ✅ Using existing app registration: $appId" -ForegroundColor Green
}

# ============================================================================
# Step 2: Create Service Principal
# ============================================================================
Write-Host ""
Write-Host "👤 Step 2: Creating Service Principal..." -ForegroundColor Cyan

$spId = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv

if ([string]::IsNullOrEmpty($spId)) {
    $spId = az ad sp create --id $appId --query id -o tsv
    Write-Host "  ✅ Created service principal: $spId" -ForegroundColor Green
} else {
    Write-Host "  ✅ Using existing service principal: $spId" -ForegroundColor Green
}

# ============================================================================
# Step 3: Assign Azure RBAC Roles
# ============================================================================
Write-Host ""
Write-Host "🔐 Step 3: Assigning Azure RBAC roles..." -ForegroundColor Cyan

# Contributor role
try {
    az role assignment create `
        --assignee $appId `
        --role "Contributor" `
        --scope "/subscriptions/$subscriptionId" `
        --query "roleDefinitionName" -o tsv 2>$null | Out-Null
    Write-Host "  ✅ Contributor role assigned" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️  Contributor role already assigned" -ForegroundColor Yellow
}

# User Access Administrator role
try {
    az role assignment create `
        --assignee $appId `
        --role "User Access Administrator" `
        --scope "/subscriptions/$subscriptionId" `
        --query "roleDefinitionName" -o tsv 2>$null | Out-Null
    Write-Host "  ✅ User Access Administrator role assigned" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️  User Access Administrator role already assigned" -ForegroundColor Yellow
}

Write-Host "  ✅ RBAC roles configured" -ForegroundColor Green

# ============================================================================
# Step 4: Create Federated Credentials
# ============================================================================
Write-Host ""
Write-Host "🔗 Step 4: Creating Federated Credentials..." -ForegroundColor Cyan

# Get App Object ID (different from App ID)
$objectId = az ad app show --id $appId --query id -o tsv

# Helper function to create federated credential
function New-FederatedCredential {
    param(
        [string]$Name,
        [string]$Subject,
        [string]$Description
    )
    
    Write-Host "  Creating credential: $Description..." -ForegroundColor Gray
    
    $body = @{
        name = $Name
        issuer = "https://token.actions.githubusercontent.com"
        subject = $Subject
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Compress
    
    try {
        az rest --method POST `
            --uri "https://graph.microsoft.com/v1.0/applications/$objectId/federatedIdentityCredentials" `
            --headers "Content-Type=application/json" `
            --body $body 2>$null | Out-Null
        Write-Host "    ✅ $Description credential created" -ForegroundColor Green
    } catch {
        Write-Host "    ⚠️  $Description credential already exists" -ForegroundColor Yellow
    }
}

# Create credentials for different scenarios
New-FederatedCredential `
    -Name "github-actions-main" `
    -Subject "repo:${RepositoryFullName}:ref:refs/heads/main" `
    -Description "Main branch"

New-FederatedCredential `
    -Name "github-actions-feature" `
    -Subject "repo:${RepositoryFullName}:ref:refs/heads/feature/github-actions-automation" `
    -Description "Feature branch"

New-FederatedCredential `
    -Name "github-actions-pr" `
    -Subject "repo:${RepositoryFullName}:pull_request" `
    -Description "Pull requests"

New-FederatedCredential `
    -Name "github-actions-prod-env" `
    -Subject "repo:${RepositoryFullName}:environment:production" `
    -Description "Production environment"

Write-Host "  ✅ Federated credentials configured" -ForegroundColor Green

# ============================================================================
# Step 5: Manual Fabric Admin Setup Instructions
# ============================================================================
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Yellow
Write-Host "⚠️  Step 5: Fabric Administrator Permission (MANUAL STEP REQUIRED)" -ForegroundColor Yellow
Write-Host "============================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "The service principal needs Fabric Administrator permissions." -ForegroundColor White
Write-Host "This CANNOT be automated and must be done manually:" -ForegroundColor White
Write-Host ""
Write-Host "1. Go to: https://app.fabric.microsoft.com" -ForegroundColor Cyan
Write-Host "2. Click ⚙️ Settings → Admin Portal" -ForegroundColor Cyan
Write-Host "3. Navigate to: Tenant settings → Admin API settings" -ForegroundColor Cyan
Write-Host "4. Enable 'Service principals can use Fabric APIs'" -ForegroundColor Cyan
Write-Host "5. Add the service principal: $AppName" -ForegroundColor Cyan
Write-Host "   App ID: $appId" -ForegroundColor Yellow
Write-Host ""
Write-Host "Then assign Fabric Admin role:" -ForegroundColor White
Write-Host "6. In Admin Portal → Capacity settings" -ForegroundColor Cyan
Write-Host "7. Select your capacity" -ForegroundColor Cyan
Write-Host "8. Add '$AppName' as admin" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Step 6: Purview Permissions
# ============================================================================
Write-Host "============================================================================" -ForegroundColor Yellow
Write-Host "📚 Step 6: Purview Permissions" -ForegroundColor Yellow
Write-Host "============================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "For Purview Data Map access, run this command with your Purview account:" -ForegroundColor White
Write-Host ""
Write-Host "`$purviewAccount = `"your-purview-account`"" -ForegroundColor Cyan
Write-Host "`$resourceGroup = `"your-resource-group`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "az role assignment create ``" -ForegroundColor Green
Write-Host "  --assignee `"$appId`" ``" -ForegroundColor Green
Write-Host "  --role `"Purview Data Curator`" ``" -ForegroundColor Green
Write-Host "  --scope `"/subscriptions/$subscriptionId/resourceGroups/`$resourceGroup/providers/Microsoft.Purview/accounts/`$purviewAccount`"" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Summary
# ============================================================================
Write-Host "============================================================================" -ForegroundColor Green
Write-Host "✅ Setup Complete!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Configuration Values" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Update .github/config/deployment-config.yml with these values:" -ForegroundColor White
Write-Host ""
Write-Host "azure:" -ForegroundColor Yellow
Write-Host "  tenant_id: `"$tenantId`"" -ForegroundColor Yellow
Write-Host "  subscription_id: `"$subscriptionId`"" -ForegroundColor Yellow
Write-Host "  client_id: `"$appId`"" -ForegroundColor Yellow
Write-Host ""
Write-Host "OR add as GitHub Secrets:" -ForegroundColor White
Write-Host ""
Write-Host "gh secret set AZURE_CLIENT_ID --body `"$appId`"" -ForegroundColor Green
Write-Host "gh secret set AZURE_TENANT_ID --body `"$tenantId`"" -ForegroundColor Green
Write-Host "gh secret set AZURE_SUBSCRIPTION_ID --body `"$subscriptionId`"" -ForegroundColor Green
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "🚀 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Complete manual Fabric Admin assignment (see above)" -ForegroundColor White
Write-Host "2. Assign Purview roles (see command above)" -ForegroundColor White
Write-Host "3. Update deployment-config.yml with your settings" -ForegroundColor White
Write-Host "4. Run workflow: Actions → Deploy Fabric-Purview Integration → Run workflow" -ForegroundColor White
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# Save values to file for easy reference
$outputFile = ".github/config/federated-credentials-output.txt"
@"
============================================================================
GitHub Actions Federated Credentials
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
============================================================================

Azure Configuration:
  Tenant ID: $tenantId
  Subscription ID: $subscriptionId
  Client ID (App ID): $appId

App Registration:
  Name: $AppName
  App ID: $appId
  Object ID: $objectId
  Service Principal ID: $spId

Repository:
  Full Name: $RepositoryFullName
  Organization: $githubOrg
  Repository: $githubRepo

Federated Credentials Created:
  ✅ Main branch: repo:${RepositoryFullName}:ref:refs/heads/main
  ✅ Feature branch: repo:${RepositoryFullName}:ref:refs/heads/feature/github-actions-automation
  ✅ Pull requests: repo:${RepositoryFullName}:pull_request
  ✅ Production env: repo:${RepositoryFullName}:environment:production

RBAC Roles Assigned:
  ✅ Contributor (Subscription scope)
  ✅ User Access Administrator (Subscription scope)

Manual Steps Required:
  ⚠️  Fabric Administrator - See setup guide
  ⚠️  Purview Data Curator - Run command in setup guide

GitHub Secrets (choose one method):
  Method 1: Store in deployment-config.yml
  Method 2: Add as GitHub repository secrets

============================================================================
"@ | Out-File -FilePath $outputFile -Encoding UTF8

Write-Host "💾 Configuration saved to: $outputFile" -ForegroundColor Green
Write-Host ""
