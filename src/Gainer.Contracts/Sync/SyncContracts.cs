using System.ComponentModel.DataAnnotations;
using System.Text.Json;

namespace Gainer.Contracts.Sync;

public static class SyncProtocol
{
    public const int PreviousVersion = 1;
    public const int CurrentVersion = 2;
    public const int MaximumResourcesPerMutation = 100;
    public const int MaximumBatchesPerPull = 200;
}

public sealed record ResourceVersionRequest
{
    public ResourceVersionRequest(string resourceType, Guid resourceId, long baseVersion)
    {
        ResourceType = resourceType;
        ResourceId = resourceId;
        BaseVersion = baseVersion;
    }

    [Required, StringLength(64, MinimumLength = 1)]
    public string ResourceType { get; init; }

    public Guid ResourceId { get; init; }

    public long BaseVersion { get; init; }
}

public sealed record PushMutationRequest
{
    public PushMutationRequest(
        int protocolVersion,
        Guid clientId,
        long clientSequence,
        string operation,
        IReadOnlyList<ResourceVersionRequest> resources,
        Guid? dependsOnMutationId,
        JsonElement payload)
    {
        ProtocolVersion = protocolVersion;
        ClientId = clientId;
        ClientSequence = clientSequence;
        Operation = operation;
        Resources = resources;
        DependsOnMutationId = dependsOnMutationId;
        Payload = payload;
    }

    public int ProtocolVersion { get; init; }

    public Guid ClientId { get; init; }

    public long ClientSequence { get; init; }

    [Required, StringLength(64, MinimumLength = 1)]
    public string Operation { get; init; }

    [Required, MinLength(1), MaxLength(SyncProtocol.MaximumResourcesPerMutation)]
    public IReadOnlyList<ResourceVersionRequest> Resources { get; init; }

    public Guid? DependsOnMutationId { get; init; }

    public JsonElement Payload { get; init; }
}

public sealed record SyncResourceResult(
    string ResourceType,
    Guid ResourceId,
    long Version,
    JsonElement? Snapshot,
    bool IsTombstone);

public sealed record PushMutationResponse(
    Guid MutationId,
    bool Replayed,
    long Revision,
    IReadOnlyList<SyncResourceResult> Resources);

public sealed record SyncConflictResponse(
    string Code,
    string Message,
    IReadOnlyList<SyncResourceResult> CurrentResources);

public sealed record SyncChangeResponse(
    string ResourceType,
    Guid ResourceId,
    long Version,
    bool IsTombstone,
    JsonElement? Snapshot);

public sealed record SyncChangeBatchResponse(
    Guid BatchId,
    long Revision,
    Guid? OriginMutationId,
    IReadOnlyList<SyncChangeResponse> Changes);

public sealed record PullChangesResponse(
    int ProtocolVersion,
    long NextCursor,
    bool HasMore,
    IReadOnlyList<SyncChangeBatchResponse> Batches);

public sealed record RegisterSyncClientRequest
{
    public RegisterSyncClientRequest(
        Guid clientId,
        string displayName,
        int protocolVersion,
        bool takeOverWriting)
    {
        ClientId = clientId;
        DisplayName = displayName;
        ProtocolVersion = protocolVersion;
        TakeOverWriting = takeOverWriting;
    }

    public Guid ClientId { get; init; }

    [Required, StringLength(100, MinimumLength = 1)]
    public string DisplayName { get; init; }

    public int ProtocolVersion { get; init; }

    public bool TakeOverWriting { get; init; }
}

public sealed record SyncClientResponse(
    Guid ClientId,
    string DisplayName,
    int ProtocolVersion,
    bool IsActiveWriter,
    DateTime RegisteredAtUtc,
    DateTime LastSeenAtUtc);

public sealed record BeginSyncHandoverRequest(
    Guid RequestId,
    Guid SourceClientId,
    long ExpectedRevision);

public sealed record BeginSyncHandoverResponse(
    Guid HandoverId,
    string OneTimeCode,
    long FrozenRevision,
    DateTime ExpiresAtUtc);

public sealed record CompleteSyncHandoverRequest(
    [Required, StringLength(128, MinimumLength = 1)] string OneTimeCode,
    Guid TargetClientId,
    long CaughtUpRevision);

public sealed record CompleteSyncHandoverResponse(
    Guid HandoverId,
    Guid TargetClientId,
    long FrozenRevision,
    bool IsActiveWriter,
    DateTime CompletedAtUtc);

public sealed record CancelSyncHandoverRequest(Guid SourceClientId);
