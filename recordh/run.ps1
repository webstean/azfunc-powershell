using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Import required modules
Import-Module PnP.PowerShell -ErrorAction SilentlyContinue

# Function to validate Entra ID token and extract claims
function Test-EntraToken {
    param(
        [string]$AuthHeader,
        [string]$RequiredScope
    )
    
    try {
        if ([string]::IsNullOrEmpty($AuthHeader)) {
            return @{
                IsValid = $false
                Error = "Missing Authorization header"
            }
        }
        
        if (-not $AuthHeader.StartsWith("Bearer ")) {
            return @{
                IsValid = $false
                Error = "Invalid Authorization header format. Expected 'Bearer <token>'"
            }
        }
        
        $token = $AuthHeader.Substring(7)
        
        # Decode JWT token (base64url decode the payload)
        $tokenParts = $token.Split('.')
        if ($tokenParts.Count -ne 3) {
            return @{
                IsValid = $false
                Error = "Invalid token format"
            }
        }
        
        # Decode the payload (second part)
        $payload = $tokenParts[1]
        # Add padding if needed
        $padding = (4 - ($payload.Length % 4)) % 4
        $payload = $payload + ("=" * $padding)
        $payload = $payload.Replace('-', '+').Replace('_', '/')
        
        $decodedBytes = [System.Convert]::FromBase64String($payload)
        $decodedJson = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
        $claims = $decodedJson | ConvertFrom-Json
        
        # Validate audience
        $expectedAudience = $env:ENTRA_AUDIENCE
        if ($expectedAudience -and $claims.aud -ne $expectedAudience) {
            return @{
                IsValid = $false
                Error = "Invalid audience. Expected: $expectedAudience, Got: $($claims.aud)"
            }
        }
        
        # Validate tenant
        $expectedTenant = $env:ENTRA_TENANT_ID
        if ($expectedTenant -and $claims.tid -ne $expectedTenant) {
            return @{
                IsValid = $false
                Error = "Invalid tenant"
            }
        }
        
        # Validate expiration
        $expirationTime = [DateTimeOffset]::FromUnixTimeSeconds($claims.exp)
        if ([DateTimeOffset]::UtcNow -gt $expirationTime) {
            return @{
                IsValid = $false
                Error = "Token has expired"
            }
        }
        
        # Check for required scope or role
        $hasRequiredPermission = $false
        
        # Check scopes (delegated permissions)
        if ($claims.scp) {
            $scopes = $claims.scp -split ' '
            if ($scopes -contains $RequiredScope) {
                $hasRequiredPermission = $true
            }
        }
        
        # Check roles (application permissions)
        if ($claims.roles -and -not $hasRequiredPermission) {
            if ($claims.roles -contains $RequiredScope) {
                $hasRequiredPermission = $true
            }
        }
        
        if (-not $hasRequiredPermission) {
            return @{
                IsValid = $false
                Error = "Missing required permission: $RequiredScope"
                Claims = $claims
            }
        }
        
        return @{
            IsValid = $true
            Claims = $claims
            AccessType = if ($claims.scp) { "Delegated" } else { "Application" }
        }
    }
    catch {
        return @{
            IsValid = $false
            Error = "Token validation failed: $($_.Exception.Message)"
        }
    }
}

# Function to handle OBO (On-Behalf-Of) flow
function Get-OBOToken {
    param(
        [string]$UserToken,
        [string]$TargetResource
    )
    
    try {
        $clientId = $env:ENTRA_CLIENT_ID
        $clientSecret = $env:ENTRA_CLIENT_SECRET
        $tenantId = $env:ENTRA_TENANT_ID
        
        if ([string]::IsNullOrEmpty($clientSecret)) {
            Write-Warning "OBO flow requires ENTRA_CLIENT_SECRET to be configured"
            return $null
        }
        
        $tokenEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
        
        $body = @{
            grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"
            client_id = $clientId
            client_secret = $clientSecret
            assertion = $UserToken.Substring(7)  # Remove 'Bearer ' prefix
            scope = "$TargetResource/.default"
            requested_token_use = "on_behalf_of"
        }
        
        $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        
        return $response.access_token
    }
    catch {
        Write-Error "OBO token acquisition failed: $($_.Exception.Message)"
        return $null
    }
}

# Main function logic
Write-Host "Processing recordh function request"

# Validate authentication
$authHeader = $Request.Headers.Authorization
$requiredScope = $env:REQUIRED_SCOPE
if ([string]::IsNullOrEmpty($requiredScope)) {
    $requiredScope = "recordh.create"
}

$tokenValidation = Test-EntraToken -AuthHeader $authHeader -RequiredScope $requiredScope

if (-not $tokenValidation.IsValid) {
    $errorResponse = @{
        error = "Unauthorized"
        message = $tokenValidation.Error
    }
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Headers = @{
            "Content-Type" = "application/json"
        }
        Body = ($errorResponse | ConvertTo-Json)
    })
    return
}

Write-Host "Token validated successfully. Access Type: $($tokenValidation.AccessType)"

# Parse request body
try {
    $requestBody = $Request.Body | ConvertFrom-Json
}
catch {
    $errorResponse = @{
        error = "Bad Request"
        message = "Invalid JSON in request body"
    }
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Headers = @{
            "Content-Type" = "application/json"
        }
        Body = ($errorResponse | ConvertTo-Json)
    })
    return
}

# Validate required parameters for SharePoint site creation
if ([string]::IsNullOrEmpty($requestBody.siteTitle)) {
    $errorResponse = @{
        error = "Bad Request"
        message = "Missing required parameter: siteTitle"
    }
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Headers = @{
            "Content-Type" = "application/json"
        }
        Body = ($errorResponse | ConvertTo-Json)
    })
    return
}

# Example: Create SharePoint site using PnP PowerShell
# Note: In production, you would need to authenticate to SharePoint using either:
# 1. Managed Identity
# 2. Certificate-based authentication
# 3. OBO token for delegated access
try {
    Write-Host "Creating SharePoint site: $($requestBody.siteTitle)"
    
    # For OBO flow with delegated access, acquire downstream tokens
    $sharePointToken = $null
    $graphToken = $null
    
    if ($tokenValidation.AccessType -eq "Delegated") {
        # Get SharePoint token for PnP operations (if tenantUrl is provided)
        if ($requestBody.tenantUrl) {
            $sharePointToken = Get-OBOToken -UserToken $authHeader -TargetResource $requestBody.tenantUrl
            if ($sharePointToken) {
                Write-Host "Successfully acquired OBO token for SharePoint"
            }
        }
        
        # Get Microsoft Graph token if needed for additional operations
        $graphToken = Get-OBOToken -UserToken $authHeader -TargetResource "https://graph.microsoft.com"
        if ($graphToken) {
            Write-Host "Successfully acquired OBO token for Microsoft Graph"
        }
    }
    
    # Example site creation logic using PnP PowerShell with OBO token
    # if ($sharePointToken) {
    #     Connect-PnPOnline -Url $requestBody.tenantUrl -AccessToken $sharePointToken
    #     $newSite = New-PnPSite -Type TeamSite -Title $requestBody.siteTitle -Alias $requestBody.siteAlias
    # }
    
    $responseBody = @{
        success = $true
        message = "SharePoint site creation initiated"
        siteTitle = $requestBody.siteTitle
        accessType = $tokenValidation.AccessType
        requestedBy = $tokenValidation.Claims.upn ?? $tokenValidation.Claims.appid
        timestamp = (Get-Date).ToString("o")
    }
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers = @{
            "Content-Type" = "application/json"
        }
        Body = ($responseBody | ConvertTo-Json)
    })
}
catch {
    Write-Error "Failed to create SharePoint site: $($_.Exception.Message)"
    
    $errorResponse = @{
        error = "Internal Server Error"
        message = "Failed to create SharePoint site: $($_.Exception.Message)"
    }
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Headers = @{
            "Content-Type" = "application/json"
        }
        Body = ($errorResponse | ConvertTo-Json)
    })
}
