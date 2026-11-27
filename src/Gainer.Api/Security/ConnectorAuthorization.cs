using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;

namespace Gainer.Api.Security;

/// <summary>
/// Separates tokens of connected assistants from app tokens: a connector token opens only the MCP
/// endpoint, an app token everything else.
/// </summary>
public static class ConnectorAuthorization
{
    /// <summary>The policy of the MCP endpoint.</summary>
    public const string PolicyName = "Connector";

    /// <summary>Claim that marks an access token of a connected assistant.</summary>
    public const string ScopeClaimType = "gainer:scope";

    /// <summary>Value of <see cref="ScopeClaimType"/> for connector tokens.</summary>
    public const string ScopeClaimValue = "connector";

    /// <summary>OAuth scope that a connected assistant receives.</summary>
    public const string OAuthScope = "gainer:read";

    /// <summary>True when the principal carries a connector token.</summary>
    public static bool IsConnector(ClaimsPrincipal principal) =>
        principal.HasClaim(ScopeClaimType, ScopeClaimValue);

    /// <summary>Requires an authenticated app token, i.e. no connector scope.</summary>
    public static AuthorizationPolicyBuilder RequireAppToken(this AuthorizationPolicyBuilder policy) =>
        policy.RequireAuthenticatedUser().RequireAssertion(context => !IsConnector(context.User));

    /// <summary>Requires an authenticated connector token.</summary>
    public static AuthorizationPolicyBuilder RequireConnectorToken(this AuthorizationPolicyBuilder policy) =>
        policy.RequireAuthenticatedUser().RequireClaim(ScopeClaimType, ScopeClaimValue);
}
