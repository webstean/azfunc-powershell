# Azure Function - PowerShell with Entra ID Authentication

This repository contains an Azure Function App built with PowerShell that provides a secure API endpoint for creating SharePoint sites. The function is protected with Microsoft Entra ID (formerly Azure AD) authentication and supports both application and delegated access patterns, including On-Behalf-Of (OBO) flows.

## Features

- ✅ **Entra ID Authentication**: Requires valid access tokens with proper scopes/roles
- ✅ **recordh.create Scope/Role**: Custom permission for SharePoint site creation
- ✅ **OBO Flow Support**: Enables delegated access for user-context operations
- ✅ **PnP PowerShell Integration**: Full support for SharePoint operations via PnP.PowerShell module
- ✅ **Extensible Architecture**: Easy to add more functions to the same Function App

## Project Structure

```
azfunc-powershell/
├── host.json                 # Azure Functions runtime configuration
├── profile.ps1              # PowerShell initialization script
├── requirements.psd1        # PowerShell module dependencies (Az, PnP.PowerShell)
├── local.settings.json      # Local development settings (not committed)
└── recordh/                 # HTTP-triggered function for SharePoint site creation
    ├── function.json        # Function binding configuration
    └── run.ps1              # Function implementation
```

## Prerequisites

- [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local) v4.x
- [PowerShell](https://docs.microsoft.com/powershell/scripting/install/installing-powershell) 7.2 or later
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (for deployment)
- An Azure subscription
- Microsoft Entra ID (Azure AD) tenant

## Entra ID App Registration

To use this function, you must register an application in Microsoft Entra ID:

### 1. Register the Application

```bash
az login
az ad app create --display-name "RecordH-API" --sign-in-audience AzureADMyOrg
```

Note the **Application (client) ID** and **Directory (tenant) ID** from the output.

### 2. Define App Roles (for Application Permissions)

Add an application role for service-to-service authentication:

```json
{
  "allowedMemberTypes": ["Application"],
  "description": "Allows creation of SharePoint sites via recordh API",
  "displayName": "recordh.create",
  "id": "<generate-a-guid>",
  "isEnabled": true,
  "value": "recordh.create"
}
```

### 3. Define API Scopes (for Delegated Permissions)

Expose an API scope for user delegation:

1. Go to **Azure Portal** → **Entra ID** → **App registrations** → Your app
2. Navigate to **Expose an API**
3. Add a scope:
   - **Scope name**: `recordh.create`
   - **Who can consent**: Admins and users
   - **Admin consent display name**: Create SharePoint sites
   - **Admin consent description**: Allows the application to create SharePoint sites on behalf of the user

### 4. Create a Client Secret (Required for OBO Flow)

```bash
az ad app credential reset --id <application-id>
```

Save the **client secret** securely - you'll need it for OBO flows.

### 5. Grant API Permissions

For the function to work with SharePoint, grant these Microsoft Graph permissions:
- `Sites.FullControl.All` (Application or Delegated)

For OBO scenarios, ensure your client applications are authorized to request tokens on behalf of users.

## Configuration

### Local Development

1. Copy `local.settings.json` template and update with your values:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "powershell",
    "FUNCTIONS_WORKER_RUNTIME_VERSION": "7.2",
    "ENTRA_CLIENT_ID": "<your-app-client-id>",
    "ENTRA_TENANT_ID": "<your-tenant-id>",
    "ENTRA_AUDIENCE": "api://<your-app-client-id>",
    "ENTRA_CLIENT_SECRET": "<your-client-secret>",
    "REQUIRED_SCOPE": "recordh.create"
  }
}
```

### Azure Deployment

When deploying to Azure, set these application settings:

```bash
az functionapp config appsettings set \
  --name <function-app-name> \
  --resource-group <resource-group> \
  --settings \
    ENTRA_CLIENT_ID="<your-app-client-id>" \
    ENTRA_TENANT_ID="<your-tenant-id>" \
    ENTRA_AUDIENCE="api://<your-app-client-id>" \
    ENTRA_CLIENT_SECRET="<your-client-secret>" \
    REQUIRED_SCOPE="recordh.create"
```

**Security Note**: Use Azure Key Vault references for sensitive values in production:
```
ENTRA_CLIENT_SECRET="@Microsoft.KeyVault(SecretUri=https://<vault>.vault.azure.net/secrets/<secret>)"
```

## Local Development

1. Install dependencies:

```bash
# Start Azure Functions Core Tools (will install PowerShell modules automatically)
func start
```

2. Test the endpoint locally:

```bash
curl -X POST http://localhost:7071/api/recordh \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"siteTitle": "My New Site", "siteAlias": "my-new-site"}'
```

## API Reference

### POST /api/recordh

Creates a new SharePoint site.

**Authentication**: Required (Bearer token with `recordh.create` scope/role)

**Request Headers**:
- `Authorization`: Bearer <access_token>
- `Content-Type`: application/json

**Request Body**:
```json
{
  "siteTitle": "Project Alpha",
  "siteAlias": "project-alpha",
  "tenantUrl": "https://contoso.sharepoint.com"
}
```

**Response (200 OK)**:
```json
{
  "success": true,
  "message": "SharePoint site creation initiated",
  "siteTitle": "Project Alpha",
  "accessType": "Delegated",
  "requestedBy": "user@contoso.com",
  "timestamp": "2024-02-11T21:23:00.000Z"
}
```

**Error Responses**:
- `401 Unauthorized`: Missing or invalid token, missing required scope/role
- `400 Bad Request`: Invalid request body or missing required parameters
- `500 Internal Server Error`: Site creation failed

## Authentication Types

### Application Authentication (Service-to-Service)

Used when a service needs to create sites without user context:

```bash
# Get access token using client credentials flow
curl -X POST https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token \
  -d "client_id=<client-id>" \
  -d "client_secret=<client-secret>" \
  -d "scope=api://<client-id>/.default" \
  -d "grant_type=client_credentials"
```

### Delegated Authentication (On-Behalf-Of User)

Used when acting on behalf of a signed-in user:

1. User authenticates to your app
2. Your app gets a token with `recordh.create` scope
3. Function validates the user's token
4. Function uses OBO to get SharePoint token with user's permissions

## OBO Flow Implementation

The function includes built-in support for On-Behalf-Of flows:

```powershell
# Automatically handles OBO for delegated access
$oboToken = Get-OBOToken -UserToken $authHeader -TargetResource "https://graph.microsoft.com"
```

This allows the function to:
- Preserve user context when accessing SharePoint
- Respect user's actual permissions
- Maintain audit trails with correct user attribution

## Deployment

### Automated Deployment with GitHub Actions (Recommended)

This repository includes a GitHub Actions workflow that uses OIDC (OpenID Connect) authentication to securely deploy to Azure without storing credentials.

#### Prerequisites

1. **Azure Resources**: Create the required Azure resources:

```bash
# Create resource group
az group create --name <resource-group> --location <region>

# Create storage account
az storage account create \
  --name <storage-account> \
  --resource-group <resource-group> \
  --location <region> \
  --sku Standard_LRS

# Create Function App
az functionapp create \
  --name <function-app-name> \
  --resource-group <resource-group> \
  --consumption-plan-location <region> \
  --runtime powershell \
  --runtime-version 7.2 \
  --functions-version 4 \
  --storage-account <storage-account>
```

2. **Configure OIDC for GitHub Actions**: Set up federated identity credentials to allow GitHub Actions to authenticate to Azure without secrets:

```bash
# Get your GitHub repository information
GITHUB_ORG="<your-github-org>"
GITHUB_REPO="<your-github-repo>"

# Create an Azure AD application for GitHub Actions
APP_ID=$(az ad app create \
  --display-name "GitHub-Actions-${GITHUB_REPO}" \
  --query appId -o tsv)

# Create a service principal
az ad sp create --id $APP_ID

# Get the service principal object ID
SP_OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

# Assign Contributor role to the service principal for the resource group
az role assignment create \
  --assignee $APP_ID \
  --role Contributor \
  --scope /subscriptions/<subscription-id>/resourceGroups/<resource-group>

# Create federated identity credential for the main branch
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-federated-credential",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"${GITHUB_ORG}/${GITHUB_REPO}"':ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# (Optional) Create federated credential for pull requests
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-pr-credential",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"${GITHUB_ORG}/${GITHUB_REPO}"':pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

3. **Configure GitHub Secrets**: Add the following secrets to your GitHub repository (Settings → Secrets and variables → Actions):

```
AZURE_CLIENT_ID=<application-client-id>
AZURE_TENANT_ID=<your-tenant-id>
AZURE_SUBSCRIPTION_ID=<your-subscription-id>
AZURE_FUNCTIONAPP_NAME=<function-app-name>
AZURE_RESOURCE_GROUP=<resource-group>

# Entra ID configuration for the function
ENTRA_CLIENT_ID=<your-entra-app-client-id>
ENTRA_TENANT_ID=<your-tenant-id>
ENTRA_AUDIENCE=api://<your-entra-app-client-id>
ENTRA_CLIENT_SECRET=<your-entra-client-secret>
REQUIRED_SCOPE=recordh.create
```

4. **Create GitHub Environment** (Optional but recommended):
   - Go to repository Settings → Environments
   - Create a `production` environment
   - Add protection rules (require reviewers, branch restrictions, etc.)
   - Add the secrets to this environment

#### Triggering Deployments

**Automatic deployment on push to main**:
```bash
git push origin main
```

**Manual deployment via GitHub UI**:
1. Go to Actions tab in your GitHub repository
2. Select "Deploy Azure Function" workflow
3. Click "Run workflow"
4. Choose the environment (production/staging)
5. Click "Run workflow"

**Manual deployment via GitHub CLI**:
```bash
gh workflow run deploy.yml --ref main -f environment=production
```

#### Monitoring Deployments

View deployment status:
- Navigate to the **Actions** tab in your GitHub repository
- Click on the workflow run to see detailed logs
- Each step shows execution status and output

### Manual Deployment with Azure Functions Core Tools

For local testing or one-time deployments:

1. Deploy the function code:

```bash
func azure functionapp publish <function-app-name>
```

2. Configure application settings:

```bash
az functionapp config appsettings set \
  --name <function-app-name> \
  --resource-group <resource-group> \
  --settings \
    ENTRA_CLIENT_ID="<your-app-client-id>" \
    ENTRA_TENANT_ID="<your-tenant-id>" \
    ENTRA_AUDIENCE="api://<your-app-client-id>" \
    ENTRA_CLIENT_SECRET="<your-client-secret>" \
    REQUIRED_SCOPE="recordh.create"
```

## Adding More Functions

This Function App is designed to be extensible. To add more functions:

1. Create a new folder (e.g., `myfunction/`)
2. Add `function.json` with binding configuration
3. Add `run.ps1` with function logic
4. Update authentication logic as needed

Example:
```bash
mkdir myfunction
# Create function.json and run.ps1
```

## Security Considerations

- ✅ All endpoints require authentication (authLevel: anonymous + manual token validation)
- ✅ Tokens are validated for audience, tenant, expiration, and required permissions
- ✅ Supports both application roles and delegated scopes
- ✅ OBO flow preserves user context for audit and permissions
- ✅ Use Azure Key Vault for storing secrets in production
- ✅ Enable Application Insights for monitoring and logging

### Important Security Notes

**JWT Signature Verification**: The current implementation validates JWT token claims (audience, tenant, expiration, scopes/roles) but does not perform cryptographic signature verification. This design is appropriate when:
- The function is deployed behind Azure API Management or Azure App Service Authentication/EasyAuth
- The function is used in internal/private scenarios where the token source is trusted

For external-facing APIs or additional security hardening, consider:
- Enabling Azure App Service Authentication (EasyAuth) to handle full token validation
- Implementing full JWT signature verification using Azure AD's JWKS endpoint
- Using a PowerShell JWT library that validates signatures

**Production Deployment Best Practices**:
- Always use HTTPS endpoints (enforced by Azure Functions)
- Store secrets in Azure Key Vault with Key Vault references
- Use Managed Identity instead of client secrets where possible
- Enable Azure Monitor and Application Insights for security monitoring
- Implement rate limiting to prevent abuse
- Regularly update PowerShell modules for security patches

**GitHub Actions Security**:
- ✅ Uses OIDC authentication (no long-lived credentials stored in GitHub)
- ✅ Federated identity credentials are scoped to specific repository and branches
- ✅ Secrets are stored in GitHub Secrets (encrypted at rest)
- ✅ Use GitHub Environments for additional protection (required reviewers, branch restrictions)
- ✅ Workflow has minimal permissions (`id-token: write`, `contents: read`)
- ⚠️ Regularly rotate Azure service principal credentials
- ⚠️ Review federated credential subjects to prevent unauthorized access

## Troubleshooting

### Token Validation Failures

- Verify `ENTRA_AUDIENCE` matches your app's identifier URI
- Ensure the token includes the required scope or role
- Check token expiration time

### Module Loading Issues

- Ensure `requirements.psd1` is properly formatted
- Check that managed dependencies are enabled in `host.json`
- Review function app logs for module installation errors

### OBO Flow Failures

- Verify `ENTRA_CLIENT_SECRET` is configured
- Ensure the client app is authorized for OBO
- Check that required API permissions are granted

### GitHub Actions Deployment Failures

**OIDC Authentication Issues**:
- Verify federated identity credential subject matches your repository
- Check that `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` secrets are set correctly
- Ensure the service principal has Contributor role on the resource group
- Verify the federated credential issuer is `https://token.actions.githubusercontent.com`

**Deployment Package Issues**:
- Ensure all required files (host.json, profile.ps1, requirements.psd1, function folders) are included
- Check GitHub Actions logs for file copy or zip errors
- Verify the deployment package size is within Azure limits

**Function App Configuration Issues**:
- Confirm all required secrets are set in GitHub (ENTRA_CLIENT_ID, ENTRA_TENANT_ID, etc.)
- Verify the Function App name and resource group are correct
- Check that the Function App is configured for PowerShell 7.2 runtime

## Resources

- [Azure Functions PowerShell Developer Guide](https://docs.microsoft.com/azure/azure-functions/functions-reference-powershell)
- [PnP PowerShell Documentation](https://pnp.github.io/powershell/)
- [Microsoft Entra ID Authentication](https://docs.microsoft.com/azure/active-directory/develop/)
- [On-Behalf-Of Flow](https://docs.microsoft.com/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow)

## License

[Specify your license here]