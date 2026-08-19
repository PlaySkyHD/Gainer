using Gainer.Core.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);
builder.Services.AddSingleton<IUserContext, MigrationUserContext>();
builder.AddGainerPersistence();
using IHost host = builder.Build();
await using AsyncServiceScope scope = host.Services.CreateAsyncScope();
AppDbContext database = scope.ServiceProvider.GetRequiredService<AppDbContext>();
ILogger logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("Gainer.Migrator");

logger.LogInformation("Applying Gainer database migrations.");
await database.Database.MigrateAsync();
string[] pending = (await database.Database.GetPendingMigrationsAsync()).ToArray();
if (pending.Length > 0)
{
    throw new InvalidOperationException("Database migration did not reach the required schema version.");
}
logger.LogInformation("Gainer database schema is current at {RequiredMigration}.", DatabaseSchemaVersion.RequiredMigration);

internal sealed class MigrationUserContext : IUserContext
{
    public Guid? UserId => null;
}
