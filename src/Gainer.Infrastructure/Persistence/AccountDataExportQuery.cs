using System.Data;
using System.Text.Json;
using Gainer.Core.Coach;
using Gainer.Core.Sync;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

/// <summary>
/// Takes the newest change of every resource from the user-scoped change feed and drops
/// tombstones. Ordering uses the batch revision, not the resource version, because a hard
/// deleted resource recreated under the same id starts again at version 1. The coach memory
/// is not part of the change feed and is read from its own table.
/// </summary>
public sealed class AccountDataExportQuery(AppDbContext context) : IAccountDataExport
{
    public async Task<AccountDataExport> ExportAsync(CancellationToken cancellationToken = default)
    {
        await using IDbContextTransaction transaction = await context.Database.BeginTransactionAsync(
            IsolationLevel.RepeatableRead, cancellationToken);
        long revision = await context.ChangeBatches.AsNoTracking()
            .MaxAsync(batch => (long?)batch.Revision, cancellationToken) ?? 0;
        var latest = await (
                from item in context.ChangeItems.AsNoTracking()
                join batch in context.ChangeBatches.AsNoTracking() on item.BatchId equals batch.Id
                where !item.IsTombstone
                      && !(from newerItem in context.ChangeItems
                           join newerBatch in context.ChangeBatches on newerItem.BatchId equals newerBatch.Id
                           where newerItem.ResourceType == item.ResourceType
                                 && newerItem.ResourceId == item.ResourceId
                                 && newerBatch.Revision > batch.Revision
                           select newerItem.Id).Any()
                orderby item.ResourceType, item.ResourceId
                select new { item.ResourceType, item.ResourceId, item.ResourceVersion, item.SnapshotJson })
            .ToListAsync(cancellationToken);
        // Same snapshot as the resources; the query filter keeps it to the current user.
        List<CoachMemoryItem> memories = await context.CoachMemories.AsNoTracking()
            .OrderByDescending(item => item.CreatedAtUtc)
            .ThenBy(item => item.Id)
            .Select(item => new CoachMemoryItem(
                item.Id, item.Category, item.Text, item.CreatedAtUtc, item.UpdatedAtUtc, item.Version))
            .ToListAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new AccountDataExport(
            revision,
            latest.Select(item => new AccountExportResource(
                item.ResourceType,
                item.ResourceId,
                item.ResourceVersion,
                JsonDocument.Parse(item.SnapshotJson!).RootElement.Clone())).ToList(),
            memories);
    }
}
