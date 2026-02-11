# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every time a new PowerShell worker is started.
# You can use this file to initialize global variables or set up your environment.
#
# For more information, see:
# https://docs.microsoft.com/azure/azure-functions/functions-reference-powershell

# Authenticate with Azure PowerShell using MSI (when available).
if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity
}

# Import PnP PowerShell module if available
if (Get-Module -ListAvailable -Name "PnP.PowerShell") {
    Write-Host "PnP.PowerShell module is available"
}
