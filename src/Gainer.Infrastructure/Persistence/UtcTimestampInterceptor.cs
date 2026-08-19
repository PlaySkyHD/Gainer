using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace Gainer.Infrastructure.Persistence;

internal sealed class UtcTimestampInterceptor : SaveChangesInterceptor
{
    public override InterceptionResult<int> SavingChanges(
        DbContextEventData eventData,
        InterceptionResult<int> result)
    {
        Validate(eventData.Context);
        return result;
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        Validate(eventData.Context);
        return ValueTask.FromResult(result);
    }

    private static void Validate(DbContext? context)
    {
        if (context is null)
        {
            return;
        }

        foreach (EntityEntry entry in context.ChangeTracker.Entries()
                     .Where(entry => entry.State is EntityState.Added or EntityState.Modified))
        {
            foreach (PropertyEntry property in entry.Properties)
            {
                ValidateTimestamp(property);
            }
        }
    }

    private static void ValidateTimestamp(PropertyEntry property)
    {
        string? columnType = property.Metadata.GetColumnType();
        if (columnType != "timestamp with time zone" || property.CurrentValue is null)
        {
            return;
        }

        bool isUtc = property.CurrentValue switch
        {
            DateTime dateTime => dateTime.Kind == DateTimeKind.Utc,
            DateTimeOffset dateTimeOffset => dateTimeOffset.Offset == TimeSpan.Zero,
            _ => true,
        };

        if (!isUtc)
        {
            throw new InvalidOperationException(
                $"Property '{property.Metadata.Name}' must contain a UTC timestamp.");
        }
    }
}
