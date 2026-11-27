using Gainer.Core.Access;

namespace Gainer.Infrastructure.Persistence;

/// <summary>A signed-in installation of the mobile app with its rotating refresh token.</summary>
public sealed class DeviceSession
{
    public Guid Id { get; set; }

    public Guid UserId { get; set; }

    public string DeviceName { get; set; } = string.Empty;

    /// <summary>App installation or connected assistant; decides which endpoints its tokens open.</summary>
    public DeviceSessionKind Kind { get; set; }

    /// <summary>SHA-256 hash of the OAuth client a connector session belongs to; null for app sessions.</summary>
    public byte[]? ConnectorClientHash { get; set; }

    /// <summary>SHA-256 hash of the current refresh token.</summary>
    public byte[] RefreshTokenHash { get; set; } = [];

    /// <summary>SHA-256 hash of the token replaced by the last rotation.</summary>
    public byte[]? PreviousRefreshTokenHash { get; set; }

    public DateTimeOffset? RotatedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset LastUsedAt { get; set; }

    public DateTimeOffset ExpiresAt { get; set; }

    public DateTimeOffset? RevokedAt { get; set; }

    public long Version { get; set; }

    public AppUser User { get; set; } = null!;

    /// <summary>Tokens replaced by grace-period retries, kept until they outlive the idle lifetime; loaded only for a grace-period retry.</summary>
    public List<DeviceSessionDiscardedToken> DiscardedTokens { get; set; } = [];
}
