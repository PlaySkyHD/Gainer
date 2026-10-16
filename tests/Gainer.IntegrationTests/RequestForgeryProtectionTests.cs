using System.Net;
using System.Net.Http.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class RequestForgeryProtectionTests
{
    private const string FrontendOrigin = "https://app.gainer.test";
    private readonly List<string> keyRingPaths = [];

    [TestCleanup]
    public void DeleteKeyRings()
    {
        foreach (string path in keyRingPaths.Where(Directory.Exists))
        {
            Directory.Delete(path, recursive: true);
        }
    }

    [TestMethod]
    public async Task MutationRequiresTrustedOriginAndMatchingAntiforgeryTokens()
    {
        await using WebApplication app = await CreateApplicationAsync(Environments.Production);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(FrontendOrigin);

        using HttpResponseMessage tokenResponse = await client.GetAsync("/api/v1/auth/antiforgery");
        string tokenResponseBody = await tokenResponse.Content.ReadAsStringAsync();
        AntiforgeryTokenResponse? token = await tokenResponse.Content
            .ReadFromJsonAsync<AntiforgeryTokenResponse>();
        Assert.AreEqual(HttpStatusCode.OK, tokenResponse.StatusCode, tokenResponseBody);
        Assert.IsNotNull(token);
        string setCookie = tokenResponse.Headers.GetValues("Set-Cookie").Single();
        Assert.StartsWith($"{GainerRequestSecurityOptions.AntiforgeryCookieName}=", setCookie);
        Assert.Contains("; secure", setCookie, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("; httponly", setCookie, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("; samesite=lax", setCookie, StringComparison.OrdinalIgnoreCase);
        Assert.IsFalse(setCookie.Contains("domain=", StringComparison.OrdinalIgnoreCase));
        string cookie = setCookie.Split(';', 2)[0];

        using HttpResponseMessage missingOrigin = await client.PostAsync("/test/mutation", content: null);
        Assert.AreEqual(HttpStatusCode.Forbidden, missingOrigin.StatusCode);

        using var wrongOriginRequest = new HttpRequestMessage(HttpMethod.Post, "/test/mutation");
        wrongOriginRequest.Headers.Add("Origin", "https://attacker.example");
        using HttpResponseMessage wrongOrigin = await client.SendAsync(wrongOriginRequest);
        Assert.AreEqual(HttpStatusCode.Forbidden, wrongOrigin.StatusCode);

        using var missingTokenRequest = CreateMutationRequest(FrontendOrigin, cookie, token: null);
        using HttpResponseMessage missingToken = await client.SendAsync(missingTokenRequest);
        Assert.AreEqual(HttpStatusCode.BadRequest, missingToken.StatusCode);

        using var wrongTokenRequest = CreateMutationRequest(FrontendOrigin, cookie, "wrong-token");
        using HttpResponseMessage wrongToken = await client.SendAsync(wrongTokenRequest);
        Assert.AreEqual(HttpStatusCode.BadRequest, wrongToken.StatusCode);

        using var acceptedRequest = CreateMutationRequest(FrontendOrigin, cookie, token.RequestToken);
        using HttpResponseMessage accepted = await client.SendAsync(acceptedRequest);
        Assert.AreEqual(HttpStatusCode.NoContent, accepted.StatusCode);

        using var acceptedRefererRequest = CreateMutationRequest(origin: null, cookie, token.RequestToken);
        acceptedRefererRequest.Headers.Referrer = new Uri($"{FrontendOrigin}/workout");
        using HttpResponseMessage acceptedReferer = await client.SendAsync(acceptedRefererRequest);
        Assert.AreEqual(HttpStatusCode.NoContent, acceptedReferer.StatusCode);
    }

    [TestMethod]
    public async Task CorsIsDisabledInProductionAndAllowsOnlyConfiguredDevelopmentOrigin()
    {
        await using (WebApplication productionApp = await CreateApplicationAsync(Environments.Production))
        {
            using HttpClient client = productionApp.GetTestClient();
            using HttpResponseMessage response = await client.SendAsync(CreatePreflightRequest(FrontendOrigin));

            Assert.IsFalse(response.Headers.Contains("Access-Control-Allow-Origin"));
        }

        await using WebApplication developmentApp = await CreateApplicationAsync(Environments.Development);
        using HttpClient developmentClient = developmentApp.GetTestClient();
        using HttpResponseMessage allowed = await developmentClient.SendAsync(
            CreatePreflightRequest(FrontendOrigin));
        using HttpResponseMessage rejected = await developmentClient.SendAsync(
            CreatePreflightRequest("https://attacker.example"));

        Assert.AreEqual(HttpStatusCode.NoContent, allowed.StatusCode);
        Assert.AreEqual(FrontendOrigin, allowed.Headers.GetValues("Access-Control-Allow-Origin").Single());
        Assert.AreEqual("true", allowed.Headers.GetValues("Access-Control-Allow-Credentials").Single());
        Assert.IsFalse(rejected.Headers.Contains("Access-Control-Allow-Origin"));
    }

    private static HttpRequestMessage CreateMutationRequest(string? origin, string cookie, string? token)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/test/mutation");
        if (origin is not null)
        {
            request.Headers.Add("Origin", origin);
        }
        request.Headers.Add("Cookie", cookie);
        if (token is not null)
        {
            request.Headers.Add(GainerRequestSecurityOptions.AntiforgeryHeaderName, token);
        }

        return request;
    }

    private static HttpRequestMessage CreatePreflightRequest(string origin)
    {
        var request = new HttpRequestMessage(HttpMethod.Options, "/test/mutation");
        request.Headers.Add("Origin", origin);
        request.Headers.Add("Access-Control-Request-Method", "POST");
        request.Headers.Add(
            "Access-Control-Request-Headers",
            GainerRequestSecurityOptions.AntiforgeryHeaderName);
        return request;
    }

    private async Task<WebApplication> CreateApplicationAsync(string environmentName)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions
        {
            EnvironmentName = environmentName,
        });
        builder.Logging.ClearProviders();
        builder.Logging.AddConsole();
        builder.WebHost.UseTestServer();
        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-csrf-{Guid.NewGuid():N}");
        keyRingPaths.Add(keyRingPath);
        builder.Configuration[GainerRequestSecurityOptions.FrontendOriginConfigurationKey] = FrontendOrigin;
        builder.AddGainerApi();
        builder.Services.AddDataProtection().PersistKeysToFileSystem(new DirectoryInfo(keyRingPath));
        builder.Services.AddControllers().AddApplicationPart(typeof(TestMutationController).Assembly);

        var app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();
        return app;
    }

}

[ApiController]
[Route("test/mutation")]
public sealed class TestMutationController : ControllerBase
{
    [HttpPost]
    public IActionResult Post()
    {
        return NoContent();
    }
}
