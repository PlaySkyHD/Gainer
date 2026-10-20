namespace Gainer.Infrastructure.Persistence;

/// <summary>A signed-in installation of the mobile app with its rotating refresh token.</summary>
public sealed class DeviceSession
{
    public Guid Id { get; set; }

    public Guid UserId { get; set; }

    public string DeviceName { get; set; } = string.Empty;

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
}
