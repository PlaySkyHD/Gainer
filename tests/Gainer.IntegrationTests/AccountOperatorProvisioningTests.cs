using System.Security.Claims;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
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
public sealed class AccountOperatorProvisioningTests
{
    private static PostgreSqlTestFixture? fixture;
    private readonly List<string> temporaryPaths = [];

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
    public void DeleteTemporaryFiles()
    {
        foreach (string path in temporaryPaths)
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
            else if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
    }

    [TestMethod]
    public async Task AccountOperatorPolicyAcceptsOnlyTheDedicatedRole()
    {
        await using WebApplication app = await CreateApplicationAsync();
        IAuthorizationService authorization = app.Services.GetRequiredService<IAuthorizationService>();
        var operatorPrincipal = CreatePrincipal(AccountOperatorAuthorization.RoleName);
        var ordinaryPrincipal = CreatePrincipal(role: null);

        AuthorizationResult operatorResult = await authorization.AuthorizeAsync(
            operatorPrincipal,
            resource: null,
            AccountOperatorAuthorization.PolicyName);
        AuthorizationResult ordinaryResult = await authorization.AuthorizeAsync(
            ordinaryPrincipal,
            resource: null,
            AccountOperatorAuthorization.PolicyName);

        Assert.IsTrue(operatorResult.Succeeded);
        Assert.IsFalse(ordinaryResult.Succeeded);
    }

    [TestMethod]
    public async Task ExternalSecretProvisionsExactlyOneOperatorAccount()
    {
        string email = $"operator-{Guid.NewGuid():N}@example.test";
        const string password = "External-only-password-42!";
        string secretPath = Path.Combine(Path.GetTempPath(), $"gainer-operator-{Guid.NewGuid():N}.json");
        temporaryPaths.Add(secretPath);
        await File.WriteAllTextAsync(secretPath, JsonSerializer.Serialize(new { email, password }));

        await using WebApplication app = await CreateApplicationAsync(secretPath);
        await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
        IInitialAccountOperatorProvisioner provisioner = scope.ServiceProvider
            .GetRequiredService<IInitialAccountOperatorProvisioner>();

        InitialAccountOperatorProvisioningResult first = await provisioner.ProvisionAsync();
        InitialAccountOperatorProvisioningResult second = await provisioner.ProvisionAsync();

        Assert.AreEqual(InitialAccountOperatorProvisioningResult.Created, first);
        Assert.AreEqual(InitialAccountOperatorProvisioningResult.AlreadyProvisioned, second);
        UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
        AppUser? account = await users.FindByEmailAsync(email);
        Assert.IsNotNull(account);
        Assert.IsTrue(await users.IsInRoleAsync(account, AccountOperatorAuthorization.RoleName));
        Assert.IsTrue(await users.CheckPasswordAsync(account, password));
        Assert.AreEqual(1, await users.Users.CountAsync());
    }

    [TestMethod]
    public async Task MissingExternalSecretDoesNotCreateDefaultCredentials()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
        IInitialAccountOperatorProvisioner provisioner = scope.ServiceProvider
            .GetRequiredService<IInitialAccountOperatorProvisioner>();

        await Assert.ThrowsAsync<InvalidOperationException>(() => provisioner.ProvisionAsync());

        UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
        Assert.AreEqual(0, await users.Users.CountAsync());
    }

    private async Task<WebApplication> CreateApplicationAsync(string? secretPath = null)
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = Fixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
        }

        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-operator-keys-{Guid.NewGuid():N}");
        temporaryPaths.Add(keyRingPath);
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        if (secretPath is not null)
        {
            builder.Configuration[InitialAccountOperatorProvisioning.SecretPathConfigurationKey] = secretPath;
        }

        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
        var app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();
        return app;
    }

    private static ClaimsPrincipal CreatePrincipal(string? role)
    {
        List<Claim> claims = [new(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString())];
        if (role is not null)
        {
            claims.Add(new Claim(ClaimTypes.Role, role));
        }

        return new ClaimsPrincipal(new ClaimsIdentity(claims, "test"));
    }
}
