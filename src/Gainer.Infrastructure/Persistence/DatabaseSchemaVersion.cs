namespace Gainer.Infrastructure.Persistence;

/// <summary>Defines where EF Core stores the migration history.</summary>
public static class DatabaseSchemaVersion
{
    public const string MigrationHistorySchema = DatabaseSchemas.Identity;
    public const string MigrationHistoryTable = "__EFMigrationsHistory";
}
