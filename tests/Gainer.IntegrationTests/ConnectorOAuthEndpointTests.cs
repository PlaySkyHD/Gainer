using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Logging;

namespace Gainer.IntegrationTests;

/// <summary>OAuth discovery, registration and consent validation; no database involved.</summary>
[TestClass]
public sealed partial class ConnectorOAuthEndpointTests
{
    internal const string RedirectUri = "https://chatgpt.com/connector_platform_oauth_redirect";
    private const string Origin = "https://gainer.markfort.xyz";

    private string? keyRingPath;

    [TestCleanup]
    public void DeleteKeyRing()
    {
        if (keyRingPath is not null && Directory.Exists(keyRingPath))
        {
            Directory.Delete(keyRingPath, recursive: true);
        }
    }

    [TestMethod]
    public async Task DiscoveryDescribesTheMcpResourceAndTheAuthorizationServer()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = app.GetTestClient();

        using JsonDocument resource = await GetJsonAsync(client, "/.well-known/oauth-protected-resource/api/v1/mcp");
        using JsonDocument root = await GetJsonAsync(client, "/.well-known/oauth-protected-resource");
        using JsonDocument server = await GetJsonAsync(client, "/.well-known/oauth-authorization-server");

        Assert.AreEqual($"{Origin}/api/v1/mcp", resource.RootElement.GetProperty("resource").GetString());
        Assert.AreEqual(Origin, resource.RootElement.GetProperty("authorization_servers")[0].GetString());
        Assert.AreEqual(resource.RootElement.GetRawText(), root.RootElement.GetRawText());
        Assert.AreEqual(Origin, server.RootElement.GetProperty("issuer").GetString());
        Assert.AreEqual($"{Origin}/api/v1/oauth/token", server.RootElement.GetProperty("token_endpoint").GetString());
        Assert.AreEqual($"{Origin}/api/v1/oauth/register", server.RootElement.GetProperty("registration_endpoint").GetString());
        Assert.AreEqual("S256", server.RootElement.GetProperty("code_challenge_methods_supported")[0].GetString());
        Assert.AreEqual(1, server.RootElement.GetProperty("code_challenge_methods_supported").GetArrayLength());
    }

    [TestMethod]
    public async Task McpWithoutTokenPointsToTheResourceMetadata()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = app.GetTestClient();

        using HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/mcp", new { }, TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        string challenge = response.Headers.WwwAuthenticate.ToString();
        Assert.Contains($"resource_metadata=\"{Origin}/.well-known/oauth-protected-resource/api/v1/mcp\"", challenge);
    }

    [TestMethod]
    public async Task RegistrationAcceptsOnlyHttpsRedirectsOnAllowedHosts()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = app.GetTestClient();

        foreach (string uri in new[] { "https://attacker.example/callback", "http://chatgpt.com/callback", "https://chatgpt.com:8443/callback" })
        {
            using HttpResponseMessage rejected = await client.PostAsJsonAsync(
                "/api/v1/oauth/register",
                new { client_name = "ChatGPT", redirect_uris = new[] { uri } },
                TestContext.CancellationToken);
            Assert.AreEqual(HttpStatusCode.BadRequest, rejected.StatusCode, uri);
            using JsonDocument error = JsonDocument.Parse(await rejected.Content.ReadAsStringAsync(TestContext.CancellationToken));
            Assert.AreEqual("invalid_redirect_uri", error.RootElement.GetProperty("error").GetString());
        }

        string clientId = await RegisterAsync(client, TestContext.CancellationToken);
        Assert.IsFalse(string.IsNullOrWhiteSpace(clientId));
    }

    [TestMethod]
    public async Task ConsentPageValidatesClientRedirectAndPkce()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = app.CreateClientWithoutRedirects();
        string clientId = await RegisterAsync(client, TestContext.CancellationToken);
        string challenge = Challenge(NewVerifier());

        using HttpResponseMessage unknownClient = await client.GetAsync(
            AuthorizeUrl("not-a-client", RedirectUri, challenge), TestContext.CancellationToken);
        using HttpResponseMessage foreignRedirect = await client.GetAsync(
            AuthorizeUrl(clientId, "https://chatgpt.com/other", challenge), TestContext.CancellationToken);
        using HttpResponseMessage plainPkce = await client.GetAsync(
            AuthorizeUrl(clientId, RedirectUri, challenge, method: "plain"), TestContext.CancellationToken);
        using HttpResponseMessage page = await client.GetAsync(
            AuthorizeUrl(clientId, RedirectUri, challenge), TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.BadRequest, unknownClient.StatusCode);
        Assert.IsNull(unknownClient.Headers.Location);
        Assert.AreEqual(HttpStatusCode.BadRequest, foreignRedirect.StatusCode);
        Assert.IsNull(foreignRedirect.Headers.Location);
        Assert.AreEqual(HttpStatusCode.Redirect, plainPkce.StatusCode);
        Dictionary<string, string?> error = Query(plainPkce.Headers.Location!);
        Assert.AreEqual("invalid_request", error["error"]);
        Assert.AreEqual("xyz", error["state"]);

        Assert.AreEqual(HttpStatusCode.OK, page.StatusCode);
        string html = await page.Content.ReadAsStringAsync(TestContext.CancellationToken);
        Assert.Contains("Gainer mit ChatGPT verbinden", html);
        Assert.Contains("script-src 'self'", page.Headers.GetValues("Content-Security-Policy").Single());
    }

    [TestMethod]
    public async Task AuthorizationErrorsGoBackToTheClient()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = app.CreateClientWithoutRedirects();
        string clientId = await RegisterAsync(client, TestContext.CancellationToken);
        string challenge = Challenge(NewVerifier());

        using HttpResponseMessage token = await client.GetAsync(
            AuthorizeUrl(clientId, RedirectUri, challenge).Replace("response_type=code", "response_type=token", StringComparison.Ordinal),
            TestContext.CancellationToken);
        using HttpResponseMessage resource = await client.GetAsync(
            AuthorizeUrl(clientId, RedirectUri, challenge).Replace("%2Fapi%2Fv1%2Fmcp", "%2Fother", StringComparison.Ordinal),
            TestContext.CancellationToken);
        using HttpResponseMessage missingClient = await client.GetAsync(
            "/api/v1/oauth/authorize?response_type=code", TestContext.CancellationToken);

        Assert.AreEqual("unsupported_response_type", Query(token.Headers.Location!)["error"]);
        Assert.AreEqual("invalid_target", Query(resource.Headers.Location!)["error"]);
        Assert.AreEqual(HttpStatusCode.BadRequest, missingClient.StatusCode);
    }

    [TestMethod]
    public async Task ApprovalRejectsForeignRequestsAndPasskeyStates()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = app.CreateClientWithoutRedirects();
        string clientId = await RegisterAsync(client, TestContext.CancellationToken);
        using HttpResponseMessage page = await client.GetAsync(
            AuthorizeUrl(clientId, RedirectUri, Challenge(NewVerifier())), TestContext.CancellationToken);
        string request = ProtectedRequest(await page.Content.ReadAsStringAsync(TestContext.CancellationToken));

        using HttpResponseMessage foreignRequest = await client.PostAsJsonAsync(
            "/api/v1/oauth/authorize/approve",
            new { request = "forged", state = "x", credentialJson = "{}" },
            TestContext.CancellationToken);
        using HttpResponseMessage foreignState = await client.PostAsJsonAsync(
            "/api/v1/oauth/authorize/approve",
            new { request, state = "forged", credentialJson = "{}" },
            TestContext.CancellationToken);
        using HttpResponseMessage confidential = await client.PostAsJsonAsync(
            "/api/v1/oauth/register",
            new { client_name = "ChatGPT", redirect_uris = new[] { RedirectUri }, token_endpoint_auth_method = "client_secret_basic" },
            TestContext.CancellationToken);
        using HttpResponseMessage script = await client.GetAsync("/api/v1/oauth/authorize.js", TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.BadRequest, foreignRequest.StatusCode);
        Assert.AreEqual(HttpStatusCode.Unauthorized, foreignState.StatusCode);
        Assert.AreEqual(HttpStatusCode.BadRequest, confidential.StatusCode);
        Assert.AreEqual("invalid_client_metadata", await ErrorAsync(confidential));
        Assert.AreEqual(HttpStatusCode.OK, script.StatusCode);
        Assert.Contains("navigator.credentials.get", await script.Content.ReadAsStringAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task DenyingSendsAccessDeniedWithState()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = app.CreateClientWithoutRedirects();
        string clientId = await RegisterAsync(client, TestContext.CancellationToken);
        using HttpResponseMessage page = await client.GetAsync(
            AuthorizeUrl(clientId, RedirectUri, Challenge(NewVerifier())), TestContext.CancellationToken);
        string request = ProtectedRequest(await page.Content.ReadAsStringAsync(TestContext.CancellationToken));

        using HttpResponseMessage denied = await client.GetAsync(
            QueryHelpers.AddQueryString("/api/v1/oauth/authorize/deny", "request", request), TestContext.CancellationToken);
        using HttpResponseMessage tampered = await client.GetAsync(
            QueryHelpers.AddQueryString("/api/v1/oauth/authorize/deny", "request", request + "x"), TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Redirect, denied.StatusCode);
        Assert.StartsWith(RedirectUri, denied.Headers.Location!.ToString());
        Dictionary<string, string?> query = Query(denied.Headers.Location!);
        Assert.AreEqual("access_denied", query["error"]);
        Assert.AreEqual("xyz", query["state"]);
        Assert.AreEqual(HttpStatusCode.BadRequest, tampered.StatusCode);
        Assert.IsNull(tampered.Headers.Location);
    }

    [TestMethod]
    public async Task TokenEndpointRejectsUnknownClientsAndCodes()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = app.GetTestClient();
        string clientId = await RegisterAsync(client, TestContext.CancellationToken);

        using HttpResponseMessage unknownClient = await client.PostAsync("/api/v1/oauth/token", Form(
            ("grant_type", "authorization_code"), ("client_id", "nope"), ("code", "abc")), TestContext.CancellationToken);
        using HttpResponseMessage unknownCode = await client.PostAsync("/api/v1/oauth/token", Form(
            ("grant_type", "authorization_code"), ("client_id", clientId), ("code", "abc"),
            ("redirect_uri", RedirectUri), ("code_verifier", NewVerifier())), TestContext.CancellationToken);
        using HttpResponseMessage unknownGrant = await client.PostAsync("/api/v1/oauth/token", Form(
            ("grant_type", "password"), ("client_id", clientId)), TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, unknownClient.StatusCode);
        Assert.AreEqual("invalid_client", await ErrorAsync(unknownClient));
        Assert.AreEqual(HttpStatusCode.BadRequest, unknownCode.StatusCode);
        Assert.AreEqual("invalid_grant", await ErrorAsync(unknownCode));
        Assert.AreEqual(HttpStatusCode.BadRequest, unknownGrant.StatusCode);
        Assert.AreEqual("unsupported_grant_type", await ErrorAsync(unknownGrant));
    }

    internal static async Task<string> RegisterAsync(HttpClient client, CancellationToken cancellationToken)
    {
        using HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/oauth/register",
            new { client_name = "ChatGPT", redirect_uris = new[] { RedirectUri } },
            cancellationToken);
        Assert.AreEqual(HttpStatusCode.Created, response.StatusCode, await response.Content.ReadAsStringAsync(cancellationToken));
        using JsonDocument body = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        return body.RootElement.GetProperty("client_id").GetString()!;
    }

    internal static string AuthorizeUrl(string clientId, string redirectUri, string challenge, string method = "S256") =>
        QueryHelpers.AddQueryString("/api/v1/oauth/authorize", new Dictionary<string, string?>
        {
            ["response_type"] = "code",
            ["client_id"] = clientId,
            ["redirect_uri"] = redirectUri,
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = method,
            ["state"] = "xyz",
            ["resource"] = $"{Origin}/api/v1/mcp",
        });

    internal static string NewVerifier() => WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(48));

    internal static string Challenge(string verifier) =>
        WebEncoders.Base64UrlEncode(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));

    internal static string ProtectedRequest(string html) =>
        WebUtility.HtmlDecode(RequestAttribute().Match(html).Groups[1].Value);

    internal static Dictionary<string, string?> Query(Uri location) =>
        QueryHelpers.ParseQuery(location.Query).ToDictionary(item => item.Key, item => (string?)item.Value.ToString());

    internal static FormUrlEncodedContent Form(params (string Name, string Value)[] fields) =>
        new(fields.Select(field => new KeyValuePair<string, string>(field.Name, field.Value)));

    internal static async Task<string?> ErrorAsync(HttpResponseMessage response)
    {
        using JsonDocument body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return body.RootElement.GetProperty("error").GetString();
    }

    private async Task<JsonDocument> GetJsonAsync(HttpClient client, string path)
    {
        using HttpResponseMessage response = await client.GetAsync(path, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, path);
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
    }

    private async Task<WebApplication> CreateApplicationAsync()
    {
        keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-connector-{Guid.NewGuid():N}");
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration[GainerIdentityOptions.PasskeyServerDomainConfigurationKey] = "gainer.markfort.xyz";
        builder.Configuration["ConnectionStrings:gainer-db"] =
            "Host=127.0.0.1;Port=1;Database=unused;Username=unused;Password=unused";
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
        var app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync(TestContext.CancellationToken);
        return app;
    }

    [GeneratedRegex("data-request=\"([^\"]+)\"")]
    private static partial Regex RequestAttribute();

    public TestContext TestContext { get; set; } = null!;
}

/// <summary>Test clients that keep 302 responses instead of following them.</summary>
internal static class TestServerClients
{
    public static HttpClient CreateClientWithoutRedirects(this WebApplication app)
    {
        HttpMessageHandler handler = app.GetTestServer().CreateHandler();
        return new HttpClient(handler) { BaseAddress = new Uri("http://localhost") };
    }
}
