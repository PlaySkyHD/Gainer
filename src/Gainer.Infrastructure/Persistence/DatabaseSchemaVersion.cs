using System.Reflection;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Defines where EF Core stores the migration history and which migrations the schema must contain.</summary>
public static class DatabaseSchemaVersion
{
    public const string MigrationHistorySchema = DatabaseSchemas.Identity;
    public const string MigrationHistoryTable = "__EFMigrationsHistory";

    private static readonly Lazy<IReadOnlyList<string>> ExpectedMigrationIds = new(DiscoverMigrationIds);

    /// <summary>
    /// Gets the IDs of all migrations compiled for <see cref="AppDbContext"/>, discovered once and without a database.
    /// The API is ready only when every one of them is in the migration history, so nothing needs maintaining by hand.
    /// </summary>
    public static IReadOnlyList<string> ExpectedMigrations => ExpectedMigrationIds.Value;

    private static IReadOnlyList<string> DiscoverMigrationIds()
    {
        string[] ids = typeof(AppDbContext).Assembly
            .GetTypes()
            .Where(type => typeof(Migration).IsAssignableFrom(type) && !type.IsAbstract)
            .Where(type => type.GetCustomAttribute<DbContextAttribute>()?.ContextType == typeof(AppDbContext))
            .Select(type => type.GetCustomAttribute<MigrationAttribute>()?.Id)
            .OfType<string>()
            .Order(StringComparer.Ordinal)
            .ToArray();

        return ids.Length > 0
            ? ids
            : throw new InvalidOperationException("No EF Core migrations were found for AppDbContext.");
    }
}
