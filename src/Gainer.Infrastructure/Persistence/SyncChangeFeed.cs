using System.Text.Json;
using Gainer.Core.Sync;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class SyncChangeFeed(AppDbContext context) : ISyncChangeFeed
{
    public async Task<SyncChangeFeedPage> GetAsync(
        long after,
        int limit,
        CancellationToken cancellationToken = default)
    {
        if (after < 0 || limit is < 1 or > 200) throw new ArgumentOutOfRangeException(nameof(limit));
        List<ChangeBatch> batches = await context.ChangeBatches.AsNoTracking()
            .Where(item => item.Revision > after)
            .OrderBy(item => item.Revision)
            .Take(limit)
            .ToListAsync(cancellationToken);
        if (batches.Count == 0) return new SyncChangeFeedPage(after, false, []);
        Guid[] batchIds = batches.Select(item => item.Id).ToArray();
        List<ChangeItem> items = await context.ChangeItems.AsNoTracking()
            .Where(item => batchIds.Contains(item.BatchId))
            .OrderBy(item => item.BatchId)
            .ThenBy(item => item.Position)
            .ToListAsync(cancellationToken);
        List<SyncFeedBatch> result = batches.Select(batch => new SyncFeedBatch(
            batch.Id,
            batch.Revision,
            batch.MutationId,
            items.Where(item => item.BatchId == batch.Id).OrderBy(item => item.Position)
                .Select(item => new SyncFeedChange(
                    item.ResourceType,
                    item.ResourceId,
                    item.ResourceVersion,
                    item.IsTombstone,
                    item.SnapshotJson is null ? null : JsonDocument.Parse(item.SnapshotJson).RootElement.Clone()))
                .ToList())).ToList();
        long nextCursor = batches[^1].Revision;
        bool hasMore = await context.ChangeBatches.AsNoTracking()
            .AnyAsync(item => item.Revision > nextCursor, cancellationToken);
        return new SyncChangeFeedPage(nextCursor, hasMore, result);
    }
}
