namespace Gainer.Infrastructure.Persistence;

/// <summary>Hash-only, single-use invitation metadata stored beside Identity.</summary>
public sealed class AccountInvitation
{
    /// <summary>Stable invitation record identifier.</summary>
    public Guid Id { get; set; }

    /// <summary>The pending Identity account this invitation activates.</summary>
    public Guid UserId { get; set; }

    /// <summary>SHA-256 hash of the externally shared token.</summary>
    public byte[] TokenHash { get; set; } = [];

    /// <summary>Time after which the token is invalid.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>Time at which the token was consumed.</summary>
    public DateTimeOffset? UsedAt { get; set; }

    /// <summary>Time at which this token generation was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>Optimistic concurrency version used to claim a token once.</summary>
    public long Version { get; set; }

    /// <summary>The pending Identity account.</summary>
    public AppUser User { get; set; } = null!;
}
