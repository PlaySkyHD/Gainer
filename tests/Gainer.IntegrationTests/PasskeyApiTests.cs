using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Controllers;
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
public sealed class PasskeyApiTests
{
    private const string BaseAddress = "https://passkeys.gainer.test";
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
    public async Task RegisteredPasskeySignsTheDeviceInWithoutPassword()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Guid userId = await CreateUserAsync(app, Email);
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient client = CreateClient(app);
        await client.AuthenticateAsync(Email, Password);

        PasskeySummaryResponse registered = await RegisterAsync(client, authenticator, "Nics iPhone");
        Assert.AreEqual(authenticator.CredentialId, registered.Id);
        Assert.AreEqual("Nics iPhone", registered.Name);
        List<PasskeySummaryResponse>? listed = await client.GetFromJsonAsync<List<PasskeySummaryResponse>>("/api/v1/auth/passkeys", TestContext.CancellationToken);
        Assert.HasCount(1, listed!);

        using HttpClient anonymous = CreateClient(app);
        TokenResponse tokens = await SignInAsync(anonymous, authenticator, "Gainer iPhone");
        anonymous.UseAccessToken(tokens.AccessToken);
        SessionResponse? session = await anonymous.GetFromJsonAsync<SessionResponse>("/api/v1/auth/session", TestContext.CancellationToken);
        Assert.AreEqual(userId, session?.UserId);

        using HttpResponseMessage refreshed = await BearerTestClient.RefreshAsync(anonymous, tokens.RefreshToken);
        Assert.AreEqual(HttpStatusCode.OK, refreshed.StatusCode);
        await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
        AppDbContext database = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.AreEqual(2, await database.DeviceSessions.CountAsync(item => item.UserId == userId, TestContext.CancellationToken));
        Assert.IsTrue(await database.DeviceSessions.AnyAsync(item => item.DeviceName == "Gainer iPhone", TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task CeremonyStateIsSingleUseAndBoundToItsAccount()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, Email);
        await CreateUserAsync(app, "other@example.test");
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient client = CreateClient(app);
        await client.AuthenticateAsync(Email, Password);
        using HttpClient other = CreateClient(app);
        await other.AuthenticateAsync("other@example.test", Password);

        PasskeyOptionsResponse options = await OptionsAsync(client, "/api/v1/auth/passkeys/creation-options");
        string credential = authenticator.Register(options.OptionsJson);
        using HttpResponseMessage foreign = await other.PostAsJsonAsync(
            "/api/v1/auth/passkeys",
            new RegisterPasskeyRequest(credential, options.State), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.BadRequest, foreign.StatusCode);
        Assert.AreEqual("passkey_rejected", await ReadCodeAsync(foreign));

        using HttpResponseMessage tampered = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys",
            new RegisterPasskeyRequest(credential, options.State[..^4] + "AAAA"), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.BadRequest, tampered.StatusCode);

        // The foreign attempt did not consume the state of the owning account.
        using HttpResponseMessage accepted = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys",
            new RegisterPasskeyRequest(credential, options.State), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Created, accepted.StatusCode, await accepted.Content.ReadAsStringAsync(TestContext.CancellationToken));

        PasskeyOptionsResponse signIn = await OptionsAsync(CreateClient(app), "/api/v1/auth/passkeys/request-options");
        string assertion = authenticator.SignIn(signIn.OptionsJson);
        using HttpResponseMessage first = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys/login",
            new PasskeyLoginRequest(assertion, signIn.State), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, first.StatusCode, await first.Content.ReadAsStringAsync(TestContext.CancellationToken));
        using HttpResponseMessage replay = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys/login",
            new PasskeyLoginRequest(assertion, signIn.State), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, replay.StatusCode);
        Assert.AreEqual("invalid_passkey", await ReadCodeAsync(replay));
    }

    [TestMethod]
    public async Task ForeignOriginIsRejected()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, Email);
        using var authenticator = new SoftwarePasskeyAuthenticator { Origin = "https://attacker.example" };
        using HttpClient client = CreateClient(app);
        await client.AuthenticateAsync(Email, Password);

        PasskeyOptionsResponse options = await OptionsAsync(client, "/api/v1/auth/passkeys/creation-options");
        using HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys",
            new RegisterPasskeyRequest(authenticator.Register(options.OptionsJson), options.State), cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
        List<PasskeySummaryResponse>? listed = await client.GetFromJsonAsync<List<PasskeySummaryResponse>>("/api/v1/auth/passkeys", TestContext.CancellationToken);
        Assert.IsEmpty(listed!);
    }

    [TestMethod]
    public async Task DeactivatedAccountsAndRemovedPasskeysCannotSignIn()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Guid userId = await CreateUserAsync(app, Email);
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient client = CreateClient(app);
        await client.AuthenticateAsync(Email, Password);
        await RegisterAsync(client, authenticator, "iPhone");

        await using (AsyncServiceScope scope = app.Services.CreateAsyncScope())
        {
            IAccountStatusService status = scope.ServiceProvider.GetRequiredService<IAccountStatusService>();
            await status.SetActiveAsync(userId, isActive: false, TestContext.CancellationToken);
        }

        using HttpClient anonymous = CreateClient(app);
        Assert.AreEqual(HttpStatusCode.Unauthorized, (await TrySignInAsync(anonymous, authenticator)).StatusCode);

        await using (AsyncServiceScope scope = app.Services.CreateAsyncScope())
        {
            IAccountStatusService status = scope.ServiceProvider.GetRequiredService<IAccountStatusService>();
            await status.SetActiveAsync(userId, isActive: true, TestContext.CancellationToken);
        }

        await client.AuthenticateAsync(Email, Password);
        using HttpResponseMessage removed = await client.DeleteAsync($"/api/v1/auth/passkeys/{authenticator.CredentialId}", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.NoContent, removed.StatusCode);
        using HttpResponseMessage missing = await client.DeleteAsync($"/api/v1/auth/passkeys/{authenticator.CredentialId}", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.NotFound, missing.StatusCode);
        Assert.AreEqual(HttpStatusCode.Unauthorized, (await TrySignInAsync(anonymous, authenticator)).StatusCode);
    }

    [TestMethod]
    public async Task PasswordLockoutDoesNotBlockPasskeySignIn()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, Email);
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient client = CreateClient(app);
        await client.AuthenticateAsync(Email, Password);
        await RegisterAsync(client, authenticator, "iPhone");

        using HttpClient anonymous = CreateClient(app);
        for (int attempt = 0; attempt < 5; attempt++)
        {
            using HttpResponseMessage wrong = await anonymous.PostAsJsonAsync(
                "/api/v1/auth/login",
                new LoginRequest(Email, "Wrong-password-1!"), cancellationToken: TestContext.CancellationToken);
            Assert.AreEqual(HttpStatusCode.Unauthorized, wrong.StatusCode);
        }

        using HttpResponseMessage locked = await anonymous.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(Email, Password), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, locked.StatusCode);
        TokenResponse tokens = await SignInAsync(anonymous, authenticator, "iPhone");
        Assert.IsFalse(string.IsNullOrEmpty(tokens.AccessToken));
    }

    [TestMethod]
    public async Task AddingAPasskeyLaterRequiresThePassword()
    {
        var timeProvider = new MutableTimeProvider(DateTimeOffset.UtcNow);
        await using WebApplication app = await CreateApplicationAsync(timeProvider);
        await CreateUserAsync(app, Email);
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient client = CreateClient(app);
        await client.AuthenticateAsync(Email, Password);

        timeProvider.Advance(PasskeysController.RecentSignInWindow + TimeSpan.FromMinutes(1));
        using HttpResponseMessage withoutPassword = await client.PostAsync("/api/v1/auth/passkeys/creation-options", content: null, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Forbidden, withoutPassword.StatusCode);
        Assert.AreEqual("reauthentication_required", await ReadCodeAsync(withoutPassword));
        using HttpResponseMessage wrongPassword = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys/creation-options",
            new PasskeyCreationOptionsRequest("Wrong-password-1!"), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Forbidden, wrongPassword.StatusCode);

        using HttpResponseMessage confirmed = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys/creation-options",
            new PasskeyCreationOptionsRequest(Password), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, confirmed.StatusCode, await confirmed.Content.ReadAsStringAsync(TestContext.CancellationToken));
        PasskeyOptionsResponse options = (await confirmed.Content.ReadFromJsonAsync<PasskeyOptionsResponse>(TestContext.CancellationToken))!;
        using HttpResponseMessage registered = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys",
            new RegisterPasskeyRequest(authenticator.Register(options.OptionsJson), options.State, "iPhone"), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Created, registered.StatusCode);
    }

    [TestMethod]
    public async Task LogoutAllEndsEverySessionButKeepsPasskeys()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, Email);
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient phone = CreateClient(app);
        await phone.AuthenticateAsync(Email, Password);
        await RegisterAsync(phone, authenticator, "iPhone");
        using HttpClient tablet = CreateClient(app);
        await tablet.AuthenticateAsync(Email, Password);

        using HttpResponseMessage logoutAll = await phone.PostAsync("/api/v1/auth/logout-all", content: null, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.NoContent, logoutAll.StatusCode);
        using HttpResponseMessage phoneSession = await phone.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        using HttpResponseMessage tabletSession = await tablet.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, phoneSession.StatusCode);
        Assert.AreEqual(HttpStatusCode.Unauthorized, tabletSession.StatusCode);

        using HttpClient anonymous = CreateClient(app);
        TokenResponse again = await SignInAsync(anonymous, authenticator, "iPhone");
        Assert.IsFalse(string.IsNullOrEmpty(again.AccessToken));
    }

    [TestMethod]
    public async Task PasskeyManagementRequiresAnAccessToken()
    {
        await using WebApplication app = await CreateApplicationAsync();
        using HttpClient client = CreateClient(app);

        using HttpResponseMessage list = await client.GetAsync("/api/v1/auth/passkeys", TestContext.CancellationToken);
        using HttpResponseMessage options = await client.PostAsync("/api/v1/auth/passkeys/creation-options", content: null, TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, list.StatusCode);
        Assert.AreEqual(HttpStatusCode.Unauthorized, options.StatusCode);
    }

    private static async Task<PasskeySummaryResponse> RegisterAsync(
        HttpClient client,
        SoftwarePasskeyAuthenticator authenticator,
        string name)
    {
        PasskeyOptionsResponse options = await OptionsAsync(client, "/api/v1/auth/passkeys/creation-options");
        using HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys",
            new RegisterPasskeyRequest(authenticator.Register(options.OptionsJson), options.State, name));
        Assert.AreEqual(HttpStatusCode.Created, response.StatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<PasskeySummaryResponse>())!;
    }

    private static async Task<TokenResponse> SignInAsync(
        HttpClient client,
        SoftwarePasskeyAuthenticator authenticator,
        string deviceName)
    {
        using HttpResponseMessage response = await TrySignInAsync(client, authenticator, deviceName);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<TokenResponse>())!;
    }

    private static async Task<HttpResponseMessage> TrySignInAsync(
        HttpClient client,
        SoftwarePasskeyAuthenticator authenticator,
        string? deviceName = null)
    {
        PasskeyOptionsResponse options = await OptionsAsync(client, "/api/v1/auth/passkeys/request-options");
        return await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys/login",
            new PasskeyLoginRequest(authenticator.SignIn(options.OptionsJson), options.State, deviceName));
    }

    private static async Task<PasskeyOptionsResponse> OptionsAsync(HttpClient client, string path)
    {
        using HttpResponseMessage response = await client.PostAsync(path, content: null);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<PasskeyOptionsResponse>())!;
    }

    private static async Task<string?> ReadCodeAsync(HttpResponseMessage response)
    {
        using JsonDocument body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return body.RootElement.GetProperty("code").GetString();
    }

    private async Task<WebApplication> CreateApplicationAsync(TimeProvider? timeProvider = null)
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync(TestContext.CancellationToken);
        }

        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-passkeys-{Guid.NewGuid():N}");
        keyRingPaths.Add(keyRingPath);
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration[GainerIdentityOptions.PasskeyServerDomainConfigurationKey] = "gainer.markfort.xyz";
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

    private static async Task<Guid> CreateUserAsync(WebApplication app, string email)
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
        IdentityResult result = await userManager.CreateAsync(user, Password);
        Assert.IsTrue(result.Succeeded, string.Join(", ", result.Errors.Select(error => error.Code)));
        return user.Id;
    }

    private static HttpClient CreateClient(WebApplication app)
    {
        HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(BaseAddress);
        return client;
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
