using System.Data;
using System.Security.Cryptography;
using System.Text;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

public sealed class SyncHandoverService(
    AppDbContext context,
    IUserContext userContext,
    IDataProtectionProvider protectionProvider,
    TimeProvider timeProvider) : ISyncHandoverService
{
    private const string InvalidHandoverRequestCode = "invalid_handover_request";
    private static readonly TimeSpan HandoverLifetime = TimeSpan.FromMinutes(15);
    private readonly ITimeLimitedDataProtector codeProtector = protectionProvider
        .CreateProtector("Gainer.SyncHandover.StartRetry.v1")
        .ToTimeLimitedDataProtector();

    public Task<BeginSyncHandoverResult> BeginAsync(
        BeginSyncHandoverCommand command,
        CancellationToken cancellationToken = default) =>
        MapConcurrencyConflictAsync(BeginCoreAsync(command, cancellationToken));

    private async Task<BeginSyncHandoverResult> BeginCoreAsync(
        BeginSyncHandoverCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        Guid userId = RequireUserId();
        if (command.RequestId == Guid.Empty || command.SourceClientId == Guid.Empty || command.ExpectedRevision < 0)
            throw new SyncHandoverException(InvalidHandoverRequestCode, "The handover request is invalid.", 422);

        await using var transaction = await context.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        UserSyncState state = await LockUserStateAsync(userId, cancellationToken);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;

        SyncHandover? requestRetry = await context.SyncHandovers.SingleOrDefaultAsync(
            item => item.RequestId == command.RequestId,
            cancellationToken);
        if (requestRetry is not null)
            return await BeginRetryAsync(requestRetry, command, now, transaction, cancellationToken);

        await ExpirePendingHandoversAsync(userId, now, cancellationToken);
        await context.SaveChangesAsync(cancellationToken);
        if (state.ActiveClientId != command.SourceClientId)
            throw new SyncHandoverException("inactive_client", "Only the active writing device can begin a handover.");
        if (state.CurrentRevision != command.ExpectedRevision)
            throw new SyncHandoverException("stale_revision", "The server changed after the source confirmed its revision.");
        if (await context.SyncHandovers.AnyAsync(
                item => item.Status == SyncHandoverStatuses.Pending && item.ExpiresAtUtc > now,
                cancellationToken))
            throw new SyncHandoverException("handover_in_progress", "A device handover is already in progress.");

        string oneTimeCode = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        var handover = new SyncHandover
        {
            Id = Guid.NewGuid(),
            RequestId = command.RequestId,
            SourceClientId = command.SourceClientId,
            FrozenRevision = state.CurrentRevision,
            CodeHash = SHA256.HashData(Encoding.UTF8.GetBytes(oneTimeCode)),
            ProtectedCode = codeProtector.Protect(oneTimeCode, HandoverLifetime),
            ExpiresAtUtc = now.Add(HandoverLifetime),
            Status = SyncHandoverStatuses.Pending,
            CreatedAtUtc = now,
        };
        context.SyncHandovers.Add(handover);
        await context.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new BeginSyncHandoverResult(handover.Id, oneTimeCode, handover.FrozenRevision, handover.ExpiresAtUtc);
    }

    private async Task<BeginSyncHandoverResult> BeginRetryAsync(
        SyncHandover requestRetry,
        BeginSyncHandoverCommand command,
        DateTime now,
        IDbContextTransaction transaction,
        CancellationToken cancellationToken)
    {
        if (requestRetry.SourceClientId != command.SourceClientId || requestRetry.FrozenRevision != command.ExpectedRevision)
            throw new SyncHandoverException("handover_request_reused", "The handover request id was already used with different values.");
        if (requestRetry.Status == SyncHandoverStatuses.Pending && requestRetry.ExpiresAtUtc > now)
        {
            string retryCode;
            try
            {
                retryCode = codeProtector.Unprotect(
                    requestRetry.ProtectedCode ?? throw new CryptographicException("The retry code is no longer available."),
                    out DateTimeOffset codeExpiration);
                if (codeExpiration <= now)
                    throw new CryptographicException("The retry code has expired.");
            }
            catch (CryptographicException)
            {
                throw new SyncHandoverException("handover_retry_unavailable", "The pending handover must be cancelled or allowed to expire.");
            }
            await transaction.CommitAsync(cancellationToken);
            return new BeginSyncHandoverResult(
                requestRetry.Id, retryCode, requestRetry.FrozenRevision, requestRetry.ExpiresAtUtc);
        }
        if (requestRetry.Status == SyncHandoverStatuses.Pending)
        {
            Expire(requestRetry);
            await context.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        else
        {
            await transaction.CommitAsync(cancellationToken);
        }
        throw new SyncHandoverException("handover_not_pending", "The handover request is no longer active.");
    }

    public Task<CompleteSyncHandoverResult> CompleteAsync(
        CompleteSyncHandoverCommand command,
        CancellationToken cancellationToken = default) =>
        MapConcurrencyConflictAsync(CompleteCoreAsync(command, cancellationToken));

    private async Task<CompleteSyncHandoverResult> CompleteCoreAsync(
        CompleteSyncHandoverCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        Guid userId = RequireUserId();
        ValidateHandoverId(command.HandoverId);
        if (command.TargetClientId == Guid.Empty || command.CaughtUpRevision < 0 || string.IsNullOrWhiteSpace(command.OneTimeCode))
            throw new SyncHandoverException(InvalidHandoverRequestCode, "The handover request is invalid.", 422);

        await using var transaction = await context.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        UserSyncState state = await LockUserStateAsync(userId, cancellationToken);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        SyncHandover handover = await context.SyncHandovers.SingleOrDefaultAsync(
            item => item.Id == command.HandoverId,
            cancellationToken)
            ?? throw new SyncHandoverException("handover_not_found", "The handover was not found.", 404);
        ValidateCode(handover, command.OneTimeCode);

        if (handover.Status == SyncHandoverStatuses.Completed)
        {
            if (handover.TargetClientId != command.TargetClientId)
                throw new SyncHandoverException("handover_already_consumed", "The handover was completed by another device.");
            if (command.CaughtUpRevision != handover.FrozenRevision)
                throw new SyncHandoverException("stale_revision", "The target did not confirm the frozen server revision.");
            await transaction.CommitAsync(cancellationToken);
            return new CompleteSyncHandoverResult(
                handover.Id,
                command.TargetClientId,
                handover.FrozenRevision,
                state.ActiveClientId == command.TargetClientId,
                handover.CompletedAtUtc ?? throw new InvalidOperationException("A completed handover has no completion time."));
        }

        if (handover.Status != SyncHandoverStatuses.Pending)
            throw new SyncHandoverException("handover_not_pending", "The handover is no longer active.");
        if (handover.ExpiresAtUtc <= now)
        {
            Expire(handover);
            await context.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            throw new SyncHandoverException("handover_expired", "The handover has expired.");
        }
        if (command.TargetClientId == handover.SourceClientId)
            throw new SyncHandoverException("invalid_handover_target", "The target must be a different registered device.");
        if (state.ActiveClientId != handover.SourceClientId)
            throw new SyncHandoverException("inactive_source", "The source device is no longer the active writer.");
        if (command.CaughtUpRevision != handover.FrozenRevision)
            throw new SyncHandoverException("stale_revision", "The target has not confirmed the frozen server revision.");
        bool targetRegistered = await context.SyncClients.AnyAsync(
            item => item.Id == command.TargetClientId,
            cancellationToken);
        if (!targetRegistered)
            throw new SyncHandoverException("target_not_registered", "The target device must register before completing the handover.");

        state.ActiveClientId = command.TargetClientId;
        state.HandoverRequired = true;
        state.UpdatedAtUtc = now;
        state.Version++;
        handover.TargetClientId = command.TargetClientId;
        handover.Status = SyncHandoverStatuses.Completed;
        handover.CompletedAtUtc = now;
        handover.ProtectedCode = null;
        await context.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new CompleteSyncHandoverResult(
            handover.Id, command.TargetClientId, handover.FrozenRevision, true, now);
    }

    public Task CancelAsync(
        CancelSyncHandoverCommand command,
        CancellationToken cancellationToken = default) =>
        MapConcurrencyConflictAsync(CancelCoreAsync(command, cancellationToken));

    private async Task CancelCoreAsync(
        CancelSyncHandoverCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        Guid userId = RequireUserId();
        ValidateHandoverId(command.HandoverId);
        if (command.SourceClientId == Guid.Empty)
            throw new SyncHandoverException(InvalidHandoverRequestCode, "The handover request is invalid.", 422);

        await using var transaction = await context.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        UserSyncState state = await LockUserStateAsync(userId, cancellationToken);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        SyncHandover handover = await context.SyncHandovers.SingleOrDefaultAsync(
            item => item.Id == command.HandoverId,
            cancellationToken)
            ?? throw new SyncHandoverException("handover_not_found", "The handover was not found.", 404);
        if (handover.SourceClientId != command.SourceClientId)
            throw new SyncHandoverException("handover_source_mismatch", "Only the source device can cancel this handover.");
        if (handover.Status == SyncHandoverStatuses.Completed)
            throw new SyncHandoverException("handover_already_completed", "A completed handover cannot be reversed.");
        if (handover.Status is SyncHandoverStatuses.Cancelled or SyncHandoverStatuses.Expired)
        {
            await transaction.CommitAsync(cancellationToken);
            return;
        }
        if (state.ActiveClientId != handover.SourceClientId)
            throw new SyncHandoverException("inactive_source", "The source device is no longer the active writer.");

        if (handover.ExpiresAtUtc <= now) Expire(handover);
        else
        {
            handover.Status = SyncHandoverStatuses.Cancelled;
            handover.ProtectedCode = null;
        }
        await context.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    private Guid RequireUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private async Task<UserSyncState> LockUserStateAsync(Guid userId, CancellationToken cancellationToken) =>
        await context.UserSyncStates
            .FromSqlInterpolated($"SELECT * FROM sync.user_state WHERE \"UserId\" = {userId} FOR UPDATE")
            .SingleOrDefaultAsync(cancellationToken)
        ?? throw new SyncHandoverException("writer_not_registered", "The account has no registered writing device.");

    private async Task ExpirePendingHandoversAsync(Guid userId, DateTime now, CancellationToken cancellationToken)
    {
        List<SyncHandover> expired = await context.SyncHandovers
            .Where(item => item.UserId == userId
                && item.Status == SyncHandoverStatuses.Pending
                && item.ExpiresAtUtc <= now)
            .ToListAsync(cancellationToken);
        foreach (SyncHandover handover in expired) Expire(handover);
    }

    private static void Expire(SyncHandover handover)
    {
        handover.Status = SyncHandoverStatuses.Expired;
        handover.ProtectedCode = null;
    }

    private static void ValidateHandoverId(Guid handoverId)
    {
        if (handoverId == Guid.Empty)
            throw new SyncHandoverException(InvalidHandoverRequestCode, "The handover id is invalid.", 422);
    }

    private static void ValidateCode(SyncHandover handover, string code)
    {
        byte[] supplied = SHA256.HashData(Encoding.UTF8.GetBytes(code));
        if (!CryptographicOperations.FixedTimeEquals(handover.CodeHash, supplied))
            throw new SyncHandoverException("invalid_handover_code", "The handover code is invalid.");
    }

    private static async Task<T> MapConcurrencyConflictAsync<T>(Task<T> operation)
    {
        try
        {
            return await operation;
        }
        catch (Exception exception) when (IsRetryableConcurrency(exception))
        {
            throw new SyncHandoverException(
                "concurrent_handover",
                "The account changed concurrently. Retry the handover request.");
        }
    }

    private static async Task MapConcurrencyConflictAsync(Task operation)
    {
        try
        {
            await operation;
        }
        catch (Exception exception) when (IsRetryableConcurrency(exception))
        {
            throw new SyncHandoverException(
                "concurrent_handover",
                "The account changed concurrently. Retry the handover request.");
        }
    }

    private static bool IsRetryableConcurrency(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            if (current is PostgresException postgres && postgres.SqlState is
                PostgresErrorCodes.SerializationFailure or PostgresErrorCodes.DeadlockDetected)
                return true;
        }
        return false;
    }
}
