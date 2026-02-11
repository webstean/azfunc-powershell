<#
.SYNOPSIS
    PowerShell module dependency manifest for Azure Functions managed dependencies.

.DESCRIPTION
    This file declares PowerShell modules required by the function app.
    Azure Functions automatically downloads and installs these modules when
    managed dependencies are enabled in host.json.
    
    Module Management:
    - Modules are installed from PowerShell Gallery
    - Version constraints ensure compatibility and stability
    - Modules are cached per function app instance
    - Updates occur during cold starts when versions change
    
.SECURITY NOTES FOR PENETRATION TESTERS
    Module Sources:
    - All modules sourced from official PowerShell Gallery (https://www.powershellgallery.com)
    - Version constraints prevent unexpected updates
    - Microsoft-signed modules (Az, PnP.PowerShell)
    
    Declared Modules:
    1. Az (Azure PowerShell SDK)
       - Version: 11.x (latest patch in major version 11)
       - Purpose: Azure resource management, authentication
       - Authentication: Managed Identity
       
    2. PnP.PowerShell (SharePoint PnP PowerShell)
       - Version: 2.x (latest patch in major version 2)
       - Purpose: SharePoint and Microsoft 365 operations
       - Repository: https://github.com/pnp/powershell
       
    Security Considerations:
    - Module integrity verified by PowerShell Gallery
    - Versions pinned to major releases for stability
    - Regular updates required for security patches
    - Consider scanning modules for vulnerabilities
    
.NOTES
    For more information:
    https://aka.ms/functionsmanageddependency
    https://www.powershellgallery.com/packages/Az
    https://pnp.github.io/powershell/
#>

@{
    # Azure PowerShell SDK - For Azure resource management and authentication
    # Used for Managed Identity authentication and Azure service interactions
    # Version 11.x includes latest security patches and features
    'Az' = '11.*'
    
    # PnP PowerShell - For SharePoint and Microsoft 365 operations
    # Used for SharePoint site provisioning and management
    # Version 2.x is the latest stable release with Graph API support
    'PnP.PowerShell' = '2.*'
}
