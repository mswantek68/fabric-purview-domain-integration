#!/bin/bash

# ============================================================================

# Setup Federated Credentials for GitHub Actions

# ============================================================================

# This script creates an Azure App Registration with federated credentials

# for GitHub Actions OIDC authentication (no secrets required!)

##

# Usage: ./setup-federated-credentials.sh <github-org>/<github-repo>

# Example: ./setup-federated-credentials.sh mswantek68/fabric-purview-domain-integration



set -e



REPO_FULL_NAME="${1:?GitHub repository (org/repo) is required}"REPO_FULL_NAME="${1:?GitHub repository (org/repo) is required}"

APP_NAME="${2:-github-actions-fabric-automation}"APP_NAME="${2:-github-actions-fabric-automation}"



echo "============================================================================"echo "============================================================================"

echo "GitHub Actions Federated Credential Setup"echo "GitHub Actions Federated Credential Setup"

echo "============================================================================"echo "============================================================================"

echo "Repository: $REPO_FULL_NAME"echo "Repository: $REPO_FULL_NAME"

echo "App Registration: $APP_NAME"echo "App Registration: $APP_NAME"

echo ""echo ""



# Get current subscription and tenant# Parse org and repo

SUBSCRIPTION_ID=$(az account show --query id -o tsv)GITHUB_ORG=$(echo "$REPO_FULL_NAME" | cut -d'/' -f1)

TENANT_ID=$(az account show --query tenantId -o tsv)GITHUB_REPO=$(echo "$REPO_FULL_NAME" | cut -d'/' -f2)



echo "Azure Subscription: $SUBSCRIPTION_ID"# Get current subscription and tenant

echo "Azure Tenant: $TENANT_ID"SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo ""TENANT_ID=$(az account show --query tenantId -o tsv)



# Step 1: Create App Registrationecho "Azure Subscription: $SUBSCRIPTION_ID"

echo "📝 Step 1: Creating App Registration..."echo "Azure Tenant: $TENANT_ID"

APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)echo ""



if [ -z "$APP_ID" ]; then# Step 1: Create App Registration

  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)echo "📝 Step 1: Creating App Registration..."

  echo "✅ Created new app registration: $APP_ID"APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)

else

  echo "✅ Using existing app registration: $APP_ID"if [ -z "$APP_ID" ]; then

fi  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)

  echo "✅ Created new app registration: $APP_ID"

# Step 2: Create Service Principalelse

echo ""  echo "✅ Using existing app registration: $APP_ID"

echo "👤 Step 2: Creating Service Principal..."fi

SP_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv)

# Step 2: Create Service Principal

if [ -z "$SP_ID" ]; thenecho ""

  SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)echo "👤 Step 2: Creating Service Principal..."

  echo "✅ Created service principal: $SP_ID"SP_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv)

else

  echo "✅ Using existing service principal: $SP_ID"if [ -z "$SP_ID" ]; then

fi  SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)

  echo "✅ Created service principal: $SP_ID"

# Step 3: Assign Azure RBAC Roleselse

echo ""  echo "✅ Using existing service principal: $SP_ID"

echo "🔐 Step 3: Assigning Azure RBAC roles..."fi



# Contributor on subscription (for infrastructure deployment)# Step 3: Assign Azure RBAC Roles

# Check if Contributor role assignment exists
if az role assignment list --assignee "$APP_ID" --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[].id" -o tsv | grep -q .; then
  echo "  ⚠️  Contributor role already assigned"
else
  if az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID" >/dev/null; then
    echo "  ✅ Contributor role assigned"
  else
    echo "  ❌ Failed to assign Contributor role" >&2
    exit 1
  fi
fi

# Check if User Access Administrator role assignment exists
if az role assignment list --assignee "$APP_ID" --role "User Access Administrator" --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[].id" -o tsv | grep -q .; then
  echo "  ⚠️  User Access Administrator role already assigned"
else
  if az role assignment create --assignee "$APP_ID" --role "User Access Administrator" --scope "/subscriptions/$SUBSCRIPTION_ID" >/dev/null; then
    echo "  ✅ User Access Administrator role assigned"
  else
    echo "  ❌ Failed to assign User Access Administrator role" >&2
    exit 1
  fi
fi
# User Access Administrator (for assigning Fabric/Purview roles)

# Step 4: Create Federated Credentials for GitHub Actionsaz role assignment create \

echo ""  --assignee "$APP_ID" \

echo "🔗 Step 4: Creating Federated Credentials..."  --role "User Access Administrator" \

  --scope "/subscriptions/$SUBSCRIPTION_ID" \

# Get object ID  --query "roleDefinitionName" -o tsv 2>/dev/null || echo "  ⚠️  User Access Administrator role already assigned"

OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)

echo "✅ RBAC roles assigned"

# Federated credential for main branch

echo "  Creating credential for main branch..."# Step 4: Create Federated Credentials for GitHub Actions

az rest --method POST \echo ""

  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID/federatedIdentityCredentials" \echo "🔗 Step 4: Creating Federated Credentials..."

  --headers "Content-Type=application/json" \

  --body "{# Get object ID

    \"name\": \"github-actions-main\",OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)

    \"issuer\": \"https://token.actions.githubusercontent.com\",

    \"subject\": \"repo:$REPO_FULL_NAME:ref:refs/heads/main\",# Federated credential for main branch

    \"audiences\": [\"api://AzureADTokenExchange\"]MAIN_CRED_NAME="github-actions-main"

  }" 2>/dev/null && echo "    ✅ Main branch credential created" || echo "    ⚠️  Main branch credential already exists"echo "  Creating credential for main branch..."

az rest --method POST \

# Federated credential for feature/github-actions-automation branch  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID/federatedIdentityCredentials" \

echo "  Creating credential for feature/github-actions-automation branch..."  --headers "Content-Type=application/json" \

az rest --method POST \  --body "{

  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID/federatedIdentityCredentials" \    \"name\": \"$MAIN_CRED_NAME\",

  --headers "Content-Type=application/json" \    \"issuer\": \"https://token.actions.githubusercontent.com\",

  --body "{    \"subject\": \"repo:$REPO_FULL_NAME:ref:refs/heads/main\",

    \"name\": \"github-actions-feature-automation\",    \"audiences\": [\"api://AzureADTokenExchange\"]

    \"issuer\": \"https://token.actions.githubusercontent.com\",  }" 2>/dev/null || echo "  ⚠️  Credential for main branch already exists"

    \"subject\": \"repo:$REPO_FULL_NAME:ref:refs/heads/feature/github-actions-automation\",

    \"audiences\": [\"api://AzureADTokenExchange\"]# Federated credential for feature branches

  }" 2>/dev/null && echo "    ✅ Feature branch credential created" || echo "    ⚠️  Feature branch credential already exists"FEATURE_CRED_NAME="github-actions-feature"

echo "  Creating credential for feature/* branches..."

# Federated credential for pull requestsaz rest --method POST \

echo "  Creating credential for pull requests..."  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID/federatedIdentityCredentials" \

az rest --method POST \  --headers "Content-Type=application/json" \

  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID/federatedIdentityCredentials" \  --body "{

  --headers "Content-Type=application/json" \    \"name\": \"$FEATURE_CRED_NAME\",

  --body "{    \"issuer\": \"https://token.actions.githubusercontent.com\",

    \"name\": \"github-actions-pr\",    \"subject\": \"repo:$REPO_FULL_NAME:ref:refs/heads/feature/github-actions-automation\",

    \"issuer\": \"https://token.actions.githubusercontent.com\",    \"audiences\": [\"api://AzureADTokenExchange\"]

    \"subject\": \"repo:$REPO_FULL_NAME:pull_request\",  }" 2>/dev/null || echo "  ⚠️  Credential for feature branches already exists"

    \"audiences\": [\"api://AzureADTokenExchange\"]

  }" 2>/dev/null && echo "    ✅ Pull request credential created" || echo "    ⚠️  Pull request credential already exists"# Federated credential for pull requests

PR_CRED_NAME="github-actions-pr"

echo ""echo "  Creating credential for pull requests..."

echo "============================================================================"az rest --method POST \

echo "✅ Setup Complete!"  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID/federatedIdentityCredentials" \

echo "============================================================================"  --headers "Content-Type=application/json" \

echo ""  --body "{

echo "📋 Configuration Values"    \"name\": \"$PR_CRED_NAME\",

echo "============================================================================"    \"issuer\": \"https://token.actions.githubusercontent.com\",

echo ""    \"subject\": \"repo:$REPO_FULL_NAME:pull_request\",

echo "Copy these values to .github/config/deployment-config.yml:"    \"audiences\": [\"api://AzureADTokenExchange\"]

echo ""  }" 2>/dev/null || echo "  ⚠️  Credential for PRs already exists"

echo "azure:"

echo "  tenant_id: \"$TENANT_ID\""# Federated credential for environment (optional)

echo "  subscription_id: \"$SUBSCRIPTION_ID\""ENV_CRED_NAME="github-actions-prod-env"

echo "  client_id: \"$APP_ID\""echo "  Creating credential for production environment..."

echo ""az rest --method POST \

echo "============================================================================"  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID/federatedIdentityCredentials" \

echo "⚠️  MANUAL STEPS REQUIRED"  --headers "Content-Type=application/json" \

echo "============================================================================"  --body "{

echo ""    \"name\": \"$ENV_CRED_NAME\",

echo "1. Fabric Administrator Permission (REQUIRED):"    \"issuer\": \"https://token.actions.githubusercontent.com\",

echo "   a. Go to: https://app.fabric.microsoft.com"    \"subject\": \"repo:$REPO_FULL_NAME:environment:production\",

echo "   b. Click ⚙️ Settings → Admin Portal"    \"audiences\": [\"api://AzureADTokenExchange\"]

echo "   c. Tenant settings → Admin API settings"  }" 2>/dev/null || echo "  ⚠️  Credential for production environment already exists"

echo "   d. Enable 'Service principals can use Fabric APIs'"

echo "   e. Add service principal: $APP_NAME (App ID: $APP_ID)"echo "✅ Federated credentials created"

echo "   f. In Capacity settings, add as admin"

echo ""# Step 5: Grant Fabric Admin permissions (requires manual approval in Fabric portal)

echo "2. Purview Data Curator Permission (REQUIRED):"echo ""

echo "   Run this command with your Purview account:"echo "⚠️  Step 5: Fabric Administrator Permission (MANUAL STEP REQUIRED)"

echo ""echo ""

echo "   PURVIEW_ACCOUNT=\"your-purview-account\""echo "The service principal needs Fabric Administrator permissions."

echo "   RESOURCE_GROUP=\"your-resource-group\""echo "This CANNOT be automated and must be done manually:"

echo ""echo ""

echo "   az role assignment create \\"echo "1. Go to: https://app.fabric.microsoft.com"

echo "     --assignee \"$APP_ID\" \\"echo "2. Click ⚙️ Settings → Admin Portal"

echo "     --role \"Purview Data Curator\" \\"echo "3. Navigate to: Tenant settings → Admin API settings"

echo "     --scope \"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/\$RESOURCE_GROUP/providers/Microsoft.Purview/accounts/\$PURVIEW_ACCOUNT\""echo "4. Enable 'Service principals can use Fabric APIs'"

echo ""echo "5. Add the service principal: $APP_NAME"

echo "============================================================================"echo "   App ID: $APP_ID"

echo "🚀 Next Steps:"echo ""

echo "1. Update .github/config/deployment-config.yml with values above"echo "Then assign Fabric Admin role:"

echo "2. Complete manual Fabric Administrator assignment"echo "6. In Admin Portal → Capacity settings"

echo "3. Assign Purview Data Curator role"echo "7. Select your capacity"

echo "4. Push config: git add .github/config/ && git commit && git push"echo "8. Add '$APP_NAME' as admin"

echo "5. Run workflow: Actions → Deploy Fabric-Purview Integration"echo ""

echo "============================================================================"

# Step 6: Grant Purview permissions (requires Azure RBAC)
echo ""
echo "📚 Step 6: Purview Permissions"
echo ""
echo "For Purview Data Map access, run this command with your Purview account name:"
echo ""
echo "  PURVIEW_ACCOUNT=\"your-purview-account\""
echo "  az role assignment create \\"
echo "    --assignee \"$APP_ID\" \\"
echo "    --role \"Purview Data Curator\" \\"
echo "    --scope \"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/YOUR_RG/providers/Microsoft.Purview/accounts/\$PURVIEW_ACCOUNT\""
echo ""

# Summary
echo ""
echo "============================================================================"
echo "✅ Setup Complete!"
echo "============================================================================"
echo ""
echo "Add these secrets to your GitHub repository:"
echo "Repository Settings → Secrets and variables → Actions → New repository secret"
echo ""
echo "Secret Name: AZURE_CLIENT_ID"
echo "Value: $APP_ID"
echo ""
echo "Secret Name: AZURE_TENANT_ID"
echo "Value: $TENANT_ID"
echo ""
echo "Secret Name: AZURE_SUBSCRIPTION_ID"
echo "Value: $SUBSCRIPTION_ID"
echo ""
echo "OR update .github/config/deployment-config.yml with these values:"
echo ""
echo "azure:"
echo "  tenant_id: \"$TENANT_ID\""
echo "  subscription_id: \"$SUBSCRIPTION_ID\""
echo "  client_id: \"$APP_ID\""
echo ""
echo "============================================================================"
echo "Next Steps:"
echo "1. Complete manual Fabric Admin assignment (see above)"
echo "2. Assign Purview roles (see command above)"
echo "3. Update deployment-config.yml with your settings"
echo "4. Run workflow: Actions → Deploy Fabric-Purview Integration → Run workflow"
echo "============================================================================"
