using System.Data;
using Gainer.Contracts.Sync;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

public sealed class SyncClientRegistry(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider) : ISyncClientRegistry
{
    public Task<RegisteredSyncClient> RegisterAsync(
        RegisterSyncClientCommand command,
        CancellationToken cancellationToken = default) =>
        MapConcurrencyConflictAsync(RegisterCoreAsync(command, cancellationToken));

    private async Task<RegisteredSyncClient> RegisterCoreAsync(
        RegisterSyncClientCommand command,
        CancellationToken cancellationToken)
    {
        Guid userId = userContext.UserId
            ?? throw new UnauthorizedAccessException("An authenticated user is required.");
        if (command.ClientId == Guid.Empty)
            throw new SyncMutationValidationException("invalid_client_id", "Client id is required.");
        string displayName = command.DisplayName.Trim();
        if (displayName.Length is < 1 or > 100)
            throw new SyncMutationValidationException("invalid_display_name", "Display name must contain 1 to 100 characters.");
        if (command.ProtocolVersion is not (SyncProtocol.PreviousVersion or SyncProtocol.CurrentVersion))
            throw new SyncUpgradeRequiredException();

        await using var transaction = await context.Database.BeginTransactionAsync(
            IsolationLevel.Serializable, cancellationToken);
        UserSyncState? state = await context.UserSyncStates
            .FromSqlInterpolated($"SELECT * FROM sync.user_state WHERE \"UserId\" = {userId} FOR UPDATE")
            .SingleOrDefaultAsync(cancellationToken);
        SyncClient? client = await context.SyncClients.SingleOrDefaultAsync(
            item => item.Id == command.ClientId, cancellationToken);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        if (client is null)
        {
            client = new SyncClient
            {
                Id = command.ClientId,
                DisplayName = displayName,
                ProtocolVersion = command.ProtocolVersion,
                RegisteredAtUtc = now,
                LastSeenAtUtc = now,
            };
            context.SyncClients.Add(client);
        }
        else
        {
            client.DisplayName = displayName;
            client.ProtocolVersion = command.ProtocolVersion;
            client.LastSeenAtUtc = now;
        }

        if (state is not null) await EnsureTakeOverAllowedAsync(userId, command, state, now, cancellationToken);

        if (state is null)
        {
            state = new UserSyncState
            {
                CurrentRevision = 0,
                ActiveClientId = command.ClientId,
                UpdatedAtUtc = now,
                Version = 1,
            };
            context.UserSyncStates.Add(state);
        }
        else if (command.TakeOverWriting && state.ActiveClientId != command.ClientId)
        {
            state.ActiveClientId = command.ClientId;
            state.UpdatedAtUtc = now;
            state.Version++;
        }

        await context.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new RegisteredSyncClient(
            client.Id,
            client.DisplayName,
            client.ProtocolVersion,
            state.ActiveClientId == client.Id,
            client.RegisteredAtUtc,
            client.LastSeenAtUtc);
    }

    private async Task EnsureTakeOverAllowedAsync(
        Guid userId,
        RegisterSyncClientCommand command,
        UserSyncState state,
        DateTime now,
        CancellationToken cancellationToken)
    {
        await ExpirePendingHandoversAsync(userId, now, cancellationToken);
        if (!command.TakeOverWriting || state.ActiveClientId == command.ClientId) return;
        if (state.HandoverRequired)
            throw new SyncMutationConflictException(
                "handover_required",
                "This account must use the verified device handover flow.");
        if (await context.SyncHandovers.AnyAsync(
                item => item.Status == SyncHandoverStatuses.Pending && item.ExpiresAtUtc > now,
                cancellationToken))
            throw new SyncMutationConflictException(
                "handover_in_progress",
                "A device handover is in progress.");
    }

    private async Task ExpirePendingHandoversAsync(Guid userId, DateTime now, CancellationToken cancellationToken)
    {
        List<SyncHandover> expired = await context.SyncHandovers
            .Where(item => item.UserId == userId
                && item.Status == SyncHandoverStatuses.Pending
                && item.ExpiresAtUtc <= now)
            .ToListAsync(cancellationToken);
        foreach (SyncHandover handover in expired)
        {
            handover.Status = SyncHandoverStatuses.Expired;
            handover.ProtectedCode = null;
        }
    }

    private static async Task<T> MapConcurrencyConflictAsync<T>(Task<T> operation)
    {
        try
        {
            return await operation;
        }
        catch (Exception exception) when (IsRetryableConcurrency(exception))
        {
            throw new SyncMutationConflictException(
                "concurrent_mutation",
                "The account changed concurrently. Retry the client registration.");
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
