using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
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
        await client.AuthenticateAsync(Email, Password);

        Guid clientId = Guid.NewGuid();
        using HttpResponseMessage registration = await client.PutAsJsonAsync(
            $"/api/v1/sync/clients/{clientId}",
            new RegisterSyncClientRequest(clientId, "Integration iPhone", SyncProtocol.CurrentVersion, false), cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, registration.StatusCode, await registration.Content.ReadAsStringAsync(TestContext.CancellationToken));
        SyncClientResponse? response = await registration.Content.ReadFromJsonAsync<SyncClientResponse>(TestContext.CancellationToken);
        Assert.IsNotNull(response);
        Assert.AreEqual(clientId, response.ClientId);
        Assert.AreEqual("Integration iPhone", response.DisplayName);
        Assert.IsTrue(response.IsActiveWriter);
    }

    [TestMethod]
    public async Task OlderAppsAreAskedToUpdateOnceWaterIsInTheFeed()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app);
        using HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        await client.AuthenticateAsync(Email, Password);
        Guid clientId = Guid.NewGuid();
        using (HttpResponseMessage registration = await client.PutAsJsonAsync(
            $"/api/v1/sync/clients/{clientId}",
            new RegisterSyncClientRequest(clientId, "Neues iPhone", SyncProtocol.CurrentVersion, false), cancellationToken: TestContext.CancellationToken))
        {
            Assert.AreEqual(HttpStatusCode.OK, registration.StatusCode, await registration.Content.ReadAsStringAsync(TestContext.CancellationToken));
        }

        // An app before protocol 4 pulls without a version and expects version 3.
        using (HttpResponseMessage legacy = await client.GetAsync("/api/v1/sync/changes?after=0&limit=200", TestContext.CancellationToken))
        {
            Assert.AreEqual(HttpStatusCode.OK, legacy.StatusCode);
            PullChangesResponse empty = (await legacy.Content.ReadFromJsonAsync<PullChangesResponse>(TestContext.CancellationToken))!;
            Assert.AreEqual(SyncProtocol.UnversionedPullVersion, empty.ProtocolVersion);
        }

        Guid dayId = Guid.NewGuid();
        using (HttpResponseMessage push = await client.PutAsJsonAsync(
            $"/api/v1/sync/mutations/{Guid.NewGuid()}",
            new PushMutationRequest(
                SyncProtocol.CurrentVersion,
                clientId,
                1,
                "setWaterIntake",
                [new ResourceVersionRequest("WaterIntakeDay", dayId, 0)],
                null,
                JsonSerializer.SerializeToElement(new
                {
                    waterIntakeDayId = dayId,
                    localDate = "2026-10-25",
                    baseVersion = 0,
                    amountMl = 750,
                })), cancellationToken: TestContext.CancellationToken))
        {
            Assert.AreEqual(HttpStatusCode.OK, push.StatusCode, await push.Content.ReadAsStringAsync(TestContext.CancellationToken));
        }

        using (HttpResponseMessage legacy = await client.GetAsync("/api/v1/sync/changes?after=0&limit=200", TestContext.CancellationToken))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, legacy.StatusCode);
            Assert.AreEqual("upgrade_required", await ProblemCodeAsync(legacy));
        }
        using (HttpResponseMessage current = await client.GetAsync(
            $"/api/v1/sync/changes?after=0&limit=200&protocolVersion={SyncProtocol.CurrentVersion}", TestContext.CancellationToken))
        {
            Assert.AreEqual(HttpStatusCode.OK, current.StatusCode);
            PullChangesResponse page = (await current.Content.ReadFromJsonAsync<PullChangesResponse>(TestContext.CancellationToken))!;
            Assert.AreEqual(SyncProtocol.CurrentVersion, page.ProtocolVersion);
            SyncChangeResponse water = page.Batches.Single().Changes.Single();
            Assert.AreEqual("WaterIntakeDay", water.ResourceType);
            Assert.AreEqual(dayId, water.ResourceId);
        }
        using (HttpResponseMessage tooNew = await client.GetAsync(
            $"/api/v1/sync/changes?after=0&limit=200&protocolVersion={SyncProtocol.CurrentVersion + 1}", TestContext.CancellationToken))
        {
            Assert.AreEqual(HttpStatusCode.BadRequest, tooNew.StatusCode);
        }
        using (HttpResponseMessage tooOld = await client.GetAsync("/api/v1/sync/changes?after=0&limit=200&protocolVersion=1", TestContext.CancellationToken))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, tooOld.StatusCode);
            Assert.AreEqual("upgrade_required", await ProblemCodeAsync(tooOld));
        }

        // The old app learns it at registration, where it shows "Aktualisiere die App".
        Guid oldDevice = Guid.NewGuid();
        using HttpResponseMessage oldRegistration = await client.PutAsJsonAsync(
            $"/api/v1/sync/clients/{oldDevice}",
            new RegisterSyncClientRequest(oldDevice, "Altes iPhone", SyncProtocol.UnversionedPullVersion, false), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Conflict, oldRegistration.StatusCode);
        Assert.AreEqual("upgrade_required", await ProblemCodeAsync(oldRegistration));
    }

    private static async Task<string?> ProblemCodeAsync(HttpResponseMessage response)
    {
        using JsonDocument problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return problem.RootElement.TryGetProperty("code", out JsonElement code) ? code.GetString() : null;
    }

    private async Task<WebApplication> CreateApplicationAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync(TestContext.CancellationToken);
        }

        keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-sync-api-{Guid.NewGuid():N}");
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();

        WebApplication app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync(TestContext.CancellationToken);
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

    public TestContext TestContext { get; set; } = null!;
}
