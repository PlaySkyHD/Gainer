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

    /// <summary>Muscle keys from <see cref="MuscleKeys"/> that the exercise mainly trains.</summary>
    public string[] PrimaryMuscles { get; set; } = [];

    /// <summary>Muscle keys from <see cref="MuscleKeys"/> that the exercise also trains; they count half.</summary>
    public string[] SecondaryMuscles { get; set; } = [];

    public string? Equipment { get; set; }

    public ExerciseType ExerciseType { get; set; } = ExerciseType.Strength;

    public string? Notes { get; set; }

    /// <summary>Share of the body weight that counts as load, 0 to 1 inclusive.</summary>
    public decimal? BodyweightFactor { get; set; }

    /// <summary>Multiplier for the added weight, greater than 0 and at most 10.</summary>
    public decimal? WeightFactor { get; set; }

    public bool IsArchived { get; set; }

    public string? CatalogVersion { get; init; }

    public DateTime CreatedAtUtc { get; init; }

    public DateTime UpdatedAtUtc { get; set; }

    public long Version { get; set; }
}
