namespace Gainer.Core.Sync;

public sealed record RegisterSyncClientCommand(
    Guid ClientId,
    string DisplayName,
    int ProtocolVersion,
    bool TakeOverWriting);

public sealed record RegisteredSyncClient(
    Guid ClientId,
    string DisplayName,
    int ProtocolVersion,
    bool IsActiveWriter,
    DateTime RegisteredAtUtc,
    DateTime LastSeenAtUtc);

public interface ISyncClientRegistry
{
    Task<RegisteredSyncClient> RegisterAsync(
        RegisterSyncClientCommand command,
        CancellationToken cancellationToken = default);
}
