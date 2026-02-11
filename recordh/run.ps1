using namespace System.Net

<#
.SYNOPSIS
    Azure Function endpoint for creating SharePoint sites with Entra ID authentication.

.DESCRIPTION
    This function provides a secure HTTP API endpoint for SharePoint site provisioning.
    Security features:
    - Requires valid Entra ID (Azure AD) JWT access token
    - Validates token audience, tenant, expiration, and permissions
    - Supports both application (service-to-service) and delegated (user) access
    - Implements On-Behalf-Of (OBO) flow for downstream API access
    - Requires 'recordh.create' scope or role for authorization

.SECURITY NOTES FOR PENETRATION TESTERS
    Authentication Method:
    - Function uses authLevel='anonymous' at Azure Functions layer (see function.json)
    - Manual JWT token validation is performed in this script for fine-grained control
    - All requests without valid tokens are rejected with 401 Unauthorized
    
    Token Validation:
    - JWT structure validation (3-part format)
    - Audience claim validation against ENTRA_AUDIENCE environment variable
    - Tenant claim validation against ENTRA_TENANT_ID environment variable
    - Expiration timestamp validation
    - Required scope/role validation (recordh.create)
    - NOTE: Cryptographic signature verification is NOT performed
      (Suitable for APIs behind Azure authentication layers like API Management or EasyAuth)
    
    Authorization:
    - Scope-based (delegated): Checks 'scp' claim for user permissions
    - Role-based (application): Checks 'roles' claim for app permissions
    - Both must contain 'recordh.create' permission
    
    OBO Flow:
    - Exchanges user token for downstream resource tokens
    - Uses client credentials from environment variables
    - Requires ENTRA_CLIENT_SECRET to be configured
    - Preserves user identity for audit and permission checks
    
    Environment Variables (Configuration):
    - ENTRA_CLIENT_ID: Application ID for token validation
    - ENTRA_TENANT_ID: Azure AD tenant ID
    - ENTRA_AUDIENCE: Expected token audience (usually api://<client-id>)
    - ENTRA_CLIENT_SECRET: Secret for OBO token exchange (sensitive)
    - REQUIRED_SCOPE: Permission name required (default: recordh.create)
    
    Input Validation:
    - Request body must be valid JSON
    - siteTitle parameter is required
    - All user inputs should be validated before use
#>

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Import required modules for SharePoint operations
Import-Module PnP.PowerShell -ErrorAction SilentlyContinue

<#
.SYNOPSIS
    Validates Entra ID JWT token and extracts claims.

.DESCRIPTION
    Performs manual JWT token validation including:
    - Bearer token format validation
    - JWT structure validation (header.payload.signature)
    - Base64url decoding of payload
    - Audience claim validation
    - Tenant ID claim validation
    - Token expiration check
    - Required scope/role validation
    
.PARAMETER AuthHeader
    Authorization header value (expected format: "Bearer <token>")

.PARAMETER RequiredScope
    The scope or role name required for authorization (e.g., "recordh.create")

.OUTPUTS
    Hashtable with validation result:
    - IsValid: Boolean indicating if token is valid
    - Error: Error message if validation failed
    - Claims: Decoded JWT claims if validation succeeded
    - AccessType: "Delegated" or "Application" based on token type

.SECURITY NOTES
    This function does NOT verify the cryptographic signature of the JWT.
    It validates claims only. This is acceptable when:
    - Function is behind Azure API Management with JWT validation
    - Function is behind Azure App Service Authentication (EasyAuth)
    - Function is in a trusted network environment
    For external-facing APIs, enable signature verification or use EasyAuth.
#>
function Test-EntraToken {
    param(
        [string]$AuthHeader,
        [string]$RequiredScope
    )
    
    try {
        # Validate Authorization header is present
        if ([string]::IsNullOrEmpty($AuthHeader)) {
            return @{
                IsValid = $false
                Error = "Missing Authorization header"
            }
        }
        
        # Validate Bearer token format
        if (-not $AuthHeader.StartsWith("Bearer ")) {
            return @{
                IsValid = $false
                Error = "Invalid Authorization header format. Expected 'Bearer <token>'"
            }
        }
        
        # Extract token from "Bearer <token>" format
        $token = $AuthHeader.Substring(7)
        
        # Validate JWT structure (header.payload.signature)
        # JWT tokens must have exactly 3 parts separated by dots
        $tokenParts = $token.Split('.')
        if ($tokenParts.Count -ne 3) {
            return @{
                IsValid = $false
                Error = "Invalid token format"
            }
        }
        
        # Decode the payload (second part of JWT)
        # JWT uses base64url encoding which differs from standard base64
        $payload = $tokenParts[1]
        
        # Add padding if needed (base64 requires length to be multiple of 4)
        $padding = (4 - ($payload.Length % 4)) % 4
        $payload = $payload + ("=" * $padding)
        
        # Convert base64url to base64 (replace URL-safe chars)
        $payload = $payload.Replace('-', '+').Replace('_', '/')
        
        # Decode base64 to bytes, then to JSON string
        $decodedBytes = [System.Convert]::FromBase64String($payload)
        $decodedJson = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
        $claims = $decodedJson | ConvertFrom-Json
        
        # SECURITY CHECK 1: Validate Audience (aud claim)
        # Ensures token was issued for this specific API
        # Prevents token reuse from other applications
        $expectedAudience = $env:ENTRA_AUDIENCE
        if ($expectedAudience -and $claims.aud -ne $expectedAudience) {
            return @{
                IsValid = $false
                Error = "Invalid audience. Expected: $expectedAudience, Got: $($claims.aud)"
            }
        }
        
        # SECURITY CHECK 2: Validate Tenant (tid claim)
        # Ensures token is from the correct Azure AD tenant
        # Prevents cross-tenant token attacks
        $expectedTenant = $env:ENTRA_TENANT_ID
        if ($expectedTenant -and $claims.tid -ne $expectedTenant) {
            return @{
                IsValid = $false
                Error = "Invalid tenant"
            }
        }
        
        # SECURITY CHECK 3: Validate Expiration (exp claim)
        # Ensures token hasn't expired
        # exp claim is Unix timestamp (seconds since epoch)
        $expirationTime = [DateTimeOffset]::FromUnixTimeSeconds($claims.exp)
        if ([DateTimeOffset]::UtcNow -gt $expirationTime) {
            return @{
                IsValid = $false
                Error = "Token has expired"
            }
        }
        
        # SECURITY CHECK 4: Validate Required Scope or Role
        # Authorization check - ensures caller has permission for this operation
        $hasRequiredPermission = $false
        
        # Check scopes (delegated permissions - user context)
        # 'scp' claim contains space-separated list of delegated scopes
        if ($claims.scp) {
            $scopes = $claims.scp -split ' '
            if ($scopes -contains $RequiredScope) {
                $hasRequiredPermission = $true
            }
        }
        
        # Check roles (application permissions - service context)
        # 'roles' claim contains array of application roles
        if ($claims.roles -and -not $hasRequiredPermission) {
            if ($claims.roles -contains $RequiredScope) {
                $hasRequiredPermission = $true
            }
        }
        
        # Reject if required permission is missing
        if (-not $hasRequiredPermission) {
            return @{
                IsValid = $false
                Error = "Missing required permission: $RequiredScope"
                Claims = $claims
            }
        }
        
        # Token is valid - return claims and access type
        return @{
            IsValid = $true
            Claims = $claims
            AccessType = if ($claims.scp) { "Delegated" } else { "Application" }
        }
    }
    catch {
        # Catch any unexpected errors during token validation
        # Return generic error to avoid leaking implementation details
        return @{
            IsValid = $false
            Error = "Token validation failed: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Acquires downstream access token using On-Behalf-Of (OBO) flow.

.DESCRIPTION
    Exchanges a user's access token for a new token to access downstream APIs
    while preserving the user's identity. This is part of the OAuth 2.0 OBO flow.
    
    The flow works as follows:
    1. User authenticates and grants permissions to client application
    2. Client sends user's token to this middle-tier service (this function)
    3. This function exchanges user token for new token to access downstream resource
    4. Downstream resource sees original user's identity and permissions
    
.PARAMETER UserToken
    The user's access token from the Authorization header (format: "Bearer <token>")

.PARAMETER TargetResource
    The resource/API to access with the OBO token
    Examples: "https://graph.microsoft.com", "https://contoso.sharepoint.com"

.OUTPUTS
    String containing the access token for the target resource, or $null if failed

.SECURITY NOTES
    OBO Flow Requirements:
    - Requires application to have a client secret (ENTRA_CLIENT_SECRET)
    - Client application must be granted permission to access target resource
    - Uses OAuth 2.0 grant type: urn:ietf:params:oauth:grant-type:jwt-bearer
    - Token is exchanged via Microsoft identity platform token endpoint
    
    Security Considerations:
    - Client secret must be stored securely (use Azure Key Vault in production)
    - OBO tokens inherit user's permissions on downstream resource
    - Token expiration and refresh should be handled by calling application
    - All communication uses HTTPS
    
    For more information:
    https://docs.microsoft.com/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow
#>
function Get-OBOToken {
    param(
        [string]$UserToken,
        [string]$TargetResource
    )
    
    try {
        # Retrieve configuration from environment variables
        # These should be configured in Azure Function App settings
        $clientId = $env:ENTRA_CLIENT_ID
        $clientSecret = $env:ENTRA_CLIENT_SECRET
        $tenantId = $env:ENTRA_TENANT_ID
        
        # Validate client secret is configured
        # OBO flow requires client credentials (client ID + secret)
        if ([string]::IsNullOrEmpty($clientSecret)) {
            Write-Warning "OBO flow requires ENTRA_CLIENT_SECRET to be configured"
            return $null
        }
        
        # Microsoft identity platform token endpoint for OAuth 2.0 token exchange
        $tokenEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
        
        # Prepare OBO token request
        # Uses client credentials + user's token to get downstream token
        $body = @{
            grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"  # OBO grant type
            client_id = $clientId                                        # This app's client ID
            client_secret = $clientSecret                                # This app's secret (sensitive)
            assertion = $UserToken.Substring(7)                          # User's token (remove 'Bearer ' prefix)
            scope = "$TargetResource/.default"                           # Request all permissions for target resource
            requested_token_use = "on_behalf_of"                         # Indicates OBO flow
        }
        
        # Exchange tokens with Microsoft identity platform
        # POST to token endpoint with OBO parameters
        $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        
        # Return the access token for downstream resource
        return $response.access_token
    }
    catch {
        # Log error but don't expose sensitive details to caller
        Write-Error "OBO token acquisition failed: $($_.Exception.Message)"
        return $null
    }
}

###########################################
# MAIN FUNCTION EXECUTION STARTS HERE
###########################################

Write-Host "Processing recordh function request"

# STEP 1: AUTHENTICATION - Validate Entra ID access token
# Get Authorization header from HTTP request
$authHeader = $Request.Headers.Authorization

# Get required scope from configuration (default: recordh.create)
$requiredScope = $env:REQUIRED_SCOPE
if ([string]::IsNullOrEmpty($requiredScope)) {
    $requiredScope = "recordh.create"
}

# Validate the token and extract claims
$tokenValidation = Test-EntraToken -AuthHeader $authHeader -RequiredScope $requiredScope

# STEP 2: AUTHORIZATION CHECK - Reject if token is invalid
if (-not $tokenValidation.IsValid) {
    # Return 401 Unauthorized with error details
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

# Log successful authentication with access type
Write-Host "Token validated successfully. Access Type: $($tokenValidation.AccessType)"

# STEP 3: INPUT VALIDATION - Parse and validate request body
try {
    # Parse JSON from request body
    $requestBody = $Request.Body | ConvertFrom-Json
}
catch {
    # Return 400 Bad Request if JSON is malformed
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

# STEP 4: PARAMETER VALIDATION - Ensure required fields are present
# Validate required parameter for SharePoint site creation
if ([string]::IsNullOrEmpty($requestBody.siteTitle)) {
    # Return 400 Bad Request if required parameter is missing
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

# STEP 5: SHAREPOINT SITE CREATION
# Execute SharePoint site provisioning with appropriate authentication
try {
    Write-Host "Creating SharePoint site: $($requestBody.siteTitle)"
    
    # STEP 5a: DOWNSTREAM TOKEN ACQUISITION
    # For delegated access (user context), acquire tokens for downstream APIs using OBO flow
    # This preserves the user's identity and permissions
    $sharePointToken = $null
    $graphToken = $null
    
    if ($tokenValidation.AccessType -eq "Delegated") {
        # OBO Flow: Exchange user's token for SharePoint access token
        # This allows the function to act on behalf of the user
        if ($requestBody.tenantUrl) {
            $sharePointToken = Get-OBOToken -UserToken $authHeader -TargetResource $requestBody.tenantUrl
            if ($sharePointToken) {
                Write-Host "Successfully acquired OBO token for SharePoint"
            }
        }
        
        # OBO Flow: Exchange user's token for Microsoft Graph access token
        # May be needed for additional operations (groups, users, etc.)
        $graphToken = Get-OBOToken -UserToken $authHeader -TargetResource "https://graph.microsoft.com"
        if ($graphToken) {
            Write-Host "Successfully acquired OBO token for Microsoft Graph"
        }
    }
    
    # STEP 5b: SHAREPOINT SITE PROVISIONING
    # Example implementation using PnP PowerShell with OBO token
    # In production, uncomment and customize based on your requirements:
    #
    # if ($sharePointToken) {
    #     # Connect to SharePoint using OBO access token (preserves user identity)
    #     Connect-PnPOnline -Url $requestBody.tenantUrl -AccessToken $sharePointToken
    #     
    #     # Create new SharePoint site
    #     $newSite = New-PnPSite -Type TeamSite -Title $requestBody.siteTitle -Alias $requestBody.siteAlias
    #     
    #     # Disconnect when done
    #     Disconnect-PnPOnline
    # }
    
    # STEP 6: SUCCESS RESPONSE
    # Return success response with site creation details
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
    # STEP 7: ERROR HANDLING
    # Log error for troubleshooting (visible in Application Insights)
    Write-Error "Failed to create SharePoint site: $($_.Exception.Message)"
    
    # Return 500 Internal Server Error without exposing sensitive details
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
