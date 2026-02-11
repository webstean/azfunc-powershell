using namespace System.Net

<#
.SYNOPSIS
    Azure Function health check endpoint for monitoring and diagnostics.

.DESCRIPTION
    This function provides a public health check endpoint that returns the operational
    status of the function app. It can be used by:
    - Azure Load Balancer health probes
    - Azure Application Gateway backend health checks
    - Kubernetes liveness and readiness probes
    - External monitoring services (Pingdom, StatusPage, etc.)
    - CI/CD pipelines for deployment validation
    
    The endpoint returns:
    - HTTP 200 OK when service is healthy
    - JSON response with status, version, and timestamp information
    - No authentication required (intentionally public for monitoring)

.SECURITY NOTES FOR PENETRATION TESTERS
    Authentication:
    - NO AUTHENTICATION REQUIRED (by design)
    - Health endpoints are typically public for monitoring purposes
    - Does not expose sensitive information (no secrets, tokens, or internal details)
    - Returns only basic operational status
    
    Information Disclosure:
    - Service name and version (non-sensitive)
    - Current timestamp (UTC)
    - Health status (healthy/unhealthy)
    - No user data, credentials, or internal system details
    
    Rate Limiting:
    - Consider implementing rate limiting via Azure API Management
    - Can be called frequently by monitoring systems
    - Lightweight operation with minimal resource usage
    
    Attack Surface:
    - Minimal attack surface (read-only operation)
    - No user input processed
    - No database or external service dependencies in basic implementation
    - No state modification

.OUTPUTS
    HTTP 200 OK with JSON body:
    {
        "status": "healthy",
        "service": "azfunc-powershell",
        "timestamp": "2024-02-11T22:00:00.000Z",
        "version": "1.0.0"
    }

.NOTES
    Best Practices:
    - Keep health checks lightweight and fast (<500ms response time)
    - Avoid expensive operations (database queries, external API calls)
    - Return 200 OK only when service can handle requests
    - Use 503 Service Unavailable for degraded state
    - Log health check failures for alerting
    
    For more information:
    https://docs.microsoft.com/azure/architecture/patterns/health-endpoint-monitoring
#>

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Log health check request (useful for monitoring frequency and patterns)
Write-Host "Health check requested from $($Request.Headers.'X-Forwarded-For' ?? 'unknown')"

try {
    # BASIC HEALTH CHECK
    # In production, you might want to add additional checks:
    # - Verify critical environment variables are set
    # - Check connectivity to dependent services
    # - Validate managed identity is working
    # - Verify required modules are loaded
    
    # For now, we perform a simple operational check
    $isHealthy = $true
    $healthStatus = "healthy"
    
    # OPTIONAL: Check if critical configuration exists
    # Uncomment to enable more robust health checking
    # if ([string]::IsNullOrEmpty($env:ENTRA_CLIENT_ID)) {
    #     $isHealthy = $false
    #     $healthStatus = "degraded"
    #     Write-Warning "ENTRA_CLIENT_ID environment variable is not set"
    # }
    
    # OPTIONAL: Check if required modules are available
    # Uncomment to verify module dependencies
    # if (-not (Get-Module -ListAvailable -Name "PnP.PowerShell")) {
    #     $isHealthy = $false
    #     $healthStatus = "degraded"
    #     Write-Warning "PnP.PowerShell module is not available"
    # }
    
    # Build health response with service metadata
    $responseBody = @{
        status = $healthStatus
        service = "azfunc-powershell"
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        version = "1.0.0"
    }
    
    # Determine HTTP status code based on health
    $statusCode = if ($isHealthy) { 
        [HttpStatusCode]::OK  # 200 - Service is healthy
    } else { 
        [HttpStatusCode]::ServiceUnavailable  # 503 - Service is degraded/unavailable
    }
    
    # Return health status response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $statusCode
        Headers = @{
            "Content-Type" = "application/json"
            "Cache-Control" = "no-cache, no-store, must-revalidate"
        }
        Body = ($responseBody | ConvertTo-Json)
    })
    
    Write-Host "Health check completed: $healthStatus"
}
catch {
    # If health check itself fails, return unhealthy status
    Write-Error "Health check failed: $($_.Exception.Message)"
    
    $errorResponse = @{
        status = "unhealthy"
        service = "azfunc-powershell"
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        error = "Health check execution failed"
    }
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::ServiceUnavailable
        Headers = @{
            "Content-Type" = "application/json"
            "Cache-Control" = "no-cache, no-store, must-revalidate"
        }
        Body = ($errorResponse | ConvertTo-Json)
    })
}
