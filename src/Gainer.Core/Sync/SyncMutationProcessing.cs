using System.Text.Json;
using Gainer.Core.Mutations;

namespace Gainer.Core.Sync;

public sealed record ProcessSyncMutationCommand(
    Guid MutationId,
    CanonicalMutationContent Content);

public sealed record ExecutedSyncChange(
    ResourceKey Resource,
    long Version,
    object? Snapshot,
    bool IsTombstone = false);

public sealed record SyncMutationExecutionResult(IReadOnlyList<ExecutedSyncChange> Changes);

public sealed record ProcessedSyncMutationResult(
    Guid MutationId,
    bool Replayed,
    long Revision,
    IReadOnlyList<ExecutedSyncChange> Changes);

public interface ISyncMutationExecutor
{
    Task<SyncMutationExecutionResult> ExecuteAsync(
        Guid mutationId,
        CanonicalMutationContent content,
        CancellationToken cancellationToken = default);
}

public interface ISyncMutationProcessor
{
    Task<ProcessedSyncMutationResult> ProcessAsync(
        ProcessSyncMutationCommand command,
        CancellationToken cancellationToken = default);
}

public abstract class SyncMutationException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

public class SyncMutationConflictException(string code, string message)
    : SyncMutationException(code, message);

public sealed class SyncMutationValidationException(string code, string message)
    : SyncMutationException(code, message);

public sealed class SyncUpgradeRequiredException()
    : SyncMutationConflictException("upgrade_required", "The client protocol is no longer supported.");
