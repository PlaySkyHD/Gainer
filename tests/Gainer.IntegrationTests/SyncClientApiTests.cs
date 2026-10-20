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
        await client.AuthenticateAsync(Email, Password);

        Guid clientId = Guid.NewGuid();
        using HttpResponseMessage registration = await client.PutAsJsonAsync(
            $"/api/v1/sync/clients/{clientId}",
            new RegisterSyncClientRequest(clientId, "Integration iPhone", SyncProtocol.CurrentVersion, false));

        Assert.AreEqual(HttpStatusCode.OK, registration.StatusCode, await registration.Content.ReadAsStringAsync());
        SyncClientResponse? response = await registration.Content.ReadFromJsonAsync<SyncClientResponse>();
        Assert.IsNotNull(response);
        Assert.AreEqual(clientId, response.ClientId);
        Assert.AreEqual("Integration iPhone", response.DisplayName);
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
}
