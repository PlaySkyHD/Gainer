using System.Data;
using Gainer.Contracts.Sync;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class SyncClientRegistry(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider) : ISyncClientRegistry
{
    public async Task<RegisteredSyncClient> RegisterAsync(
        RegisterSyncClientCommand command,
        CancellationToken cancellationToken = default)
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
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        SyncClient? client = await context.SyncClients.SingleOrDefaultAsync(
            item => item.Id == command.ClientId, cancellationToken);
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
}
