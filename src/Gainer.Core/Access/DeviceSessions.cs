namespace Gainer.Core.Access;

/// <summary>A device session and the refresh token issued for it. The token is returned only once.</summary>
public sealed record IssuedDeviceSession(Guid SessionId, Guid UserId, string RefreshToken, DateTimeOffset ExpiresAt);

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

    /// <summary>Exchanges a refresh token for a new one and extends the session.</summary>
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
