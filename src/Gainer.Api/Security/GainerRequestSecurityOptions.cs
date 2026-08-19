namespace Gainer.Api.Security;

/// <summary>Stable request-forgery protection settings.</summary>
public static class GainerRequestSecurityOptions
{
    /// <summary>Header carrying the per-request antiforgery token.</summary>
    public const string AntiforgeryHeaderName = "X-CSRF-TOKEN";

    /// <summary>Host-only cookie paired with the request token.</summary>
    public const string AntiforgeryCookieName = "__Host-Gainer.Antiforgery";

    /// <summary>Configuration key for the concrete browser origin.</summary>
    public const string FrontendOriginConfigurationKey = "Security:FrontendOrigin";

    internal const string DevelopmentCorsPolicy = "GainerDevelopmentFrontend";
}
