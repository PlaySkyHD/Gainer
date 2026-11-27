namespace Gainer.Core.Access;

/// <summary>What a session belongs to: an installation of the app or an external AI assistant.</summary>
public enum DeviceSessionKind
{
    /// <summary>A signed-in installation of the mobile app.</summary>
    App = 0,

    /// <summary>An external assistant connected through OAuth; its tokens open only the MCP endpoint.</summary>
    Connector = 1,
}

/// <summary>A device session and the refresh token issued for it. The token is returned only once.</summary>
public sealed record IssuedDeviceSession(
    Guid SessionId,
    Guid UserId,
    string RefreshToken,
    DateTimeOffset ExpiresAt,
    DeviceSessionKind Kind = DeviceSessionKind.App);

/// <summary>An active connected assistant as shown in the account settings.</summary>
public sealed record ConnectorSessionSummary(
    Guid SessionId,
    string Name,
    DateTimeOffset CreatedAt,
    DateTimeOffset LastUsedAt);

/// <summary>Possible outcomes of a refresh attempt.</summary>
public enum DeviceSessionRefreshStatus
{
    /// <summary>The token was rotated and a new one issued.</summary>
    Refreshed,

    /// <summary>The token is unknown, expired, revoked, or belongs to an inactive account.</summary>
    Invalid,

    /// <summary>An already rotated token was presented again; the whole session was revoked.</summary>
    ReuseDetected,
}

/// <summary>Result of a refresh attempt; <see cref="Session"/> is set only when refreshed.</summary>
public sealed record DeviceSessionRefreshResult(DeviceSessionRefreshStatus Status, IssuedDeviceSession? Session = null);

/// <summary>Creates, rotates, and revokes long-lived device sessions of the mobile app.</summary>
public interface IDeviceSessionService
{
    /// <summary>Starts a new session for an authenticated, active account.</summary>
    Task<IssuedDeviceSession> CreateAsync(
        Guid userId,
        string deviceName,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Starts a session for an external assistant the account owner just approved. An earlier session
    /// of the same client for this account is revoked, so reconnecting leaves one connection.
    /// </summary>
    Task<IssuedDeviceSession> CreateConnectorAsync(
        Guid userId,
        string clientName,
        string connectorClient,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Rotates the refresh token of a connector session created for <paramref name="connectorClient"/>.
    /// Tokens of app sessions or of other clients are rejected without being rotated.
    /// </summary>
    Task<DeviceSessionRefreshResult> RefreshConnectorAsync(
        string refreshToken,
        string connectorClient,
        CancellationToken cancellationToken = default);

    /// <summary>Lists the active connector sessions of the account, newest first.</summary>
    Task<IReadOnlyList<ConnectorSessionSummary>> ListConnectorsAsync(
        Guid userId,
        CancellationToken cancellationToken = default);

    /// <summary>Revokes one connector session of the account; false when there is no such active session.</summary>
    Task<bool> RevokeConnectorAsync(
        Guid sessionId,
        Guid userId,
        CancellationToken cancellationToken = default);

    /// <summary>Exchanges the refresh token of an app session for a new one and extends the session; connector tokens are rejected without being rotated.</summary>
    Task<DeviceSessionRefreshResult> RefreshAsync(
        string refreshToken,
        CancellationToken cancellationToken = default);

    /// <summary>Returns whether the session is unexpired, unrevoked, and owned by an active account.</summary>
    Task<bool> IsActiveAsync(
        Guid sessionId,
        Guid userId,
        CancellationToken cancellationToken = default);

    /// <summary>Returns when the account signed in on this session, or null when the session is not active.</summary>
    Task<DateTimeOffset?> GetSignedInAtAsync(
        Guid sessionId,
        Guid userId,
        CancellationToken cancellationToken = default);

    /// <summary>Revokes one session of the given account.</summary>
    Task RevokeAsync(
        Guid sessionId,
        Guid userId,
        CancellationToken cancellationToken = default);

    /// <summary>Revokes every session of the given account.</summary>
    Task RevokeAllAsync(Guid userId, CancellationToken cancellationToken = default);
}
