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
            new LoginRequest(Email, Password, "Test-iPhone"), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, login.StatusCode);
        Assert.IsFalse(login.Headers.Contains("Set-Cookie"));
        Assert.IsTrue(login.Headers.CacheControl?.NoStore);
        TokenResponse? tokens = await login.Content.ReadFromJsonAsync<TokenResponse>(TestContext.CancellationToken);
        Assert.IsNotNull(tokens);
        Assert.AreEqual((int)GainerIdentityOptions.AccessTokenLifetime.TotalSeconds, tokens.ExpiresIn);
        Assert.IsGreaterThanOrEqualTo(43, tokens.RefreshToken.Length);

        client.UseAccessToken(tokens.AccessToken);
        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        SessionResponse? payload = await session.Content.ReadFromJsonAsync<SessionResponse>(TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
        Assert.IsNotNull(payload);
        Assert.AreEqual(userId, payload.UserId);
        Assert.AreEqual(Email, payload.Email);
        Assert.IsFalse(payload.IsAccountOperator);
        Assert.IsTrue(session.Headers.CacheControl?.NoStore);

        await using (AsyncServiceScope scope = app.Services.CreateAsyncScope())
        {
            AppDbContext database = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            DeviceSession stored = await database.DeviceSessions.SingleAsync(item => item.UserId == userId, TestContext.CancellationToken);
            Assert.AreEqual("Test-iPhone", stored.DeviceName);
            Assert.HasCount(32, stored.RefreshTokenHash);
        }

        using HttpResponseMessage logout = await client.PostAsync("/api/v1/auth/logout", content: null, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.NoContent, logout.StatusCode);

        using HttpResponseMessage afterLogout = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, afterLogout.StatusCode);
        using HttpResponseMessage refreshAfterLogout = await BearerTestClient.RefreshAsync(client, tokens.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, refreshAfterLogout.StatusCode);
    }

    [TestMethod]
    public async Task UnauthenticatedRequestReturnsProblemDetailsWithStableCode()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = CreateClient(app);

        using HttpResponseMessage response = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        using JsonDocument payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.AreEqual("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        Assert.AreEqual("authentication_required", payload.RootElement.GetProperty("code").GetString());
    }

    [TestMethod]
    public async Task CookiesAndAntiforgeryAreNoLongerPartOfTheApi()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);

        // The fallback policy answers 401 for every unknown route without a session; the route is gone for a signed-in user.
        using HttpResponseMessage anonymousAntiforgery = await client.GetAsync("/api/v1/auth/antiforgery", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, anonymousAntiforgery.StatusCode);
        TokenResponse tokens = await BearerTestClient.LoginAsync(client, Email, Password);
        using var antiforgeryRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/antiforgery");
        antiforgeryRequest.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", tokens.AccessToken);
        using HttpResponseMessage antiforgery = await client.SendAsync(antiforgeryRequest, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.NotFound, antiforgery.StatusCode);

        using var foreignOriginLogin = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/login")
        {
            Content = JsonContent.Create(new LoginRequest(Email, Password)),
        };
        foreignOriginLogin.Headers.Add("Origin", "https://attacker.example");
        foreignOriginLogin.Headers.Add("Cookie", ".AspNetCore.Identity.Application=forged");
        using HttpResponseMessage login = await client.SendAsync(foreignOriginLogin, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, login.StatusCode);

        using var cookieOnly = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/session");
        cookieOnly.Headers.Add("Cookie", ".AspNetCore.Identity.Application=forged");
        using HttpResponseMessage session = await client.SendAsync(cookieOnly, TestContext.CancellationToken);
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
        using (HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken))
        {
            Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
        }

        timeProvider.Advance(TimeSpan.FromHours(7));
        using HttpResponseMessage reused = await BearerTestClient.RefreshAsync(client, first.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, reused.StatusCode);
        Assert.AreEqual("invalid_refresh_token", await ReadCodeAsync(reused));

        using HttpResponseMessage current = await BearerTestClient.RefreshAsync(client, second.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, current.StatusCode);
        using HttpResponseMessage revokedAccess = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, revokedAccess.StatusCode);
    }

    [TestMethod]
    public async Task PreviousTokenIsStillAcceptedMinutesAfterALostResponse()
    {
        var timeProvider = new MutableTimeProvider(Start);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse first = await BearerTestClient.LoginAsync(client, Email, Password);
        _ = await RefreshSucceedsAsync(client, first.RefreshToken);

        timeProvider.Advance(TimeSpan.FromMinutes(30));
        TokenResponse retried = await RefreshSucceedsAsync(client, first.RefreshToken);
        client.UseAccessToken(retried.AccessToken);
        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
    }

    [TestMethod]
    public async Task OlderPredecessorGetsNoGraceEvenWithinTheGracePeriod()
    {
        var timeProvider = new MutableTimeProvider(Start);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse first = await BearerTestClient.LoginAsync(client, Email, Password);
        TokenResponse second = await RefreshSucceedsAsync(client, first.RefreshToken);
        TokenResponse third = await RefreshSucceedsAsync(client, second.RefreshToken);

        timeProvider.Advance(TimeSpan.FromMinutes(5));
        using HttpResponseMessage reused = await BearerTestClient.RefreshAsync(client, first.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, reused.StatusCode);
        Assert.AreEqual("invalid_refresh_token", await ReadCodeAsync(reused));

        // Only the immediate predecessor is remembered; the older token is simply unknown.
        TokenResponse retried = await RefreshSucceedsAsync(client, second.RefreshToken);
        Assert.AreNotEqual(third.RefreshToken, retried.RefreshToken);
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
        Assert.AreNotEqual(lost.RefreshToken, retried.RefreshToken);

        TokenResponse next = await RefreshSucceedsAsync(client, retried.RefreshToken);
        client.UseAccessToken(next.AccessToken);
        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
    }

    [TestMethod]
    public async Task TokenDiscardedByAGraceRetryRevokesTheSessionWhenItReturns()
    {
        var timeProvider = new MutableTimeProvider(Start);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse stolen = await BearerTestClient.LoginAsync(client, Email, Password);
        TokenResponse device = await RefreshSucceedsAsync(client, stolen.RefreshToken);

        timeProvider.Advance(TimeSpan.FromSeconds(20));
        TokenResponse attacker = await RefreshSucceedsAsync(client, stolen.RefreshToken);

        using HttpResponseMessage deviceRefresh = await BearerTestClient.RefreshAsync(client, device.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, deviceRefresh.StatusCode);
        Assert.AreEqual("invalid_refresh_token", await ReadCodeAsync(deviceRefresh));
        using HttpResponseMessage attackerRefresh = await BearerTestClient.RefreshAsync(client, attacker.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, attackerRefresh.StatusCode);
        client.UseAccessToken(attacker.AccessToken);
        using HttpResponseMessage attackerAccess = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, attackerAccess.StatusCode);
    }

    [TestMethod]
    public async Task OnlyOneGraceRetryIsAllowedPerRotation()
    {
        var timeProvider = new MutableTimeProvider(Start);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse first = await BearerTestClient.LoginAsync(client, Email, Password);
        _ = await RefreshSucceedsAsync(client, first.RefreshToken);
        TokenResponse retried = await RefreshSucceedsAsync(client, first.RefreshToken);

        using HttpResponseMessage secondRetry = await BearerTestClient.RefreshAsync(client, first.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, secondRetry.StatusCode);
        using HttpResponseMessage current = await BearerTestClient.RefreshAsync(client, retried.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, current.StatusCode);

    }

    [TestMethod]
    public async Task EachRotationAllowsItsOwnGraceRetry()
    {
        var timeProvider = new MutableTimeProvider(Start);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email, Password);
        using HttpClient client = CreateClient(app);
        TokenResponse first = await BearerTestClient.LoginAsync(client, Email, Password);
        _ = await RefreshSucceedsAsync(client, first.RefreshToken);
        TokenResponse retried = await RefreshSucceedsAsync(client, first.RefreshToken);

        timeProvider.Advance(TimeSpan.FromMinutes(15));
        _ = await RefreshSucceedsAsync(client, retried.RefreshToken);
        TokenResponse retriedAgain = await RefreshSucceedsAsync(client, retried.RefreshToken);
        TokenResponse next = await RefreshSucceedsAsync(client, retriedAgain.RefreshToken);
        client.UseAccessToken(next.AccessToken);
        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
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
        using HttpResponseMessage expired = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, expired.StatusCode);

        TokenResponse renewed = await RefreshSucceedsAsync(client, tokens.RefreshToken);
        client.UseAccessToken(renewed.AccessToken);
        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
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
            Assert.IsTrue(await status.SetActiveAsync(userId, isActive: false, TestContext.CancellationToken));
        }

        using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, session.StatusCode);
        using HttpResponseMessage refresh = await BearerTestClient.RefreshAsync(client, tokens.RefreshToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, refresh.StatusCode);

        await using (AsyncServiceScope scope = app.Services.CreateAsyncScope())
        {
            IAccountStatusService status = scope.ServiceProvider.GetRequiredService<IAccountStatusService>();
            Assert.IsTrue(await status.SetActiveAsync(userId, isActive: true, TestContext.CancellationToken));
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
            new LoginRequest("unknown@example.test", Password), cancellationToken: TestContext.CancellationToken);
        using HttpResponseMessage wrongPassword = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(Email, "Wrong-password-42!"), cancellationToken: TestContext.CancellationToken);
        using JsonDocument unknownBody = JsonDocument.Parse(await unknown.Content.ReadAsStringAsync(TestContext.CancellationToken));
        using JsonDocument wrongPasswordBody = JsonDocument.Parse(await wrongPassword.Content.ReadAsStringAsync(TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.Unauthorized, unknown.StatusCode);
        Assert.AreEqual(unknown.StatusCode, wrongPassword.StatusCode);
        Assert.AreEqual(
            unknownBody.RootElement.GetProperty("title").GetString(),
            wrongPasswordBody.RootElement.GetProperty("title").GetString());
        Assert.AreEqual("invalid_credentials", unknownBody.RootElement.GetProperty("code").GetString());
        Assert.AreEqual(
            unknownBody.RootElement.GetProperty("code").GetString(),
            wrongPasswordBody.RootElement.GetProperty("code").GetString());
        Assert.IsFalse((await unknown.Content.ReadAsStringAsync(TestContext.CancellationToken)).Contains("unknown@example.test", StringComparison.Ordinal));

        // Unknown routes answer 401 without a session (fallback policy) and 404 for a signed-in user.
        using HttpResponseMessage anonymousRegistration = await client.GetAsync("/api/v1/auth/register", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, anonymousRegistration.StatusCode);
        TokenResponse tokens = await BearerTestClient.LoginAsync(client, Email, Password);
        using var registrationRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/register");
        registrationRequest.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", tokens.AccessToken);
        using HttpResponseMessage registration = await client.SendAsync(registrationRequest, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.NotFound, registration.StatusCode);
    }

    private async Task<WebApplication> CreateApplicationAsync(TimeProvider? timeProvider = null)
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync(TestContext.CancellationToken);
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
        await app.StartAsync(TestContext.CancellationToken);
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

    public TestContext TestContext { get; set; } = null!;
}
