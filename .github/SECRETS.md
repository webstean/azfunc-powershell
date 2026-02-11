# GitHub Actions Secrets Configuration

This file lists all the secrets required for the GitHub Actions deployment workflow.

## Required Secrets

Navigate to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret

### Azure OIDC Authentication Secrets

These secrets are used for authenticating GitHub Actions to Azure using OpenID Connect (OIDC):

| Secret Name | Description | Example Value | Where to Find |
|------------|-------------|---------------|---------------|
| `AZURE_CLIENT_ID` | Application (client) ID of the Azure AD app | `12345678-1234-1234-1234-123456789012` | Azure Portal → Azure Active Directory → App registrations → Your app → Overview |
| `AZURE_TENANT_ID` | Azure Active Directory tenant ID | `87654321-4321-4321-4321-210987654321` | Azure Portal → Azure Active Directory → Overview → Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | `abcdef12-ab12-ab12-ab12-abcdef123456` | Azure Portal → Subscriptions → Your subscription |
| `AZURE_FUNCTIONAPP_NAME` | Name of your Azure Function App | `func-recordh-prod` | Azure Portal → Function Apps → Your function app name |
| `AZURE_RESOURCE_GROUP` | Azure resource group name | `rg-azfunc-powershell` | Azure Portal → Resource groups → Your resource group |

### Function App Configuration Secrets

These secrets are used to configure the Azure Function App at deployment time:

| Secret Name | Description | Example Value | Where to Find |
|------------|-------------|---------------|---------------|
| `ENTRA_CLIENT_ID` | Entra ID app registration client ID for the function | `11111111-1111-1111-1111-111111111111` | Azure Portal → Azure Active Directory → App registrations → Your RecordH app → Overview |
| `ENTRA_TENANT_ID` | Entra ID tenant ID | `87654321-4321-4321-4321-210987654321` | Same as AZURE_TENANT_ID |
| `ENTRA_AUDIENCE` | Expected audience in JWT tokens | `api://11111111-1111-1111-1111-111111111111` | Format: `api://<ENTRA_CLIENT_ID>` |
| `ENTRA_CLIENT_SECRET` | Entra ID app client secret | `your-client-secret-value` | Azure Portal → Azure Active Directory → App registrations → Your RecordH app → Certificates & secrets |
| `REQUIRED_SCOPE` | Required scope for API access | `recordh.create` | Defined in your Entra ID app's exposed API |

## Quick Setup Script

You can use this script to set all secrets at once using GitHub CLI:

```bash
# Set your values here
AZURE_CLIENT_ID="your-azure-client-id"
AZURE_TENANT_ID="your-tenant-id"
AZURE_SUBSCRIPTION_ID="your-subscription-id"
AZURE_FUNCTIONAPP_NAME="your-function-app-name"
AZURE_RESOURCE_GROUP="your-resource-group"
ENTRA_CLIENT_ID="your-entra-client-id"
ENTRA_TENANT_ID="your-entra-tenant-id"
ENTRA_AUDIENCE="api://your-entra-client-id"
ENTRA_CLIENT_SECRET="your-entra-client-secret"
REQUIRED_SCOPE="recordh.create"

# Set secrets using GitHub CLI
gh secret set AZURE_CLIENT_ID -b"$AZURE_CLIENT_ID"
gh secret set AZURE_TENANT_ID -b"$AZURE_TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID -b"$AZURE_SUBSCRIPTION_ID"
gh secret set AZURE_FUNCTIONAPP_NAME -b"$AZURE_FUNCTIONAPP_NAME"
gh secret set AZURE_RESOURCE_GROUP -b"$AZURE_RESOURCE_GROUP"
gh secret set ENTRA_CLIENT_ID -b"$ENTRA_CLIENT_ID"
gh secret set ENTRA_TENANT_ID -b"$ENTRA_TENANT_ID"
gh secret set ENTRA_AUDIENCE -b"$ENTRA_AUDIENCE"
gh secret set ENTRA_CLIENT_SECRET -b"$ENTRA_CLIENT_SECRET"
gh secret set REQUIRED_SCOPE -b"$REQUIRED_SCOPE"

echo "✅ All secrets configured successfully!"
```

## Verifying Secrets

To verify that all secrets are set:

```bash
gh secret list
```

Expected output:
```
AZURE_CLIENT_ID          Updated YYYY-MM-DD
AZURE_FUNCTIONAPP_NAME   Updated YYYY-MM-DD
AZURE_RESOURCE_GROUP     Updated YYYY-MM-DD
AZURE_SUBSCRIPTION_ID    Updated YYYY-MM-DD
AZURE_TENANT_ID          Updated YYYY-MM-DD
ENTRA_AUDIENCE           Updated YYYY-MM-DD
ENTRA_CLIENT_ID          Updated YYYY-MM-DD
ENTRA_CLIENT_SECRET      Updated YYYY-MM-DD
ENTRA_TENANT_ID          Updated YYYY-MM-DD
REQUIRED_SCOPE           Updated YYYY-MM-DD
```

## Environment-Specific Secrets (Optional)

If you're using GitHub Environments (recommended for production):

1. Go to Settings → Environments
2. Create an environment (e.g., "production")
3. Add the same secrets to the environment
4. Environment secrets override repository secrets

This allows you to have different configurations for staging and production environments.

## Security Best Practices

1. **Never commit secrets to the repository** - Always use GitHub Secrets
2. **Use Azure Key Vault** - For production, store secrets in Azure Key Vault and use Key Vault references:
   ```bash
   az functionapp config appsettings set \
     --settings ENTRA_CLIENT_SECRET="@Microsoft.KeyVault(SecretUri=https://your-vault.vault.azure.net/secrets/secret-name)"
   ```
3. **Rotate secrets regularly** - Especially client secrets
4. **Use Managed Identity** - When possible, use Managed Identity instead of client secrets
5. **Audit access** - Regularly review who has access to your repository and secrets
6. **Minimum permissions** - Ensure the Azure service principal has only the necessary permissions

## Troubleshooting

### Secret not found error
- Ensure the secret name matches exactly (case-sensitive)
- Verify the secret is set at the repository or environment level
- Check that your GitHub Actions workflow has permission to access secrets

### Secret value issues
- Ensure no leading/trailing spaces in secret values
- For URLs, don't include quotes unless they're part of the actual value
- Client secrets may need to be regenerated if expired

## Additional Resources

- [GitHub Secrets Documentation](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Azure Key Vault Integration](https://docs.microsoft.com/azure/app-service/app-service-key-vault-references)
- [OIDC Setup Guide](./DEPLOYMENT.md)
