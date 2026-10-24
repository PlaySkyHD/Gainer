using System.Reflection;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace Gainer.ArchitectureTests;

[TestClass]
public sealed class DatabaseSchemaVersionTests
{
    [TestMethod]
    public void RequiredMigrationIsTheLatestMigration()
    {
        string latestMigration = typeof(AppDbContext).Assembly
            .GetTypes()
            .Where(type => type.GetCustomAttribute<DbContextAttribute>()?.ContextType == typeof(AppDbContext))
            .Select(type => type.GetCustomAttribute<MigrationAttribute>()?.Id)
            .OfType<string>()
            .OrderBy(id => id, StringComparer.Ordinal)
            .Last();

        Assert.AreEqual(
            DatabaseSchemaVersion.RequiredMigration,
            latestMigration,
            $"DatabaseSchemaVersion.RequiredMigration must be the newest migration. Set it to \"{latestMigration}\" " +
            "in src/Gainer.Infrastructure/Persistence/DatabaseSchemaVersion.cs whenever a migration is added; " +
            "otherwise /health/ready reports ready although the schema is incomplete.");
    }
}
