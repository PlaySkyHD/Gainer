using System.Text.Json.Serialization;
using Gainer.Api.Composition;
using Gainer.Api.Connectors;
using Gainer.Api.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Gainer.Api.Controllers;

/// <summary>OAuth discovery for connected assistants (RFC 9728 and RFC 8414).</summary>
[ApiController]
[ApiExplorerSettings(IgnoreApi = true)]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class OAuthMetadataController(ConnectorEndpoints endpoints) : ControllerBase
{
    /// <summary>Describes the MCP endpoint as a protected resource.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.SystemStatusRateLimitPolicy)]
    [HttpGet(ConnectorEndpoints.ResourceMetadataPath)]
    [HttpGet(ConnectorEndpoints.RootResourceMetadataPath)]
    public ActionResult<ProtectedResourceMetadata> ProtectedResource() => Ok(new ProtectedResourceMetadata(
        endpoints.Resource,
        [endpoints.Origin],
        [ConnectorAuthorization.OAuthScope],
        ["header"],
        "Gainer"));

    /// <summary>Describes the authorization server.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.SystemStatusRateLimitPolicy)]
    [HttpGet(ConnectorEndpoints.AuthorizationServerMetadataPath)]
    public ActionResult<AuthorizationServerMetadata> AuthorizationServer() => Ok(new AuthorizationServerMetadata(
        endpoints.Origin,
        endpoints.AuthorizationEndpoint,
        endpoints.TokenEndpoint,
        endpoints.RegistrationEndpoint,
        [ConnectorAuthorization.OAuthScope],
        ["code"],
        ["authorization_code", "refresh_token"],
        ["S256"],
        ["none"]));
}

/// <summary>Protected-resource metadata (RFC 9728).</summary>
public sealed record ProtectedResourceMetadata(
    [property: JsonPropertyName("resource")] string Resource,
    [property: JsonPropertyName("authorization_servers")] IReadOnlyList<string> AuthorizationServers,
    [property: JsonPropertyName("scopes_supported")] IReadOnlyList<string> ScopesSupported,
    [property: JsonPropertyName("bearer_methods_supported")] IReadOnlyList<string> BearerMethodsSupported,
    [property: JsonPropertyName("resource_name")] string ResourceName);

/// <summary>Authorization-server metadata (RFC 8414).</summary>
public sealed record AuthorizationServerMetadata(
    [property: JsonPropertyName("issuer")] string Issuer,
    [property: JsonPropertyName("authorization_endpoint")] string AuthorizationEndpoint,
    [property: JsonPropertyName("token_endpoint")] string TokenEndpoint,
    [property: JsonPropertyName("registration_endpoint")] string RegistrationEndpoint,
    [property: JsonPropertyName("scopes_supported")] IReadOnlyList<string> ScopesSupported,
    [property: JsonPropertyName("response_types_supported")] IReadOnlyList<string> ResponseTypesSupported,
    [property: JsonPropertyName("grant_types_supported")] IReadOnlyList<string> GrantTypesSupported,
    [property: JsonPropertyName("code_challenge_methods_supported")] IReadOnlyList<string> CodeChallengeMethodsSupported,
    [property: JsonPropertyName("token_endpoint_auth_methods_supported")] IReadOnlyList<string> TokenEndpointAuthMethodsSupported);
