namespace Gainer.Infrastructure.Persistence;

/// <summary>Defines the schema version required before the API becomes ready.</summary>
public static class DatabaseSchemaVersion
{
    public const string MigrationHistorySchema = DatabaseSchemas.Identity;
    public const string MigrationHistoryTable = "__EFMigrationsHistory";
    public const string RequiredMigration = "20261024214315_AddCoachMemory";
}
