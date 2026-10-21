using Gainer.Core.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Testcontainers.PostgreSql;

namespace Gainer.IntegrationTests;

internal sealed class PostgreSqlTestFixture : IAsyncDisposable
{
    private readonly PostgreSqlContainer container = new PostgreSqlBuilder("postgres:17.6-alpine")
        .WithDatabase("postgres")
        .WithUsername("postgres")
        .WithPassword("gainer-integration-tests")
        .Build();

    public Task StartAsync()
    {
        return container.StartAsync();
    }

    public async Task<string> CreateIsolatedDatabaseAsync()
    {
        string databaseName = $"gainer_test_{Guid.NewGuid():N}";
        await using var connection = new NpgsqlConnection(container.GetConnectionString());
        await connection.OpenAsync();
        string quotedDatabaseName = new NpgsqlCommandBuilder().QuoteIdentifier(databaseName);
        await using var command = new NpgsqlCommand($"CREATE DATABASE {quotedDatabaseName}", connection);
        await command.ExecuteNonQueryAsync();

        var connectionString = new NpgsqlConnectionStringBuilder(container.GetConnectionString())
        {
            Database = databaseName,
        };
        return connectionString.ConnectionString;
    }

    public AppDbContext CreateContext(string connectionString, Guid? userId = null) =>
        CreateContext(connectionString, new FixtureUserContext(userId));

    public AppDbContext CreateContext(string connectionString, IUserContext userContext)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(connectionString, npgsql => npgsql.MigrationsHistoryTable(
                DatabaseSchemaVersion.MigrationHistoryTable,
                DatabaseSchemaVersion.MigrationHistorySchema))
            .AddInterceptors(
                new UtcTimestampInterceptor(),
                new UserOwnershipInterceptor(userContext))
            .Options;
        return new AppDbContext(options, userContext);
    }

    public ValueTask DisposeAsync()
    {
        return container.DisposeAsync();
    }

    private sealed record FixtureUserContext(Guid? UserId) : IUserContext;
}
