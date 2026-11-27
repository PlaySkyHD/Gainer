using System.Reflection;
using System.Text.Json.Serialization;
using Gainer.Api.Composition;
using Gainer.Api.Connectors;
using Gainer.Api.Errors;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Core.Access;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.WebUtilities;

namespace Gainer.Api.Controllers;

/// <summary>
/// OAuth 2.1 for connected assistants: dynamic client registration, consent with a passkey, and the
/// token endpoint for authorization codes with PKCE and refresh tokens. Approved assistants become
/// connector sessions whose tokens open only the MCP endpoint.
/// </summary>
[ApiController]
[Route(ConnectorEndpoints.OAuthRoute)]
[ApiExplorerSettings(IgnoreApi = true)]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class OAuthController(
    ConnectorEndpoints endpoints,
    ConnectorClientRegistry clients,
    ConnectorAuthorizationRequests requests,
    ConnectorAuthorizationCodes codes,
    IPasskeyHandler<AppUser> passkeys,
    PasskeyCeremonyProtector ceremonies,
    SignInManager<AppUser> signInManager,
    UserManager<AppUser> userManager,
    IDeviceSessionService deviceSessions,
    DeviceSignIn deviceSignIn) : ControllerBase
{
    private const string HtmlContentType = "text/html; charset=utf-8";

    private static readonly Lazy<string> ConsentScript = new(() =>
    {
        using Stream stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("Gainer.Api.Connectors.authorize.js")
            ?? throw new InvalidOperationException("The consent script is not embedded.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    });

    /// <summary>Registers a public client (RFC 7591) without storing it.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [HttpPost("register")]
    public ActionResult<ClientRegistrationResponse> Register(ClientRegistrationRequest request)
    {
        IReadOnlyList<string> redirectUris = request.RedirectUris ?? [];
        if (redirectUris.Count is 0 or > ConnectorClientRegistry.MaximumRedirectUris
            || !redirectUris.All(clients.IsAllowedRedirect))
        {
            return BadRequest(new OAuthError("invalid_redirect_uri", "Redirect URIs must use HTTPS on an allowed host."));
        }

        if (request.TokenEndpointAuthMethod is not (null or "none"))
        {
            return BadRequest(new OAuthError("invalid_client_metadata", "Only public clients are supported."));
        }

        var client = new ConnectorClient(ConnectorClientRegistry.DisplayName(request.ClientName), redirectUris);
        return StatusCode(StatusCodes.Status201Created, new ClientRegistrationResponse(
            clients.Register(client),
            client.Name,
            client.RedirectUris,
            "none",
            ["authorization_code", "refresh_token"],
            ["code"]));
    }

    /// <summary>Shows the consent page, or sends protocol errors back to the client.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [HttpGet("authorize")]
    public IActionResult Authorize(
        [FromQuery(Name = "response_type")] string? responseType,
        [FromQuery(Name = "client_id")] string? clientId,
        [FromQuery(Name = "redirect_uri")] string? redirectUri,
        [FromQuery(Name = "code_challenge")] string? codeChallenge,
        [FromQuery(Name = "code_challenge_method")] string? codeChallengeMethod,
        [FromQuery(Name = "state")] string? state,
        [FromQuery(Name = "resource")] string? resource)
    {
        // Without a known client and one of its redirect URIs nothing may be sent anywhere.
        ConnectorClient? client = clients.Find(clientId);
        if (client is null || redirectUri is null
            || !client.RedirectUris.Contains(redirectUri, StringComparer.Ordinal)
            || !clients.IsAllowedRedirect(redirectUri))
        {
            return ErrorPage("Der Assistent ist unbekannt oder seine Rücksprungadresse ist nicht erlaubt.");
        }

        if (responseType != "code")
        {
            return RedirectWithError(redirectUri, "unsupported_response_type", state);
        }

        if (codeChallengeMethod != "S256" || !Pkce.IsValidChallenge(codeChallenge))
        {
            return RedirectWithError(redirectUri, "invalid_request", state);
        }

        if (resource is not null && !string.Equals(resource.TrimEnd('/'), endpoints.Resource, StringComparison.Ordinal))
        {
            return RedirectWithError(redirectUri, "invalid_target", state);
        }

        var request = new ConnectorAuthorizationRequest(clientId!, client.Name, redirectUri, state, codeChallenge!);
        string protectedRequest = requests.Protect(request);
        string denyUrl = QueryHelpers.AddQueryString(
            $"/{ConnectorEndpoints.OAuthRoute}/authorize/deny",
            "request",
            protectedRequest);
        return Html(ConnectorConsentPage.Render(request, protectedRequest, denyUrl), StatusCodes.Status200OK);
    }

    /// <summary>Script of the consent page.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.SystemStatusRateLimitPolicy)]
    [HttpGet("authorize.js")]
    public IActionResult Script() => Content(ConsentScript.Value, "text/javascript; charset=utf-8");

    /// <summary>Verifies the passkey and returns the redirect URL with a one-time code.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [HttpPost("authorize/approve")]
    public async Task<ActionResult<ConsentApprovalResponse>> Approve(ConsentApprovalRequest request)
    {
        ConnectorAuthorizationRequest? authorization = requests.Unprotect(request.Request);
        if (authorization is null || !clients.IsAllowedRedirect(authorization.RedirectUri))
        {
            return AuthenticationProblems.BadRequest(
                HttpContext,
                "The authorization request expired. Start connecting again.",
                "authorization_request_invalid");
        }

        if (!ceremonies.TryConsume(PasskeyCeremony.SignIn, null, request.State, out string state))
        {
            return AuthenticationProblems.Unauthorized(HttpContext, "invalid_passkey");
        }

        PasskeyAssertionResult<AppUser> assertion = await passkeys.PerformAssertionAsync(new PasskeyAssertionContext
        {
            HttpContext = HttpContext,
            CredentialJson = request.CredentialJson,
            AssertionState = state,
        });
        if (!assertion.Succeeded || !await signInManager.CanSignInAsync(assertion.User))
        {
            return AuthenticationProblems.Unauthorized(HttpContext, "invalid_passkey");
        }

        await userManager.AddOrUpdatePasskeyAsync(assertion.User, assertion.Passkey);
        string code = codes.Issue(new ConnectorAuthorizationGrant(
            assertion.User.Id,
            authorization.ClientId,
            authorization.ClientName,
            authorization.RedirectUri,
            authorization.CodeChallenge));
        return Ok(new ConsentApprovalResponse(RedirectUrl(authorization.RedirectUri, authorization.State, ("code", code))));
    }

    /// <summary>Sends the refusal back to the client.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [HttpGet("authorize/deny")]
    public IActionResult Deny([FromQuery(Name = "request")] string? request)
    {
        ConnectorAuthorizationRequest? authorization = requests.Unprotect(request);
        return authorization is null || !clients.IsAllowedRedirect(authorization.RedirectUri)
            ? ErrorPage("Die Anfrage ist abgelaufen. Starte die Verbindung im Assistenten neu.")
            : RedirectWithError(authorization.RedirectUri, "access_denied", authorization.State);
    }

    /// <summary>Exchanges an authorization code or a refresh token of a connector session.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(GainerConnectorExtensions.ConnectorTokenRateLimitPolicy)]
    [HttpPost("token")]
    [Consumes("application/x-www-form-urlencoded")]
    public async Task<IActionResult> Token(
        [FromForm(Name = "grant_type")] string? grantType,
        [FromForm(Name = "client_id")] string? clientId,
        [FromForm(Name = "code")] string? code,
        [FromForm(Name = "redirect_uri")] string? redirectUri,
        [FromForm(Name = "code_verifier")] string? codeVerifier,
        [FromForm(Name = "refresh_token")] string? refreshToken,
        CancellationToken cancellationToken)
    {
        if (clients.Find(clientId) is null)
        {
            return Unauthorized(new OAuthError("invalid_client", "The client is not registered."));
        }

        return grantType switch
        {
            "authorization_code" => await ExchangeCodeAsync(clientId!, code, redirectUri, codeVerifier, cancellationToken),
            "refresh_token" => await RefreshAsync(clientId!, refreshToken, cancellationToken),
            _ => BadRequest(new OAuthError("unsupported_grant_type", "Use authorization_code or refresh_token.")),
        };
    }

    private async Task<IActionResult> ExchangeCodeAsync(
        string clientId,
        string? code,
        string? redirectUri,
        string? codeVerifier,
        CancellationToken cancellationToken)
    {
        ConnectorAuthorizationGrant? grant = codes.Redeem(code);
        if (grant is null
            || !string.Equals(grant.ClientId, clientId, StringComparison.Ordinal)
            || !string.Equals(grant.RedirectUri, redirectUri, StringComparison.Ordinal)
            || !Pkce.Verify(codeVerifier, grant.CodeChallenge))
        {
            return InvalidGrant();
        }

        AppUser? user = await userManager.FindByIdAsync(grant.UserId.ToString());
        if (user is null || !await signInManager.CanSignInAsync(user))
        {
            return InvalidGrant();
        }

        IssuedDeviceSession session = await deviceSessions.CreateConnectorAsync(
            user.Id,
            grant.ClientName,
            grant.ClientId,
            cancellationToken);
        return Ok(OAuthTokens(await deviceSignIn.TokensAsync(user, session)));
    }

    private async Task<IActionResult> RefreshAsync(string clientId, string? refreshToken, CancellationToken cancellationToken)
    {
        DeviceSessionRefreshResult result = await deviceSessions.RefreshConnectorAsync(
            refreshToken ?? string.Empty,
            clientId,
            cancellationToken);
        if (result is not { Status: DeviceSessionRefreshStatus.Refreshed, Session: IssuedDeviceSession session })
        {
            return InvalidGrant();
        }

        AppUser? user = await userManager.FindByIdAsync(session.UserId.ToString());
        return user is null ? InvalidGrant() : Ok(OAuthTokens(await deviceSignIn.TokensAsync(user, session)));
    }

    private static OAuthTokenResponse OAuthTokens(TokenResponse tokens) => new(
        tokens.AccessToken,
        "Bearer",
        tokens.ExpiresIn,
        tokens.RefreshToken,
        ConnectorAuthorization.OAuthScope);

    private BadRequestObjectResult InvalidGrant() =>
        BadRequest(new OAuthError("invalid_grant", "The grant is invalid, expired, or already used."));

    private ContentResult ErrorPage(string message) =>
        Html(ConnectorConsentPage.RenderError(message), StatusCodes.Status400BadRequest);

    private ContentResult Html(string body, int statusCode)
    {
        Response.Headers.ContentSecurityPolicy = ConnectorConsentPage.ContentSecurityPolicy;
        return new ContentResult { Content = body, ContentType = HtmlContentType, StatusCode = statusCode };
    }

    private RedirectResult RedirectWithError(string redirectUri, string error, string? state) =>
        Redirect(RedirectUrl(redirectUri, state, ("error", error)));

    private static string RedirectUrl(string redirectUri, string? state, (string Name, string Value) parameter)
    {
        var query = new Dictionary<string, string?> { [parameter.Name] = parameter.Value };
        if (state is not null)
        {
            query["state"] = state;
        }

        return QueryHelpers.AddQueryString(redirectUri, query);
    }
}

/// <summary>Dynamic client registration request (RFC 7591).</summary>
public sealed record ClientRegistrationRequest(
    [property: JsonPropertyName("client_name")] string? ClientName,
    [property: JsonPropertyName("redirect_uris")] IReadOnlyList<string>? RedirectUris,
    [property: JsonPropertyName("token_endpoint_auth_method")] string? TokenEndpointAuthMethod);

/// <summary>Dynamic client registration response (RFC 7591).</summary>
public sealed record ClientRegistrationResponse(
    [property: JsonPropertyName("client_id")] string ClientId,
    [property: JsonPropertyName("client_name")] string ClientName,
    [property: JsonPropertyName("redirect_uris")] IReadOnlyList<string> RedirectUris,
    [property: JsonPropertyName("token_endpoint_auth_method")] string TokenEndpointAuthMethod,
    [property: JsonPropertyName("grant_types")] IReadOnlyList<string> GrantTypes,
    [property: JsonPropertyName("response_types")] IReadOnlyList<string> ResponseTypes);

/// <summary>Token response of the OAuth token endpoint.</summary>
public sealed record OAuthTokenResponse(
    [property: JsonPropertyName("access_token")] string AccessToken,
    [property: JsonPropertyName("token_type")] string TokenType,
    [property: JsonPropertyName("expires_in")] int ExpiresIn,
    [property: JsonPropertyName("refresh_token")] string RefreshToken,
    [property: JsonPropertyName("scope")] string Scope);

/// <summary>OAuth error response.</summary>
public sealed record OAuthError(
    [property: JsonPropertyName("error")] string Error,
    [property: JsonPropertyName("error_description")] string Description);

/// <summary>Passkey assertion for a pending authorization request.</summary>
public sealed record ConsentApprovalRequest(string Request, string State, string CredentialJson);

/// <summary>Where the consent page sends the browser next.</summary>
public sealed record ConsentApprovalResponse(string RedirectUri);
