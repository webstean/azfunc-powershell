# host.json Configuration Documentation

## Purpose
This file configures the Azure Functions runtime behavior for the entire function app.
It applies to all functions within the app.

## Security and Operational Configuration

### Version
- `version: "2.0"` - Azure Functions runtime version 2.x/3.x/4.x configuration schema
- Version 2.0 schema required for modern features and security capabilities

### Logging Configuration
Logging controls what information is captured and sent to monitoring services.

**Log Levels:**
- `default: "Information"` - Captures informational messages, warnings, and errors
- `Function: "Information"` - Function execution logs at Information level
- Available levels: Trace, Debug, Information, Warning, Error, Critical, None

**Security Consideration:** Log levels control verbosity. Avoid "Trace" or "Debug" in production
as they may log sensitive data. "Information" provides good balance for security monitoring.

**Application Insights Integration:**
```json
"applicationInsights": {
  "samplingSettings": {
    "isEnabled": true,
    "maxTelemetryItemsPerSecond": 20
  }
}
```
- Sampling reduces telemetry volume and cost
- 20 items/second provides adequate monitoring without overwhelming Application Insights
- All security-relevant events should still be captured
- Used for detecting anomalies, unauthorized access attempts, and performance issues

### Function Timeout
```json
"functionTimeout": "00:10:00"
```
- Maximum execution time: 10 minutes (00:10:00)
- Prevents runaway functions that could consume excessive resources
- SharePoint operations may take time, hence longer timeout
- Default is 5 minutes; extended for site provisioning operations
- **Security Note:** Timeout prevents DoS via long-running requests

### HTTP Extension Configuration
```json
"extensions": {
  "http": {
    "routePrefix": "api"
  }
}
```
- All HTTP functions are exposed under `/api` prefix
- Example: recordh function accessible at `/api/recordh`
- Provides consistent API routing and easier API gateway integration
- **Security Note:** Route prefix helps with API Management policies and WAF rules

### Managed Dependencies
```json
"managedDependency": {
  "Enabled": true
}
```
- Enables automatic PowerShell module management from requirements.psd1
- Modules downloaded from PowerShell Gallery during cold starts
- Reduces deployment package size
- Ensures modules are available in function runtime
- **Security Note:** Only use trusted modules from official sources

## Security Considerations for Penetration Testing

1. **Monitoring and Alerting:**
   - Application Insights captures all function invocations
   - Failed authentication attempts logged at Warning level
   - Review logs for patterns indicating attacks

2. **Resource Limits:**
   - 10-minute timeout prevents resource exhaustion
   - Sampling prevents telemetry flooding
   - Consider implementing additional rate limiting

3. **Attack Surface:**
   - HTTP endpoints exposed under `/api/*`
   - Authentication handled at function level (see run.ps1)
   - No built-in Azure Functions authentication (authLevel: anonymous)
   - Manual token validation provides fine-grained control

4. **Recommended Additional Protections:**
   - Deploy behind Azure API Management for rate limiting
   - Enable Azure DDoS Protection
   - Use Application Insights alerts for anomaly detection
   - Implement request throttling based on IP or identity

## Related Files
- `profile.ps1` - Runtime initialization and module loading
- `requirements.psd1` - PowerShell module dependencies
- `recordh/function.json` - Individual function binding configuration
- `recordh/run.ps1` - Function code with authentication logic

## References
- [host.json reference](https://docs.microsoft.com/azure/azure-functions/functions-host-json)
- [Application Insights](https://docs.microsoft.com/azure/azure-monitor/app/app-insights-overview)
- [Function timeout limits](https://docs.microsoft.com/azure/azure-functions/functions-scale#timeout)
