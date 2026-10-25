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

/// <param name="UpgradeRequired">
/// True when the page stops before a batch the client cannot apply; the cursor never moves past that batch.
/// </param>
public sealed record SyncChangeFeedPage(
    long NextCursor,
    bool HasMore,
    IReadOnlyList<SyncFeedBatch> Batches,
    bool UpgradeRequired = false);

public interface ISyncChangeFeed
{
    /// <summary>Reads every change after <paramref name="after"/> regardless of the client protocol.</summary>
    Task<SyncChangeFeedPage> GetAsync(long after, int limit, CancellationToken cancellationToken = default);

    /// <summary>
    /// Reads changes for a client speaking <paramref name="clientProtocolVersion"/>. The page ends before the first
    /// batch holding a resource type the client does not understand (see <see cref="SyncResourceProtocol"/>).
    /// </summary>
    Task<SyncChangeFeedPage> GetAsync(
        long after,
        int limit,
        int clientProtocolVersion,
        CancellationToken cancellationToken = default);
}
