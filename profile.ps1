<#
.SYNOPSIS
    Azure Functions profile script for PowerShell runtime initialization.

.DESCRIPTION
    This script executes once when a new PowerShell worker process is started.
    It sets up the execution environment, authenticates with Azure services,
    and initializes required PowerShell modules.
    
    Use this file to:
    - Configure Azure authentication (Managed Identity)
    - Import PowerShell modules
    - Set environment variables
    - Initialize global resources
    
.SECURITY NOTES FOR PENETRATION TESTERS
    Managed Identity Authentication:
    - Uses MSI_SECRET environment variable (injected by Azure runtime)
    - Authenticates using system-assigned or user-assigned managed identity
    - No credentials stored in code or configuration
    - Identity permissions managed through Azure RBAC
    
    Module Loading:
    - PnP.PowerShell: SharePoint/Microsoft 365 operations
    - Az modules: Azure resource management
    - Modules installed via managed dependencies (requirements.psd1)
    
    Security Considerations:
    - Script runs with function app's managed identity permissions
    - Disable-AzContextAutosave prevents credential caching across invocations
    - Module availability check ensures dependencies are loaded
    
.NOTES
    For more information:
    https://docs.microsoft.com/azure/azure-functions/functions-reference-powershell
#>

# Authenticate with Azure PowerShell using Managed Identity (MSI)
# MSI_SECRET is automatically provided by Azure Functions runtime when managed identity is enabled
if ($env:MSI_SECRET) {
    # Disable context autosave to prevent credential persistence across function invocations
    # This ensures each invocation uses fresh credentials and improves security
    Disable-AzContextAutosave -Scope Process | Out-Null
    
    # Connect to Azure using the function app's managed identity
    # This provides access to Azure resources without storing credentials
    Connect-AzAccount -Identity
}

# Verify PnP PowerShell module availability
# This module is required for SharePoint operations
# Loaded via managed dependencies from requirements.psd1
if (Get-Module -ListAvailable -Name "PnP.PowerShell") {
    Write-Host "PnP.PowerShell module is available"
}
