using Gainer.Core.Security;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Creates the migration context used only by EF design-time tooling.</summary>
public sealed class AppDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    /// <inheritdoc />
    public AppDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(
                "Host=localhost;Database=gainer_design;Username=gainer;Password=design-time-only",
                npgsql => npgsql.MigrationsHistoryTable(
                    DatabaseSchemaVersion.MigrationHistoryTable,
                    DatabaseSchemaVersion.MigrationHistorySchema))
            .Options;
        return new AppDbContext(options, new DesignTimeUserContext());
    }

    private sealed class DesignTimeUserContext : IUserContext
    {
        public Guid? UserId => null;
    }
}
