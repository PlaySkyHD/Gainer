using Gainer.Core.Security;

namespace Gainer.Core.Sync;

public sealed class SyncClient : UserOwnedEntity
{
    public Guid Id { get; init; }
    public string DisplayName { get; set; } = string.Empty;
    public int ProtocolVersion { get; set; }
    public DateTime RegisteredAtUtc { get; init; }
    public DateTime LastSeenAtUtc { get; set; }
}

public sealed class UserSyncState : UserOwnedEntity
{
    public long CurrentRevision { get; set; }
    public Guid? ActiveClientId { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}

public sealed class ProcessedMutation : UserOwnedEntity
{
    public Guid MutationId { get; init; }
    public Guid ClientId { get; init; }
    public long ClientSequence { get; init; }
    public byte[] ContentHash { get; init; } = [];
    public string ResultJson { get; init; } = string.Empty;
    public long Revision { get; init; }
    public DateTime AppliedAtUtc { get; init; }
}

public sealed class ChangeBatch : UserOwnedEntity
{
    public Guid Id { get; init; }
    public long Revision { get; init; }
    public Guid? MutationId { get; init; }
    public DateTime CreatedAtUtc { get; init; }
}

public sealed class ChangeItem : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid BatchId { get; init; }
    public int Position { get; init; }
    public string ResourceType { get; init; } = string.Empty;
    public Guid ResourceId { get; init; }
    public long ResourceVersion { get; init; }
    public bool IsTombstone { get; init; }
    public string? SnapshotJson { get; init; }
}
