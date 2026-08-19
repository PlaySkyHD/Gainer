using System.Net;
using System.Net.Http.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Contracts.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class SyncClientApiTests
{
    private const string TestOrigin = "https://sync.gainer.test";
    private const string Email = "sync-client@example.test";
    private const string Password = "Sync-client-password-42!";
    private static PostgreSqlTestFixture? fixture;
    private string? keyRingPath;

    private static PostgreSqlTestFixture Fixture =>
        fixture ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

    [ClassInitialize]
    public static async Task StartPostgreSqlAsync(TestContext context)
    {
        _ = context;
        fixture = new PostgreSqlTestFixture();
        await fixture.StartAsync();
    }

    [ClassCleanup]
    public static async Task StopPostgreSqlAsync()
    {
        if (fixture is not null) await fixture.DisposeAsync();
    }

    [TestCleanup]
    public void DeleteKeyRing()
    {
        if (keyRingPath is not null && Directory.Exists(keyRingPath))
            Directory.Delete(keyRingPath, recursive: true);
    }

    [TestMethod]
    public async Task AuthenticatedClientRegistrationBindsAndValidatesThroughHttp()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        var cookies = new CookieJar();

        AntiforgeryTokenResponse anonymousToken = await GetAntiforgeryTokenAsync(client, cookies);
        using HttpResponseMessage login = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Post,
            "/api/v1/auth/login",
            new LoginRequest(Email, Password),
            anonymousToken.RequestToken);
        Assert.AreEqual(HttpStatusCode.NoContent, login.StatusCode, await login.Content.ReadAsStringAsync());

        AntiforgeryTokenResponse authenticatedToken = await GetAntiforgeryTokenAsync(client, cookies);
        Guid clientId = Guid.NewGuid();
        using HttpResponseMessage registration = await SendMutationAsync(
            client,
            cookies,
            HttpMethod.Put,
            $"/api/v1/sync/clients/{clientId}",
            new RegisterSyncClientRequest(clientId, "Integration browser", SyncProtocol.CurrentVersion, false),
            authenticatedToken.RequestToken);

        Assert.AreEqual(HttpStatusCode.OK, registration.StatusCode, await registration.Content.ReadAsStringAsync());
        SyncClientResponse? response = await registration.Content.ReadFromJsonAsync<SyncClientResponse>();
        Assert.IsNotNull(response);
        Assert.AreEqual(clientId, response.ClientId);
        Assert.AreEqual("Integration browser", response.DisplayName);
        Assert.IsTrue(response.IsActiveWriter);
    }

    private async Task<WebApplication> CreateApplicationAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = Fixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
        }

        keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-sync-api-{Guid.NewGuid():N}");
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration[GainerRequestSecurityOptions.FrontendOriginConfigurationKey] = TestOrigin;
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();

        WebApplication app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();
        return app;
    }

    private static async Task CreateUserAsync(WebApplication app)
    {
        await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
        UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
        IdentityResult result = await users.CreateAsync(new AppUser
        {
            Id = Guid.NewGuid(),
            UserName = Email,
            Email = Email,
            EmailConfirmed = true,
            IsActive = true,
        }, Password);
        Assert.IsTrue(result.Succeeded, string.Join(", ", result.Errors.Select(error => error.Code)));
    }

    private static async Task<AntiforgeryTokenResponse> GetAntiforgeryTokenAsync(
        HttpClient client,
        CookieJar cookies)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/antiforgery");
        cookies.Apply(request);
        using HttpResponseMessage response = await client.SendAsync(request);
        cookies.Capture(response);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<AntiforgeryTokenResponse>()
            ?? throw new InvalidOperationException("The antiforgery response was empty.");
    }

    private static async Task<HttpResponseMessage> SendMutationAsync<TBody>(
        HttpClient client,
        CookieJar cookies,
        HttpMethod method,
        string path,
        TBody body,
        string requestToken)
    {
        using var request = new HttpRequestMessage(method, path) { Content = JsonContent.Create(body) };
        request.Headers.Add("Origin", TestOrigin);
        request.Headers.Add(GainerRequestSecurityOptions.AntiforgeryHeaderName, requestToken);
        cookies.Apply(request);
        HttpResponseMessage response = await client.SendAsync(request);
        cookies.Capture(response);
        return response;
    }

    private sealed class CookieJar
    {
        private readonly Dictionary<string, string> values = new(StringComparer.Ordinal);

        public void Capture(HttpResponseMessage response)
        {
            if (!response.Headers.TryGetValues("Set-Cookie", out IEnumerable<string>? headers)) return;
            foreach (string header in headers)
            {
                string[] pair = header.Split(';', 2)[0].Split('=', 2);
                if (pair[1].Length == 0) values.Remove(pair[0]);
                else values[pair[0]] = pair[1];
            }
        }

        public void Apply(HttpRequestMessage request)
        {
            if (values.Count > 0)
                request.Headers.Add("Cookie", string.Join("; ", values.Select(pair => $"{pair.Key}={pair.Value}")));
        }
    }
}
