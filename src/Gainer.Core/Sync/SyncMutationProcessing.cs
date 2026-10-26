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

public sealed record BeginSyncHandoverCommand(
    Guid RequestId,
    Guid SourceClientId,
    long ExpectedRevision);

public sealed record BeginSyncHandoverResult(
    Guid HandoverId,
    string OneTimeCode,
    long FrozenRevision,
    DateTime ExpiresAtUtc);

public sealed record CompleteSyncHandoverCommand(
    Guid HandoverId,
    string OneTimeCode,
    Guid TargetClientId,
    long CaughtUpRevision);

public sealed record CompleteSyncHandoverResult(
    Guid HandoverId,
    Guid TargetClientId,
    long FrozenRevision,
    bool IsActiveWriter,
    DateTime CompletedAtUtc);

public sealed record CancelSyncHandoverCommand(
    Guid HandoverId,
    Guid SourceClientId);

public interface ISyncHandoverService
{
    Task<BeginSyncHandoverResult> BeginAsync(
        BeginSyncHandoverCommand command,
        CancellationToken cancellationToken = default);

    Task<CompleteSyncHandoverResult> CompleteAsync(
        CompleteSyncHandoverCommand command,
        CancellationToken cancellationToken = default);

    Task CancelAsync(
        CancelSyncHandoverCommand command,
        CancellationToken cancellationToken = default);
}

public sealed class SyncHandoverException(string code, string message, int statusCode = 409)
    : Exception(message)
{
    public string Code { get; } = code;
    public int StatusCode { get; } = statusCode;
}

public abstract class SyncMutationException(string code, string message, Exception? innerException = null)
    : Exception(message, innerException)
{
    public string Code { get; } = code;
}

public class SyncMutationConflictException(string code, string message)
    : SyncMutationException(code, message);

/// <summary>A permanent rejection; <paramref name="innerException"/> keeps the server-side cause for logs only.</summary>
public sealed class SyncMutationValidationException(string code, string message, Exception? innerException = null)
    : SyncMutationException(code, message, innerException);

public sealed class SyncUpgradeRequiredException()
    : SyncMutationConflictException("upgrade_required", "The client protocol is no longer supported.");
