namespace Gainer.Infrastructure.Persistence;

/// <summary>A refresh token a grace-period retry replaced; the real device never presents it, so its return revokes the session.</summary>
public sealed class DeviceSessionDiscardedToken
{
    public Guid SessionId { get; set; }

    /// <summary>SHA-256 hash of the discarded refresh token.</summary>
    public byte[] TokenHash { get; set; } = [];

    public DateTimeOffset DiscardedAt { get; set; }
}
