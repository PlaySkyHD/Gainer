using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Gainer.Infrastructure.Persistence;
using Npgsql;

namespace Gainer.Infrastructure.HealthChecks;

/// <summary>
/// Registers the database checks required before the Gainer API receives traffic.
/// </summary>
public static class DatabaseReadinessExtensions
{
    /// <summary>
    /// Adds PostgreSQL connectivity and EF migration-history checks with the supplied readiness tag.
    /// </summary>
    /// <param name="services">The service collection.</param>
    /// <param name="readinessTag">The tag selected by the readiness endpoint.</param>
    /// <returns>The supplied service collection.</returns>
    public static IServiceCollection AddGainerDatabaseReadiness(
        this IServiceCollection services,
        string readinessTag)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(readinessTag);

        services
            .AddHealthChecks()
            .AddCheck<PostgreSqlReadinessHealthCheck>(
                "postgresql",
                tags: [readinessTag])
            .AddCheck<DatabaseSchemaReadinessHealthCheck>(
                "database-schema",
                tags: [readinessTag]);

        return services;
    }
}

internal sealed class PostgreSqlReadinessHealthCheck(IConfiguration configuration) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var connectionString = GainerPersistenceExtensions.ResolveConnectionString(configuration, "gainer-db");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return HealthCheckResult.Unhealthy("PostgreSQL connection is not configured.");
        }

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync(cancellationToken);

            return HealthCheckResult.Healthy();
        }
        catch (Exception exception) when (exception is NpgsqlException or TimeoutException)
        {
            return HealthCheckResult.Unhealthy("PostgreSQL is unavailable.");
        }
    }
}

internal sealed class DatabaseSchemaReadinessHealthCheck(IConfiguration configuration) : IHealthCheck
{
    private const string MigrationHistoryQuery =
        "SELECT EXISTS (" +
        "SELECT 1 FROM identity.\"__EFMigrationsHistory\" " +
        "WHERE \"MigrationId\" = @required_migration)";

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var connectionString = GainerPersistenceExtensions.ResolveConnectionString(configuration, "gainer-db");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return HealthCheckResult.Unhealthy("Database schema cannot be verified.");
        }

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand(MigrationHistoryQuery, connection);
            command.Parameters.AddWithValue("required_migration", DatabaseSchemaVersion.RequiredMigration);
            var hasRequiredMigration = await command.ExecuteScalarAsync(cancellationToken) is true;

            return hasRequiredMigration
                ? HealthCheckResult.Healthy()
                : HealthCheckResult.Unhealthy("Database schema is not at the required version.");
        }
        catch (Exception exception) when (exception is NpgsqlException or TimeoutException)
        {
            return HealthCheckResult.Unhealthy("Database schema cannot be verified.");
        }
    }
}
