using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Gainer.Infrastructure.Persistence;
using Gainer.Infrastructure.Catalog;
using Gainer.Infrastructure.Coach;
using Gainer.Infrastructure.Nutrition;
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
                tags: [readinessTag])
            .AddCheck<OpenFoodFactsConfigurationHealthCheck>(
                "open-food-facts-configuration",
                tags: [readinessTag])
            .AddCheck<MealEstimationConfigurationHealthCheck>(
                "meal-estimation-configuration",
                tags: [readinessTag])
            .AddCheck<CoachConfigurationHealthCheck>(
                "coach-configuration",
                tags: [readinessTag]);

        return services;
    }
}

internal sealed class CoachConfigurationHealthCheck(IConfiguration configuration) : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        _ = context;
        _ = cancellationToken;
        CoachOptions options = configuration.GetSection(CoachOptions.SectionName).Get<CoachOptions>() ?? new();
        bool valid = options.DailyRequestsPerUser is >= 1 and <= 1_000 && options.MaximumConcurrentRequests is >= 1 and <= 32;
        return Task.FromResult(valid
            ? HealthCheckResult.Healthy("Coach configuration is valid.")
            : HealthCheckResult.Unhealthy("Coach configuration is invalid."));
    }
}

internal sealed class MealEstimationConfigurationHealthCheck(IConfiguration configuration) : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        _ = context;
        _ = cancellationToken;
        OpenAiProviderOptions provider = configuration.GetSection(OpenAiProviderOptions.SectionName).Get<OpenAiProviderOptions>() ?? new();
        MealEstimationOptions estimate = configuration.GetSection(MealEstimationOptions.SectionName).Get<MealEstimationOptions>() ?? new();
        MealImageOptions image = configuration.GetSection(MealImageOptions.SectionName).Get<MealImageOptions>() ?? new();
        bool keyAvailable = !string.IsNullOrWhiteSpace(provider.ApiKey) ||
            (!string.IsNullOrWhiteSpace(provider.ApiKeyFile) && File.Exists(provider.ApiKeyFile));
        bool valid = keyAvailable && !string.IsNullOrWhiteSpace(provider.Model) &&
            provider.TimeoutSeconds is >= 1 and <= 120 && provider.MaxOutputTokens is >= 128 and <= 8_000 &&
            estimate.DailyRequestsPerUser is >= 1 and <= 1_000 && estimate.MaximumConcurrentRequests is >= 1 and <= 32 &&
            image.MaximumBytes is >= 100_000 and <= 20 * 1024 * 1024 && image.MaximumDimension is >= 256 and <= 8_192 &&
            image.MaximumPixels is >= 65_536 and <= 40_000_000 && image.JpegQuality is >= 50 and <= 95;
        return Task.FromResult(valid
            ? HealthCheckResult.Healthy("Meal estimation configuration is valid.")
            : HealthCheckResult.Unhealthy("Meal estimation configuration is invalid."));
    }
}

internal sealed class OpenFoodFactsConfigurationHealthCheck(IConfiguration configuration) : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        _ = context;
        _ = cancellationToken;
        OpenFoodFactsOptions options = configuration
            .GetSection(OpenFoodFactsOptions.SectionName)
            .Get<OpenFoodFactsOptions>() ?? new OpenFoodFactsOptions();
        bool validUrl = Uri.TryCreate(options.BaseUrl, UriKind.Absolute, out Uri? uri) && uri.Scheme == Uri.UriSchemeHttps;
        bool validIdentity = !string.IsNullOrWhiteSpace(options.ApplicationName) &&
            !string.IsNullOrWhiteSpace(options.ApplicationVersion) &&
            !string.IsNullOrWhiteSpace(options.ContactEmail);
        bool validLimits = options.TimeoutSeconds is >= 1 and <= 30 &&
            options.MaximumResponseBytes is >= 1_024 and <= 5_000_000 &&
            options.BarcodeRequestsPerMinute is >= 1 and < 15 &&
            options.SearchRequestsPerMinute is >= 1 and < 10;
        return Task.FromResult(validUrl && validIdentity && validLimits
            ? HealthCheckResult.Healthy("Open Food Facts adapter configuration is valid.")
            : HealthCheckResult.Unhealthy("Open Food Facts adapter configuration is invalid."));
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

/// <summary>
/// Reports the schema as ready only when every migration compiled into the assembly is in the migration history.
/// One query counts the expected IDs in the history, so the check needs neither an <see cref="AppDbContext"/> nor a hand-kept version.
/// </summary>
internal sealed class DatabaseSchemaReadinessHealthCheck(IConfiguration configuration) : IHealthCheck
{
    private static readonly string CountAppliedQuery = BuildCountAppliedQuery();

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var connectionString = GainerPersistenceExtensions.ResolveConnectionString(configuration, "gainer-db");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return HealthCheckResult.Unhealthy("Database schema cannot be verified.");
        }

        string[] expected = DatabaseSchemaVersion.ExpectedMigrationArray;

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand(CountAppliedQuery, connection);
            command.Parameters.AddWithValue("ids", expected);
            var applied = Convert.ToInt64(await command.ExecuteScalarAsync(cancellationToken));

            return applied == expected.Length
                ? HealthCheckResult.Healthy()
                : HealthCheckResult.Unhealthy("Database schema is not at the required version.");
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UndefinedTable)
        {
            return HealthCheckResult.Unhealthy("Database schema is not at the required version.");
        }
        catch (Exception exception) when (
            exception is NpgsqlException or TimeoutException or ArgumentException)
        {
            // ArgumentException: the configured connection string is malformed.
            return HealthCheckResult.Unhealthy("Database schema cannot be verified.");
        }
    }

    private static string BuildCountAppliedQuery()
    {
        var identifiers = new NpgsqlCommandBuilder();

        return "SELECT COUNT(*) FROM " +
            $"{identifiers.QuoteIdentifier(DatabaseSchemaVersion.MigrationHistorySchema)}." +
            $"{identifiers.QuoteIdentifier(DatabaseSchemaVersion.MigrationHistoryTable)} " +
            "WHERE \"MigrationId\" = ANY(@ids)";
    }
}
