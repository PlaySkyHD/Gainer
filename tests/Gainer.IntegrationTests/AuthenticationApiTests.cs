using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Core.Access;
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
public sealed class AuthenticationApiTests
{
    private const string TestOrigin = "https://auth.gainer.test";
    private const string Email = "athlete@example.test";
    private const string Password = "Correct-horse-42!";
    private static readonly DateTimeOffset Start = new(2026, 8, 18, 12, 0, 0, TimeSpan.Zero);
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
    public async Task LoginIssuesBearerTokensAndLogoutRevokesTheDeviceSession()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Guid userId = await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);

        using HttpResponseMessage login = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(Email, Password, "Test-iPhone"));
        Assert.AreEqual(HttpStatusCode.OK, login.StatusCode);
        Assert.IsFalse(login.Headers.Contains("Set-Cookie"));
        Assert.IsTrue(login.Headers.CacheControl?.NoStore);
        TokenResponse? tokens = await login.Content.ReadFromJsonAsync<TokenResponse>();
        Assert.IsNotNull(tokens);
        Assert.AreEqual((int)GainerIdentityOptions.AccessTokenLifetime.TotalSeconds, tokens.ExpiresIn);
        Assert.IsGreaterThanOrEqualTo(43, tokens.RefreshToken.Length);

        client.UseAccessToken(tokens.AccessToken);
        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session");
        SessionResponse? payload = await session.Content.ReadFromJsonAsync<SessionResponse>();
        Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
        Assert.IsNotNull(payload);
        Assert.AreEqual(userId, payload.UserId);
        Assert.AreEqual(Email, payload.Email);
        Assert.IsFalse(payload.IsAccountOperator);
        Assert.IsTrue(session.Headers.CacheControl?.NoStore);

        await using (AsyncServiceScope scope = app.Services.CreateAsyncScope())
        {
            AppDbContext database = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            DeviceSession stored = await database.DeviceSessions.SingleAsync(item => item.UserId == userId);
            Assert.AreEqual("Test-iPhone", stored.DeviceName);
            Assert.HasCount(32, stored.RefreshTokenHash);
        }

        using HttpResponseMessage logout = await client.PostAsync("/api/v1/auth/logout", content: null);
        Assert.AreEqual(HttpStatusCode.NoContent, logout.StatusCode);

        using HttpResponseMessage afterLogout = await client.GetAsync("/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.Unauthorized, afterLogout.StatusCode);
        using HttpResponseMessage refreshAfterLogout = await BearerTestClient.RefreshAsync(client, tokens.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, refreshAfterLogout.StatusCode);
    }

    [TestMethod]
    public async Task CookiesAndAntiforgeryAreNoLongerPartOfTheApi()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);

        using HttpResponseMessage antiforgery = await client.GetAsync("/api/v1/auth/antiforgery");
        Assert.AreEqual(HttpStatusCode.NotFound, antiforgery.StatusCode);

        using var foreignOriginLogin = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/login")
        {
            Content = JsonContent.Create(new LoginRequest(Email, Password)),
        };
        foreignOriginLogin.Headers.Add("Origin", "https://attacker.example");
        foreignOriginLogin.Headers.Add("Cookie", ".AspNetCore.Identity.Application=forged");
        using HttpResponseMessage login = await client.SendAsync(foreignOriginLogin);
        Assert.AreEqual(HttpStatusCode.OK, login.StatusCode);

        using var cookieOnly = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/session");
        cookieOnly.Headers.Add("Cookie", ".AspNetCore.Identity.Application=forged");
        using HttpResponseMessage session = await client.SendAsync(cookieOnly);
        Assert.AreEqual(HttpStatusCode.Unauthorized, session.StatusCode);
    }

    [TestMethod]
    public async Task RefreshRotatesTheTokenAndRevokesTheSessionWhenAnOldTokenReturns()
    {
        var timeProvider = new MutableTimeProvider(Start);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse first = await BearerTestClient.LoginAsync(client, Email, Password);

        TokenResponse second = await RefreshSucceedsAsync(client, first.RefreshToken);
        Assert.AreNotEqual(first.RefreshToken, second.RefreshToken);
        Assert.AreNotEqual(first.AccessToken, second.AccessToken);
        client.UseAccessToken(second.AccessToken);
        using (HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session"))
        {
            Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
        }

        timeProvider.Advance(TimeSpan.FromMinutes(2));
        using HttpResponseMessage reused = await BearerTestClient.RefreshAsync(client, first.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, reused.StatusCode);
        Assert.AreEqual("invalid_refresh_token", await ReadCodeAsync(reused));

        using HttpResponseMessage current = await BearerTestClient.RefreshAsync(client, second.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, current.StatusCode);
        using HttpResponseMessage revokedAccess = await client.GetAsync("/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.Unauthorized, revokedAccess.StatusCode);
    }

    [TestMethod]
    public async Task PreviousTokenIsAcceptedWithinTheGracePeriodForALostResponse()
    {
        var timeProvider = new MutableTimeProvider(Start);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse first = await BearerTestClient.LoginAsync(client, Email, Password);
        TokenResponse lost = await RefreshSucceedsAsync(client, first.RefreshToken);

        timeProvider.Advance(TimeSpan.FromSeconds(20));
        TokenResponse retried = await RefreshSucceedsAsync(client, first.RefreshToken);

        using HttpResponseMessage lostToken = await BearerTestClient.RefreshAsync(client, lost.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, lostToken.StatusCode);
        TokenResponse next = await RefreshSucceedsAsync(client, retried.RefreshToken);
        client.UseAccessToken(next.AccessToken);
        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
    }

    [TestMethod]
    public async Task ExpiredAccessTokenIsRejectedAndRefreshIssuesANewOne()
    {
        var timeProvider = new MutableTimeProvider(Start);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse tokens = await client.AuthenticateAsync(Email, Password);

        timeProvider.Advance(GainerIdentityOptions.AccessTokenLifetime + TimeSpan.FromSeconds(1));
        using HttpResponseMessage expired = await client.GetAsync("/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.Unauthorized, expired.StatusCode);

        TokenResponse renewed = await RefreshSucceedsAsync(client, tokens.RefreshToken);
        client.UseAccessToken(renewed.AccessToken);
        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
    }

    [TestMethod]
    public async Task RegularRefreshKeepsTheSessionAliveAndIdleSessionsExpire()
    {
        var timeProvider = new MutableTimeProvider(Start);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse tokens = await BearerTestClient.LoginAsync(client, Email, Password);
        Assert.AreEqual(Start + TimeSpan.FromDays(60), tokens.RefreshTokenExpiresAt);

        for (int month = 0; month < 4; month++)
        {
            timeProvider.Advance(TimeSpan.FromDays(50));
            tokens = await RefreshSucceedsAsync(client, tokens.RefreshToken);
        }

        Assert.AreEqual(timeProvider.GetUtcNow() + TimeSpan.FromDays(60), tokens.RefreshTokenExpiresAt);
        timeProvider.Advance(TimeSpan.FromDays(60) + TimeSpan.FromSeconds(1));
        using HttpResponseMessage idle = await BearerTestClient.RefreshAsync(client, tokens.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, idle.StatusCode);
    }

    [TestMethod]
    public async Task DeactivatingAnAccountEndsItsDeviceSessionsImmediately()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Guid userId = await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse tokens = await client.AuthenticateAsync(Email, Password);

        await using (AsyncServiceScope scope = app.Services.CreateAsyncScope())
        {
            IAccountStatusService status = scope.ServiceProvider.GetRequiredService<IAccountStatusService>();
            Assert.IsTrue(await status.SetActiveAsync(userId, isActive: false));
        }

        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.Unauthorized, session.StatusCode);
        using HttpResponseMessage refresh = await BearerTestClient.RefreshAsync(client, tokens.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, refresh.StatusCode);

        await using (AsyncServiceScope scope = app.Services.CreateAsyncScope())
        {
            IAccountStatusService status = scope.ServiceProvider.GetRequiredService<IAccountStatusService>();
            Assert.IsTrue(await status.SetActiveAsync(userId, isActive: true));
        }

        using HttpResponseMessage afterReactivation = await BearerTestClient.RefreshAsync(client, tokens.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, afterReactivation.StatusCode);
    }

    [TestMethod]
    public async Task UnknownAccountAndWrongPasswordReturnTheSameGenericFailure()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);

        using HttpResponseMessage unknown = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest("unknown@example.test", Password));
        using HttpResponseMessage wrongPassword = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(Email, "Wrong-password-42!"));
        using JsonDocument unknownBody = JsonDocument.Parse(await unknown.Content.ReadAsStringAsync());
        using JsonDocument wrongPasswordBody = JsonDocument.Parse(await wrongPassword.Content.ReadAsStringAsync());

        Assert.AreEqual(HttpStatusCode.Unauthorized, unknown.StatusCode);
        Assert.AreEqual(unknown.StatusCode, wrongPassword.StatusCode);
        Assert.AreEqual(
            unknownBody.RootElement.GetProperty("title").GetString(),
            wrongPasswordBody.RootElement.GetProperty("title").GetString());
        Assert.AreEqual("invalid_credentials", unknownBody.RootElement.GetProperty("code").GetString());
        Assert.AreEqual(
            unknownBody.RootElement.GetProperty("code").GetString(),
            wrongPasswordBody.RootElement.GetProperty("code").GetString());
        Assert.IsFalse((await unknown.Content.ReadAsStringAsync()).Contains("unknown@example.test", StringComparison.Ordinal));

        using HttpResponseMessage registration = await client.GetAsync("/api/v1/auth/register");
        Assert.AreEqual(HttpStatusCode.NotFound, registration.StatusCode);
    }

    private async Task<WebApplication> CreateApplicationAsync(TimeProvider? timeProvider = null)
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
        if (timeProvider is not null)
        {
            builder.Services.AddSingleton(timeProvider);
        }

        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();

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

    private static async Task<TokenResponse> RefreshSucceedsAsync(HttpClient client, string refreshToken)
    {
        using HttpResponseMessage response = await BearerTestClient.RefreshAsync(client, refreshToken);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        return await response.Content.ReadFromJsonAsync<TokenResponse>()
            ?? throw new InvalidOperationException("The refresh response was empty.");
    }

    private static async Task<string?> ReadCodeAsync(HttpResponseMessage response)
    {
        using JsonDocument body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return body.RootElement.GetProperty("code").GetString();
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
