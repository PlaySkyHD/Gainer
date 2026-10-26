using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Contracts.Sync;
using Gainer.Core.Integrations;
using Gainer.Core.Training;
using Gainer.Infrastructure.Integrations;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.TestHost;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Gainer.IntegrationTests;

/// <summary>
/// Two-user isolation of the account-level resources that have no list endpoint: passkeys, Strava
/// exports and sync handovers. Both users talk to one running API over HTTP.
/// </summary>
[TestClass]
[DoNotParallelize]
public sealed partial class AccountResourceIsolationMatrixTests
{
    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture
        ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

    [ClassInitialize]
    public static async Task StartAsync(TestContext context)
    {
        _ = context;
        fixture = new PostgreSqlTestFixture();
        await fixture.StartAsync();
    }

    [ClassCleanup]
    public static async Task StopAsync()
    {
        if (fixture is not null) await fixture.DisposeAsync();
    }

    [TestMethod]
    public async Task PasskeysAreListedAndDeletedOnlyByTheirOwner()
    {
        await using var api = await TwoUserHttpApp.StartAsync(Fixture, configure: PasskeyConfiguration);
        using var scenario = new PasskeyScenario(api);
        Guid firstPasskey = await scenario.CreateAsync(api.FirstUser, "first-private-listed");
        Assert.IsTrue(await scenario.ListContainsAsync(api.FirstUser, firstPasskey));
        Assert.IsFalse(
            await scenario.ListContainsAsync(api.SecondUser, firstPasskey),
            "The second user's passkey list shows the first user's passkey.");
        await TwoUserApiIsolationMatrix.VerifyForeignAccessAsync(scenario);
    }

    [TestMethod]
    public async Task StravaExportsAreReadAndRequestedOnlyByTheirOwner()
    {
        await using var api = await TwoUserHttpApp.StartAsync(Fixture, configure: StravaConfiguration);
        await ConnectStravaAsync(api, api.FirstUser);
        await ConnectStravaAsync(api, api.SecondUser);
        await TwoUserApiIsolationMatrix.VerifyForeignAccessAsync(new StravaExportScenario(api, Fixture));
    }

    [TestMethod]
    public async Task SyncHandoversAreCompletedOnlyByTheirOwner()
    {
        await using var api = await TwoUserHttpApp.StartAsync(Fixture);
        var scenario = await HandoverScenario.CreateAsync(api, supportsUpdate: true);
        await TwoUserApiIsolationMatrix.VerifyForeignAccessAsync(scenario);
    }

    [TestMethod]
    public async Task SyncHandoversAreCancelledOnlyByTheirOwner()
    {
        await using var api = await TwoUserHttpApp.StartAsync(Fixture);
        var scenario = await HandoverScenario.CreateAsync(api, supportsUpdate: false);
        await TwoUserApiIsolationMatrix.VerifyForeignAccessAsync(scenario);
    }

    private static void PasskeyConfiguration(WebApplicationBuilder builder) =>
        builder.Configuration[GainerIdentityOptions.PasskeyServerDomainConfigurationKey] = "gainer.markfort.xyz";

    private static void StravaConfiguration(WebApplicationBuilder builder)
    {
        builder.Configuration["Strava:ClientId"] = "123";
        builder.Configuration["Strava:ClientSecret"] = "isolation-test-secret";
        // No export may reach the real Strava while the test runs; manual requests only queue a row.
        ServiceDescriptor[] workers = builder.Services
            .Where(descriptor => descriptor.ImplementationType == typeof(StravaExportWorker))
            .ToArray();
        Assert.IsNotEmpty(workers, "The StravaExportWorker registration was not found, so it could not be removed.");
        foreach (ServiceDescriptor worker in workers) builder.Services.Remove(worker);
    }

    private static async Task ConnectStravaAsync(TwoUserHttpApp api, Guid user)
    {
        DateTime now = DateTime.UtcNow;
        await using AsyncServiceScope scope = api.Services.CreateAsyncScope();
        StravaTokenVault vault = scope.ServiceProvider.GetRequiredService<StravaTokenVault>();
        var connection = new StravaConnection
        {
            AthleteId = user == api.FirstUser ? 4242 : 4343,
            AthleteName = "Test",
            Scope = "read,activity:write",
            CardioExportSinceUtc = now.AddDays(-10),
            ConnectedAtUtc = now.AddDays(-10),
            UpdatedAtUtc = now.AddDays(-10),
        };
        vault.Store(connection, new StravaTokens("access", "refresh", now.AddDays(30), connection.AthleteId, null));
        await using AppDbContext context = Fixture.CreateContext(api.ConnectionString, user);
        context.StravaConnections.Add(connection);
        await context.SaveChangesAsync();
    }

    private abstract partial class HttpScenarioBase(TwoUserHttpApp api)
    {
        protected TwoUserHttpApp Api { get; } = api;

        public Guid FirstUser => Api.FirstUser;

        public Guid SecondUser => Api.SecondUser;

        public Regex FirstUserSecretPattern { get; } = FirstUserSecretRegex();

        public Regex SecondUserSecretPattern { get; } = SecondUserSecretRegex();

        [GeneratedRegex("first-(user|private)", RegexOptions.IgnoreCase)]
        private static partial Regex FirstUserSecretRegex();

        [GeneratedRegex("second-(user|private)", RegexOptions.IgnoreCase)]
        private static partial Regex SecondUserSecretRegex();

        public Task<int> CountAsync(Guid actor) => throw new NotSupportedException();

        public Task<IReadOnlyList<Guid>> ListIdsAsync(Guid actor, int offset, int limit) => throw new NotSupportedException();
    }

    private sealed class PasskeyScenario(TwoUserHttpApp api)
        : HttpScenarioBase(api), ITwoUserApiIsolationScenario<Guid>, IDisposable
    {
        private readonly Dictionary<Guid, string> credentialIds = [];
        private readonly List<SoftwarePasskeyAuthenticator> authenticators = [];

        // Passkeys have no detail and no update endpoint; GET only lists the caller's own passkeys.
        public bool SupportsDetail => false;

        public bool SupportsUpdate => false;

        public async Task<Guid> CreateAsync(Guid actor, string privateMarker)
        {
            var authenticator = new SoftwarePasskeyAuthenticator();
            authenticators.Add(authenticator);
            IsolationApiResponse options = await Api.SendAsync(actor, HttpMethod.Post, "/api/v1/auth/passkeys/creation-options");
            Assert.AreEqual(HttpStatusCode.OK, options.StatusCode, options.Representation);
            PasskeyOptionsResponse challenge = JsonSerializer.Deserialize<PasskeyOptionsResponse>(
                options.Representation, TwoUserHttpApp.JsonOptions)!;
            IsolationApiResponse created = await Api.SendAsync(
                actor,
                HttpMethod.Post,
                "/api/v1/auth/passkeys",
                new RegisterPasskeyRequest(authenticator.Register(challenge.OptionsJson), challenge.State, privateMarker));
            Assert.AreEqual(HttpStatusCode.Created, created.StatusCode, created.Representation);
            Guid id = Guid.NewGuid();
            credentialIds[id] = authenticator.CredentialId;
            return id;
        }

        public Task<IsolationApiResponse> DetailAsync(Guid actor, Guid id) => throw new NotSupportedException();

        /// <summary>Whether the actor's own passkey list, as served by the API, contains the passkey.</summary>
        public async Task<bool> ListContainsAsync(Guid actor, Guid id)
        {
            IsolationApiResponse list = await Api.SendAsync(actor, HttpMethod.Get, "/api/v1/auth/passkeys");
            Assert.AreEqual(HttpStatusCode.OK, list.StatusCode, list.Representation);
            return JsonSerializer
                .Deserialize<List<PasskeySummaryResponse>>(list.Representation, TwoUserHttpApp.JsonOptions)!
                .Any(passkey => passkey.Id == CredentialId(id));
        }

        public Task<IsolationApiResponse> UpdateAsync(Guid actor, Guid id, string privateMarker) =>
            throw new NotSupportedException();

        public Task<IsolationApiResponse> DeleteAsync(Guid actor, Guid id) =>
            Api.SendAsync(actor, HttpMethod.Delete, $"/api/v1/auth/passkeys/{CredentialId(id)}");

        public void Dispose()
        {
            foreach (SoftwarePasskeyAuthenticator authenticator in authenticators) authenticator.Dispose();
        }

        private string CredentialId(Guid id) =>
            credentialIds.TryGetValue(id, out string? credentialId)
                ? credentialId
                : WebEncoders.Base64UrlEncode(id.ToByteArray());
    }

    private sealed class StravaExportScenario(TwoUserHttpApp api, PostgreSqlTestFixture fixture)
        : HttpScenarioBase(api), ITwoUserApiIsolationScenario<Guid>
    {
        // Exports are queued by a POST and cannot be removed through the API.
        public bool SupportsDelete => false;

        public async Task<Guid> CreateAsync(Guid actor, string privateMarker)
        {
            DateTime endedAtUtc = DateTime.UtcNow.AddMinutes(-5);
            var session = new CardioSession
            {
                Id = Guid.NewGuid(),
                StartedAtUtc = endedAtUtc.AddMinutes(-30),
                EndedAtUtc = endedAtUtc,
                SampleIntervalSeconds = 5,
                HeartRateBpm = [120, 130],
                CreatedAtUtc = endedAtUtc,
                UpdatedAtUtc = endedAtUtc,
                Version = 1,
            };
            await using (AppDbContext context = fixture.CreateContext(Api.ConnectionString, actor))
            {
                context.CardioSessions.Add(session);
                await context.SaveChangesAsync();
            }

            IsolationApiResponse queued = await UpdateAsync(actor, session.Id, privateMarker);
            Assert.AreEqual(HttpStatusCode.Accepted, queued.StatusCode, queued.Representation);
            return session.Id;
        }

        public Task<IsolationApiResponse> DetailAsync(Guid actor, Guid id) =>
            Api.SendAsync(actor, HttpMethod.Get, $"/api/v1/integrations/strava/exports/cardio/{id}");

        public Task<IsolationApiResponse> UpdateAsync(Guid actor, Guid id, string privateMarker) =>
            Api.SendAsync(actor, HttpMethod.Post, $"/api/v1/integrations/strava/exports/cardio/{id}");

        public Task<IsolationApiResponse> DeleteAsync(Guid actor, Guid id) => throw new NotSupportedException();
    }

    private sealed class HandoverScenario : HttpScenarioBase, ITwoUserApiIsolationScenario<Guid>
    {
        private readonly Dictionary<Guid, string> codes = [];
        private readonly Dictionary<Guid, Guid> sourceClients = [];
        private readonly Dictionary<Guid, Guid> targetClients = [];

        private HandoverScenario(TwoUserHttpApp api, bool supportsUpdate)
            : base(api)
        {
            SupportsUpdate = supportsUpdate;
        }

        // Completing and cancelling a handover end it, so each flavour verifies one of them.
        public bool SupportsDetail => false;

        public bool SupportsUpdate { get; }

        public static async Task<HandoverScenario> CreateAsync(TwoUserHttpApp api, bool supportsUpdate)
        {
            var scenario = new HandoverScenario(api, supportsUpdate);
            foreach (Guid user in new[] { api.FirstUser, api.SecondUser })
            {
                // The first registered client of an account is its active writer.
                Guid source = Guid.NewGuid();
                Guid target = Guid.NewGuid();
                await scenario.RegisterClientAsync(user, source, "Source");
                await scenario.RegisterClientAsync(user, target, "Target");
                scenario.sourceClients[user] = source;
                scenario.targetClients[user] = target;
            }

            return scenario;
        }

        public async Task<Guid> CreateAsync(Guid actor, string privateMarker)
        {
            IsolationApiResponse response = await Api.SendAsync(
                actor,
                HttpMethod.Post,
                "/api/v1/sync/handovers",
                new BeginSyncHandoverRequest(Guid.NewGuid(), sourceClients[actor], 0));
            Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, response.Representation);
            BeginSyncHandoverResponse begun = JsonSerializer.Deserialize<BeginSyncHandoverResponse>(
                response.Representation, TwoUserHttpApp.JsonOptions)!;
            codes[begun.HandoverId] = begun.OneTimeCode;
            return begun.HandoverId;
        }

        public Task<IsolationApiResponse> DetailAsync(Guid actor, Guid id) => throw new NotSupportedException();

        /// <summary>Completes the handover as the actor's own target device, with the real one-time code.</summary>
        public Task<IsolationApiResponse> UpdateAsync(Guid actor, Guid id, string privateMarker) =>
            Api.SendAsync(
                actor,
                HttpMethod.Post,
                $"/api/v1/sync/handovers/{id}/complete",
                new CompleteSyncHandoverRequest(
                    codes.GetValueOrDefault(id, "unknown-one-time-code"), targetClients[actor], 0));

        public Task<IsolationApiResponse> DeleteAsync(Guid actor, Guid id) =>
            Api.SendAsync(
                actor,
                HttpMethod.Post,
                $"/api/v1/sync/handovers/{id}/cancel",
                new CancelSyncHandoverRequest(sourceClients[actor]));

        private async Task RegisterClientAsync(Guid user, Guid clientId, string name)
        {
            IsolationApiResponse response = await Api.SendAsync(
                user,
                HttpMethod.Put,
                $"/api/v1/sync/clients/{clientId}",
                new RegisterSyncClientRequest(clientId, name, SyncProtocol.CurrentVersion, false));
            Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, response.Representation);
        }
    }
}

/// <summary>One running API with two signed-in accounts, each sending its own bearer token.</summary>
internal sealed class TwoUserHttpApp : IAsyncDisposable
{
    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private const string BaseAddress = "https://isolation.gainer.test";
    private const string Password = "Isolation-test-password-42!";
    private readonly WebApplication app;
    private readonly HttpClient client;
    private readonly string keyRingPath;
    private readonly Dictionary<Guid, TestSession> sessions = [];

    private TwoUserHttpApp(WebApplication app, string connectionString, string keyRingPath)
    {
        this.app = app;
        ConnectionString = connectionString;
        this.keyRingPath = keyRingPath;
        client = app.GetTestClient();
        client.BaseAddress = new Uri(BaseAddress);
    }

    public string ConnectionString { get; }

    public IServiceProvider Services => app.Services;

    public Guid FirstUser { get; private set; }

    public Guid SecondUser { get; private set; }

    public static async Task<TwoUserHttpApp> StartAsync(
        PostgreSqlTestFixture fixture,
        Action<WebApplicationBuilder>? configure = null)
    {
        string connectionString = await fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = fixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
        }

        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-isolation-{Guid.NewGuid():N}");
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
        configure?.Invoke(builder);
        WebApplication app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();

        var result = new TwoUserHttpApp(app, connectionString, keyRingPath);
        result.FirstUser = await result.AddUserAsync("isolation-a@example.test");
        result.SecondUser = await result.AddUserAsync("isolation-b@example.test");
        return result;
    }

    public async Task<IsolationApiResponse> SendAsync(Guid actor, HttpMethod method, string path, object? body = null)
    {
        using var request = new HttpRequestMessage(method, path);
        if (body is not null) request.Content = JsonContent.Create(body, body.GetType());
        sessions[actor].Apply(request);
        using HttpResponseMessage response = await client.SendAsync(request);
        string content = await response.Content.ReadAsStringAsync();
        return new IsolationApiResponse(response.StatusCode, ErrorCode(content), content);
    }

    public async ValueTask DisposeAsync()
    {
        client.Dispose();
        await app.DisposeAsync();
        if (Directory.Exists(keyRingPath)) Directory.Delete(keyRingPath, recursive: true);
    }

    private static string ErrorCode(string content)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(content);
            return document.RootElement.ValueKind == JsonValueKind.Object
                && document.RootElement.TryGetProperty("code", out JsonElement code)
                && code.ValueKind == JsonValueKind.String
                    ? code.GetString()!
                    : string.Empty;
        }
        catch (JsonException)
        {
            return string.Empty;
        }
    }

    private async Task<Guid> AddUserAsync(string email)
    {
        Guid id = Guid.NewGuid();
        await using (AsyncServiceScope scope = app.Services.CreateAsyncScope())
        {
            UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
            IdentityResult result = await users.CreateAsync(
                new AppUser { Id = id, UserName = email, Email = email, EmailConfirmed = true, IsActive = true },
                Password);
            Assert.IsTrue(result.Succeeded, string.Join(", ", result.Errors.Select(error => error.Code)));
        }

        sessions[id] = await TestSession.SignInAsync(client, email, Password);
        return id;
    }
}
