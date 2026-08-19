using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication.Cookies;
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
public sealed class AuthenticationApiTests
{
    private const string TestOrigin = "https://auth.gainer.test";
    private const string Email = "athlete@example.test";
    private const string Password = "Correct-horse-42!";
    private static PostgreSqlTestFixture? fixture;
    private readonly List<string> keyRingPaths = [];

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
        if (fixture is not null)
        {
            await fixture.DisposeAsync();
        }
    }

    [TestCleanup]
    public void DeleteKeyRings()
    {
        foreach (string path in keyRingPaths.Where(Directory.Exists))
        {
            Directory.Delete(path, recursive: true);
        }
    }

    [TestMethod]
    public async Task ValidLoginCreatesSessionAndLogoutInvalidatesIt()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Guid userId = await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        var cookies = new TestCookieJar();

        AntiforgeryTokenResponse anonymousToken = await GetAntiforgeryTokenAsync(client, cookies);
        using HttpResponseMessage login = await SendMutationAsync(
            client,
            cookies,
            "/api/v1/auth/login",
            new LoginRequest(Email, Password),
            anonymousToken.RequestToken);
        Assert.AreEqual(HttpStatusCode.NoContent, login.StatusCode);
        string authCookie = login.Headers.GetValues("Set-Cookie")
            .Single(value => value.StartsWith($"{GainerIdentityOptions.ApplicationCookieName}=", StringComparison.Ordinal));
        StringAssert.Contains(authCookie, "; secure", StringComparison.OrdinalIgnoreCase);
        StringAssert.Contains(authCookie, "; httponly", StringComparison.OrdinalIgnoreCase);
        StringAssert.Contains(authCookie, "; samesite=lax", StringComparison.OrdinalIgnoreCase);
        Assert.IsFalse(authCookie.Contains("domain=", StringComparison.OrdinalIgnoreCase));

        using HttpResponseMessage session = await SendGetAsync(client, cookies, "/api/v1/auth/session");
        SessionResponse? payload = await session.Content.ReadFromJsonAsync<SessionResponse>();
        Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
        Assert.IsNotNull(payload);
        Assert.AreEqual(userId, payload.UserId);
        Assert.AreEqual(Email, payload.Email);
        Assert.IsFalse(payload.IsAccountOperator);
        Assert.IsTrue(session.Headers.CacheControl?.NoStore);

        AntiforgeryTokenResponse authenticatedToken = await GetAntiforgeryTokenAsync(client, cookies);
        using HttpResponseMessage logout = await SendMutationAsync(
            client,
            cookies,
            "/api/v1/auth/logout",
            new { },
            authenticatedToken.RequestToken);
        Assert.AreEqual(HttpStatusCode.NoContent, logout.StatusCode);

        using HttpResponseMessage afterLogout = await SendGetAsync(client, cookies, "/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.Unauthorized, afterLogout.StatusCode);
    }

    [TestMethod]
    public async Task UnknownAccountAndWrongPasswordReturnTheSameGenericFailure()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        var cookies = new TestCookieJar();
        AntiforgeryTokenResponse token = await GetAntiforgeryTokenAsync(client, cookies);

        using HttpResponseMessage unknown = await SendMutationAsync(
            client,
            cookies,
            "/api/v1/auth/login",
            new LoginRequest("unknown@example.test", Password),
            token.RequestToken);
        using HttpResponseMessage wrongPassword = await SendMutationAsync(
            client,
            cookies,
            "/api/v1/auth/login",
            new LoginRequest(Email, "Wrong-password-42!"),
            token.RequestToken);
        using JsonDocument unknownBody = JsonDocument.Parse(await unknown.Content.ReadAsStringAsync());
        using JsonDocument wrongPasswordBody = JsonDocument.Parse(await wrongPassword.Content.ReadAsStringAsync());

        Assert.AreEqual(HttpStatusCode.Unauthorized, unknown.StatusCode);
        Assert.AreEqual(unknown.StatusCode, wrongPassword.StatusCode);
        Assert.AreEqual(
            unknownBody.RootElement.GetProperty("title").GetString(),
            wrongPasswordBody.RootElement.GetProperty("title").GetString());
        Assert.AreEqual(
            unknownBody.RootElement.GetProperty("code").GetString(),
            wrongPasswordBody.RootElement.GetProperty("code").GetString());
        Assert.IsFalse((await unknown.Content.ReadAsStringAsync()).Contains("unknown@example.test", StringComparison.Ordinal));

        using HttpResponseMessage registration = await client.GetAsync("/api/v1/auth/register");
        Assert.AreEqual(HttpStatusCode.NotFound, registration.StatusCode);
    }

    [TestMethod]
    public async Task ExpiredApplicationCookieReturnsUnauthorized()
    {
        var timeProvider = new MutableTimeProvider(new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.Zero));
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        var cookies = new TestCookieJar();
        AntiforgeryTokenResponse token = await GetAntiforgeryTokenAsync(client, cookies);
        using HttpResponseMessage login = await SendMutationAsync(
            client,
            cookies,
            "/api/v1/auth/login",
            new LoginRequest(Email, Password),
            token.RequestToken);
        Assert.AreEqual(HttpStatusCode.NoContent, login.StatusCode);

        timeProvider.Advance(GainerIdentityOptions.ApplicationCookieLifetime + TimeSpan.FromSeconds(1));
        using HttpResponseMessage session = await SendGetAsync(client, cookies, "/api/v1/auth/session");

        Assert.AreEqual(HttpStatusCode.Unauthorized, session.StatusCode);
    }

    private async Task<WebApplication> CreateApplicationAsync(TimeProvider? authenticationTimeProvider = null)
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = Fixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
        }

        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-auth-{Guid.NewGuid():N}");
        keyRingPaths.Add(keyRingPath);
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration[GainerRequestSecurityOptions.FrontendOriginConfigurationKey] = TestOrigin;
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
        if (authenticationTimeProvider is not null)
        {
            builder.Services.PostConfigure<CookieAuthenticationOptions>(
                IdentityConstants.ApplicationScheme,
                options => options.TimeProvider = authenticationTimeProvider);
        }

        var app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();
        return app;
    }

    private static async Task<Guid> CreateUserAsync(WebApplication app, string email, string password)
    {
        await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
        UserManager<AppUser> userManager = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
        var user = new AppUser
        {
            Id = Guid.NewGuid(),
            UserName = email,
            Email = email,
            EmailConfirmed = true,
            IsActive = true,
        };
        IdentityResult result = await userManager.CreateAsync(user, password);
        Assert.IsTrue(result.Succeeded, string.Join(", ", result.Errors.Select(error => error.Code)));
        return user.Id;
    }

    private static HttpClient CreateClient(WebApplication app)
    {
        HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        return client;
    }

    private static async Task<AntiforgeryTokenResponse> GetAntiforgeryTokenAsync(
        HttpClient client,
        TestCookieJar cookies)
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
        TestCookieJar cookies,
        string path,
        TBody? body,
        string requestToken)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, path);
        request.Headers.Add("Origin", TestOrigin);
        request.Headers.Add(GainerRequestSecurityOptions.AntiforgeryHeaderName, requestToken);
        cookies.Apply(request);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }

        HttpResponseMessage response = await client.SendAsync(request);
        cookies.Capture(response);
        request.Dispose();
        return response;
    }

    private static async Task<HttpResponseMessage> SendGetAsync(
        HttpClient client,
        TestCookieJar cookies,
        string path)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, path);
        cookies.Apply(request);
        HttpResponseMessage response = await client.SendAsync(request);
        request.Dispose();
        return response;
    }

    private sealed class TestCookieJar
    {
        private readonly Dictionary<string, string> values = new(StringComparer.Ordinal);

        public void Capture(HttpResponseMessage response)
        {
            if (!response.Headers.TryGetValues("Set-Cookie", out IEnumerable<string>? headers))
            {
                return;
            }

            foreach (string header in headers)
            {
                string[] pair = header.Split(';', 2)[0].Split('=', 2);
                if (pair[1].Length == 0)
                {
                    values.Remove(pair[0]);
                }
                else
                {
                    values[pair[0]] = pair[1];
                }
            }
        }

        public void Apply(HttpRequestMessage request)
        {
            if (values.Count > 0)
            {
                request.Headers.Add("Cookie", string.Join("; ", values.Select(pair => $"{pair.Key}={pair.Value}")));
            }
        }
    }

    private sealed class MutableTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset currentUtc = utcNow;

        public override DateTimeOffset GetUtcNow() => currentUtc;

        public void Advance(TimeSpan duration)
        {
            currentUtc += duration;
        }
    }
}
