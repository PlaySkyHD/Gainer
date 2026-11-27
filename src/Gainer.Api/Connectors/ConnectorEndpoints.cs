using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;

namespace Gainer.Api.Connectors;

/// <summary>Public URLs of the MCP resource and its authorization server.</summary>
public sealed class ConnectorEndpoints(IOptions<IdentityPasskeyOptions> passkeys)
{
    /// <summary>Path of the MCP endpoint.</summary>
    public const string McpPath = "/api/v1/mcp";

    /// <summary>Protected-resource metadata of the MCP endpoint (RFC 9728, path-suffixed form).</summary>
    public const string ResourceMetadataPath = "/.well-known/oauth-protected-resource/api/v1/mcp";

    /// <summary>Protected-resource metadata at the root, for clients that only check there.</summary>
    public const string RootResourceMetadataPath = "/.well-known/oauth-protected-resource";

    /// <summary>Authorization-server metadata (RFC 8414) of the issuer at the root.</summary>
    public const string AuthorizationServerMetadataPath = "/.well-known/oauth-authorization-server";

    /// <summary>Route prefix of the OAuth endpoints.</summary>
    public const string OAuthRoute = "api/v1/oauth";

    /// <summary>Origin the server is reached at, e.g. <c>https://gainer.markfort.xyz</c>; the passkey domain.</summary>
    public string Origin { get; } = "https://" + (passkeys.Value.ServerDomain
        ?? throw new InvalidOperationException("The passkey server domain is not configured."));

    public string Resource => Origin + McpPath;

    public string ResourceMetadata => Origin + ResourceMetadataPath;

    public string AuthorizationEndpoint => $"{Origin}/{OAuthRoute}/authorize";

    public string TokenEndpoint => $"{Origin}/{OAuthRoute}/token";

    public string RegistrationEndpoint => $"{Origin}/{OAuthRoute}/register";
}
