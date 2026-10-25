using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Defines where EF Core stores the migration history and which migrations the schema must contain.</summary>
public static class DatabaseSchemaVersion
{
    public const string MigrationHistorySchema = DatabaseSchemas.Identity;
    public const string MigrationHistoryTable = "__EFMigrationsHistory";

    private static readonly Lazy<string[]> ExpectedMigrationIds = new(DiscoverMigrationIds);

    /// <summary>
    /// Gets the IDs of all migrations of <see cref="AppDbContext"/> in application order, asked once from EF Core without a database connection.
    /// The API is ready only when every one of them is in the migration history, so nothing needs maintaining by hand.
    /// </summary>
    public static IReadOnlyList<string> ExpectedMigrations => ExpectedMigrationIds.Value;

    internal static string[] ExpectedMigrationArray => ExpectedMigrationIds.Value;

    private static string[] DiscoverMigrationIds()
    {
        using AppDbContext context = new AppDbContextFactory().CreateDbContext([]);
        string[] ids = context.Database.GetMigrations().ToArray();

        return ids.Length > 0
            ? ids
            : throw new InvalidOperationException("No EF Core migrations were found for AppDbContext.");
    }
}
