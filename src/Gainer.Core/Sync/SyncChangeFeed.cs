using System.Text.Json;

namespace Gainer.Core.Sync;

public sealed record SyncFeedChange(
    string ResourceType,
    Guid ResourceId,
    long Version,
    bool IsTombstone,
    JsonElement? Snapshot);

public sealed record SyncFeedBatch(
    Guid BatchId,
    long Revision,
    Guid? OriginMutationId,
    IReadOnlyList<SyncFeedChange> Changes);

public sealed record SyncChangeFeedPage(
    long NextCursor,
    bool HasMore,
    IReadOnlyList<SyncFeedBatch> Batches);

public interface ISyncChangeFeed
{
    Task<SyncChangeFeedPage> GetAsync(long after, int limit, CancellationToken cancellationToken = default);
}
