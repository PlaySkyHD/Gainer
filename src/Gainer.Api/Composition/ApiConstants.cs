namespace Gainer.Api.Composition;

/// <summary>Defines stable HTTP API constants.</summary>
public static class ApiConstants
{
    /// <summary>The route prefix for the first public API contract.</summary>
    public const string Version1Route = "api/v1";

    /// <summary>The maximum accepted request body size for the general API.</summary>
    public const long MaximumRequestBodyBytes = 1_048_576;

    /// <summary>The request and response header carrying the correlation identifier.</summary>
    public const string CorrelationIdHeader = "X-Correlation-ID";

    /// <summary>The response header carrying the distributed trace identifier.</summary>
    public const string TraceIdHeader = "X-Trace-ID";

    /// <summary>Rate-limit policy for anonymous sign-in requests.</summary>
    public const string AuthenticationRateLimitPolicy = "authentication";

    /// <summary>Rate-limit policy for token refresh, separate so a sign-in flood cannot end sessions.</summary>
    public const string TokenRefreshRateLimitPolicy = "token-refresh";

    /// <summary>Rate-limit policy for the per-user data export.</summary>
    public const string AccountExportRateLimitPolicy = "account-export";
}
