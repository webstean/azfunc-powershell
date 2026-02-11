# GitHub Actions Deployment Guide

This guide explains how to set up automated deployments for this Azure Function App using GitHub Actions with OIDC authentication.

## Table of Contents
- [Why OIDC?](#why-oidc)
- [Prerequisites](#prerequisites)
- [Setup Steps](#setup-steps)
- [Workflow Overview](#workflow-overview)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

## Why OIDC?

OpenID Connect (OIDC) authentication provides several advantages over traditional credential-based authentication:

- ✅ **No stored credentials**: No long-lived secrets stored in GitHub
- ✅ **Short-lived tokens**: Authentication tokens expire quickly (typically 1 hour)
- ✅ **Scoped access**: Federated credentials can be restricted to specific repositories and branches
- ✅ **Easier rotation**: No need to rotate secrets stored in GitHub
- ✅ **Better audit trail**: Azure AD logs show which GitHub workflow requested access
- ✅ **Industry best practice**: Recommended by both GitHub and Microsoft

## Prerequisites

Before setting up the GitHub Actions workflow, you need:

1. An Azure subscription
2. A GitHub repository with this code
3. Azure CLI installed (for setup steps)
4. Appropriate permissions to:
   - Create Azure AD applications and service principals
   - Assign roles in Azure
   - Configure GitHub repository secrets

## Setup Steps

### Step 1: Create Azure Resources

```bash
# Variables - customize these
RESOURCE_GROUP="rg-azfunc-powershell"
LOCATION="eastus"
STORAGE_ACCOUNT="stazfuncps$(openssl rand -hex 3)"
FUNCTION_APP_NAME="func-recordh-prod"

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Create storage account
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS

# Create Function App
az functionapp create \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --consumption-plan-location $LOCATION \
  --runtime powershell \
  --runtime-version 7.2 \
  --functions-version 4 \
  --storage-account $STORAGE_ACCOUNT

echo "✅ Azure resources created successfully!"
echo "Function App: $FUNCTION_APP_NAME"
```

### Step 2: Configure OIDC for GitHub Actions

```bash
# Variables - customize these
GITHUB_ORG="your-github-username-or-org"
GITHUB_REPO="azfunc-powershell"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create Azure AD application
echo "Creating Azure AD application..."
APP_ID=$(az ad app create \
  --display-name "GitHub-Actions-${FUNCTION_APP_NAME}" \
  --query appId -o tsv)

echo "Application (client) ID: $APP_ID"

# Create service principal
echo "Creating service principal..."
az ad sp create --id $APP_ID

# Assign Contributor role to the service principal
echo "Assigning Contributor role..."
az role assignment create \
  --assignee $APP_ID \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP

# Create federated identity credential for main branch
echo "Creating federated credential for main branch..."
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-main-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"${GITHUB_ORG}/${GITHUB_REPO}"':ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"],
    "description": "GitHub Actions deployment from main branch"
  }'

echo "✅ OIDC configuration completed!"
echo ""
echo "Save these values for GitHub Secrets:"
echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "AZURE_FUNCTIONAPP_NAME=$FUNCTION_APP_NAME"
echo "AZURE_RESOURCE_GROUP=$RESOURCE_GROUP"
```

### Step 3: Configure GitHub Secrets

Navigate to your GitHub repository:
1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret** for each of the following:

#### Required Secrets for Azure OIDC Authentication:
```
AZURE_CLIENT_ID          # Application (client) ID from Step 2
AZURE_TENANT_ID          # Your Azure AD tenant ID
AZURE_SUBSCRIPTION_ID    # Your Azure subscription ID
AZURE_FUNCTIONAPP_NAME   # Name of your Function App
AZURE_RESOURCE_GROUP     # Name of your resource group
```

#### Required Secrets for Function Configuration:
```
ENTRA_CLIENT_ID          # Your Entra ID app registration client ID
ENTRA_TENANT_ID          # Your Entra ID tenant ID
ENTRA_AUDIENCE           # API audience (e.g., api://<client-id>)
ENTRA_CLIENT_SECRET      # Your Entra ID app client secret
REQUIRED_SCOPE           # Required scope (e.g., recordh.create)
```

### Step 4: (Optional) Create GitHub Environment

For additional security and approval gates:

1. Go to **Settings** → **Environments**
2. Click **New environment**
3. Name it `production`
4. Configure protection rules:
   - ✅ Required reviewers (add team members who should approve deployments)
   - ✅ Wait timer (optional delay before deployment)
   - ✅ Deployment branches (restrict to `main` branch only)
5. Add the same secrets to the environment (they'll override repository secrets)

### Step 5: Test the Deployment

#### Option 1: Push to main branch
```bash
git checkout main
git commit --allow-empty -m "Trigger deployment"
git push origin main
```

#### Option 2: Manual workflow dispatch
1. Go to **Actions** tab in GitHub
2. Select **Deploy Azure Function** workflow
3. Click **Run workflow**
4. Select branch and environment
5. Click **Run workflow**

#### Option 3: Using GitHub CLI
```bash
gh workflow run deploy.yml --ref main -f environment=production
```

## Workflow Overview

The GitHub Actions workflow (`.github/workflows/deploy.yml`) performs these steps:

1. **Checkout**: Clones the repository code
2. **Azure Login**: Authenticates using OIDC (no credentials stored)
3. **Prepare Package**: Creates a deployment zip with function files
4. **Deploy**: Uploads the package to Azure Function App
5. **Configure**: Sets application settings (Entra ID configuration)
6. **Verify**: Confirms deployment and displays Function App URL
7. **Logout**: Cleans up Azure session

### Workflow Triggers

- **Automatic**: Triggered on push to `main` branch
- **Manual**: Can be triggered via GitHub UI or CLI with environment selection

## Security Considerations

### OIDC Security Best Practices

1. **Scope Federated Credentials**: Create separate credentials for different branches/environments
   ```bash
   # Production (main branch)
   subject: "repo:org/repo:ref:refs/heads/main"
   
   # Staging (develop branch)
   subject: "repo:org/repo:ref:refs/heads/develop"
   
   # Pull requests
   subject: "repo:org/repo:pull_request"
   ```

2. **Use GitHub Environments**: Add approval gates for production deployments

3. **Minimal Permissions**: The workflow uses only required permissions:
   - `id-token: write` - For OIDC token exchange
   - `contents: read` - For code checkout

4. **Rotate Service Principal**: Although OIDC removes stored secrets, periodically verify:
   ```bash
   # List federated credentials
   az ad app federated-credential list --id $APP_ID
   
   # Remove unused credentials
   az ad app federated-credential delete --id $APP_ID --federated-credential-id <credential-id>
   ```

5. **Monitor Access**: Review Azure AD sign-in logs for unusual activity:
   ```bash
   az monitor activity-log list --resource-group $RESOURCE_GROUP
   ```

### Secret Management

- Store sensitive configuration (ENTRA_CLIENT_SECRET) in Azure Key Vault
- Use Key Vault references in Function App settings:
  ```bash
  az functionapp config appsettings set \
    --name $FUNCTION_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings ENTRA_CLIENT_SECRET="@Microsoft.KeyVault(SecretUri=https://vault.vault.azure.net/secrets/secret-name)"
  ```

### Branch Protection

Enable branch protection rules for `main`:
1. Go to **Settings** → **Branches**
2. Add rule for `main` branch
3. Enable:
   - ✅ Require pull request reviews
   - ✅ Require status checks to pass
   - ✅ Require branches to be up to date

## Troubleshooting

### OIDC Authentication Fails

**Error**: `Error: OIDC token exchange failed`

**Solutions**:
1. Verify federated credential subject matches exactly:
   ```bash
   az ad app federated-credential list --id $AZURE_CLIENT_ID
   ```
   Should show: `repo:<your-org>/<your-repo>:ref:refs/heads/main`

2. Check service principal has correct role:
   ```bash
   az role assignment list --assignee $AZURE_CLIENT_ID --resource-group $RESOURCE_GROUP
   ```

3. Verify GitHub secrets are set correctly:
   - AZURE_CLIENT_ID must match the application ID
   - AZURE_TENANT_ID must match your Azure AD tenant
   - AZURE_SUBSCRIPTION_ID must match your subscription

### Deployment Package Issues

**Error**: `Error: Failed to deploy`

**Solutions**:
1. Check the deployment package includes all required files:
   ```
   - host.json
   - profile.ps1
   - requirements.psd1
   - recordh/function.json
   - recordh/run.ps1
   ```

2. Verify package size is within limits (max 1.5 GB for zip deployment)

3. Check workflow logs for specific error messages

### Configuration Setting Failures

**Error**: `Error: Failed to set application settings`

**Solutions**:
1. Ensure all required secrets are set in GitHub
2. Verify service principal has permissions on the Function App
3. Check for typos in secret names

### Function Runtime Issues

**Error**: Function app not responding after deployment

**Solutions**:
1. Check Function App logs in Azure Portal:
   - Navigate to Function App → Monitor → Logs
   - Look for startup errors or module loading issues

2. Verify PowerShell runtime version:
   ```bash
   az functionapp config show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
   ```

3. Test the function endpoint:
   ```bash
   curl https://$FUNCTION_APP_NAME.azurewebsites.net/api/recordh
   ```

## Advanced Configuration

### Multiple Environments

To support staging and production environments:

1. Create separate Azure resources for each environment
2. Create separate GitHub environments with different secrets
3. Create additional federated credentials for staging branch:
   ```bash
   az ad app federated-credential create \
     --id $APP_ID \
     --parameters '{
       "name": "github-staging-branch",
       "subject": "repo:'"${GITHUB_ORG}/${GITHUB_REPO}"':ref:refs/heads/staging",
       "audiences": ["api://AzureADTokenExchange"]
     }'
   ```

### Custom Deployment Slots

For blue-green deployments:

1. Create a deployment slot:
   ```bash
   az functionapp deployment slot create \
     --name $FUNCTION_APP_NAME \
     --resource-group $RESOURCE_GROUP \
     --slot staging
   ```

2. Update workflow to deploy to slot, then swap:
   ```yaml
   - name: Deploy to Staging Slot
     uses: azure/webapps-deploy@v3
     with:
       app-name: ${{ secrets.AZURE_FUNCTIONAPP_NAME }}
       slot-name: staging
       package: deploy.zip
   
   - name: Swap Slots
     run: |
       az functionapp deployment slot swap \
         --name ${{ secrets.AZURE_FUNCTIONAPP_NAME }} \
         --resource-group ${{ secrets.AZURE_RESOURCE_GROUP }} \
         --slot staging
   ```

## Resources

- [GitHub Actions OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Azure AD Workload Identity Federation](https://docs.microsoft.com/azure/active-directory/develop/workload-identity-federation)
- [Azure Functions Deployment](https://docs.microsoft.com/azure/azure-functions/functions-deployment-technologies)
- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
