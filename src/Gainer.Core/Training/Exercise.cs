namespace Gainer.Core.Training;

/// <summary>A global catalog exercise or a user-owned custom exercise.</summary>
public sealed class Exercise
{
    public Guid Id { get; init; }

    /// <summary>Null for immutable base-catalog entries.</summary>
    public Guid? OwnerUserId { get; init; }

    public string Name { get; set; } = string.Empty;

    public string? Description { get; set; }

    public string? TargetMuscle { get; set; }

    public string? MuscleGroup { get; set; }

    public string? Equipment { get; set; }

    public bool IsArchived { get; set; }

    public string? CatalogVersion { get; init; }

    public DateTime CreatedAtUtc { get; init; }

    public DateTime UpdatedAtUtc { get; set; }

    public long Version { get; set; }
}
