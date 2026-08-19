using Gainer.Core.Security;

namespace Gainer.Core.BodyTracking;

/// <summary>A historical or currently active body-composition goal in canonical units.</summary>
public sealed class BodyGoal : UserOwnedEntity
{
    public Guid Id { get; init; }

    public BodyGoalKind Kind { get; init; }

    public decimal StartWeightKg { get; init; }

    public decimal TargetWeightKg { get; init; }

    public DateOnly StartDate { get; init; }

    public DateOnly? TargetDate { get; init; }

    public DateTime CreatedAtUtc { get; init; }

    public DateTime? EndedAtUtc { get; set; }

    public long Version { get; set; }
}

public enum BodyGoalKind
{
    Bulk,
    Maintain,
    Cut,
}
