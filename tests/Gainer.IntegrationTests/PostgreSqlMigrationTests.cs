using Gainer.Infrastructure.HealthChecks;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Npgsql;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class PostgreSqlMigrationTests
{
    private static PostgreSqlTestFixture? fixture;
    private string? connectionString;

    private static PostgreSqlTestFixture Fixture =>
        fixture ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

    private string ConnectionString =>
        connectionString ?? throw new InvalidOperationException("The test database has not been reset.");

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

    [TestInitialize]
    public async Task ResetDatabaseAsync()
    {
        connectionString = await Fixture.CreateIsolatedDatabaseAsync();
    }

    [TestMethod]
    public async Task EmptyDatabaseMigratesAndCreatesRequiredSchemasForTwoUsers()
    {
        await using AppDbContext context = Fixture.CreateContext(ConnectionString);

        await context.Database.MigrateAsync();
        context.Users.AddRange(
            new AppUser { Id = Guid.NewGuid(), UserName = "user-a" },
            new AppUser { Id = Guid.NewGuid(), UserName = "user-b" });
        await context.SaveChangesAsync();

        Assert.AreEqual(2, await context.Users.CountAsync());
        CollectionAssert.AreEquivalent(DatabaseSchemas.All.ToArray(), await ReadSchemasAsync());
        CollectionAssert.Contains(
            (await context.Database.GetAppliedMigrationsAsync()).ToArray(),
            DatabaseSchemaVersion.RequiredMigration);
    }

    [TestMethod]
    public async Task ApplyingMigrationsRepeatedlyKeepsExactlyTheDefinedHistoryEntries()
    {
        await using AppDbContext context = Fixture.CreateContext(ConnectionString);

        await context.Database.MigrateAsync();
        await context.Database.MigrateAsync();
        string[] migrations = (await context.Database.GetAppliedMigrationsAsync()).ToArray();

        CollectionAssert.AreEqual(context.Database.GetMigrations().ToArray(), migrations);
    }

    [TestMethod]
    public async Task TestInitializationProvidesAResetDatabase()
    {
        await using AppDbContext context = Fixture.CreateContext(ConnectionString);

        bool canConnect = await context.Database.CanConnectAsync();
        string[] appliedMigrations = (await context.Database.GetAppliedMigrationsAsync()).ToArray();

        Assert.IsTrue(canConnect);
        Assert.IsEmpty(appliedMigrations);
    }

    [TestMethod]
    public async Task SchemaReadinessRequiresTheCurrentMigration()
    {
        IConfiguration configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:gainer-db"] = ConnectionString,
            })
            .Build();
        var healthCheck = new DatabaseSchemaReadinessHealthCheck(configuration);

        HealthCheckResult beforeMigration = await healthCheck.CheckHealthAsync(new HealthCheckContext());
        await using AppDbContext context = Fixture.CreateContext(ConnectionString);
        await context.Database.MigrateAsync();
        HealthCheckResult afterMigration = await healthCheck.CheckHealthAsync(new HealthCheckContext());

        Assert.AreEqual(HealthStatus.Unhealthy, beforeMigration.Status);
        Assert.AreEqual(HealthStatus.Healthy, afterMigration.Status);
    }

    private async Task<string[]> ReadSchemasAsync()
    {
        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync();
        const string query =
            "SELECT schema_name FROM information_schema.schemata " +
            "WHERE schema_name = ANY (@schemas) ORDER BY schema_name";
        await using var command = new NpgsqlCommand(query, connection);
        command.Parameters.AddWithValue("schemas", DatabaseSchemas.All.ToArray());
        await using NpgsqlDataReader reader = await command.ExecuteReaderAsync();
        var schemas = new List<string>();
        while (await reader.ReadAsync())
        {
            schemas.Add(reader.GetString(0));
        }

        return schemas.ToArray();
    }
}
