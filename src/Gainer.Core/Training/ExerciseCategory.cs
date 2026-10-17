namespace Gainer.Core.Training;

/// <summary>A base category (OwnerUserId is null, immutable) or a user-owned category.</summary>
public sealed class ExerciseCategory
{
    public Guid Id { get; init; }

    /// <summary>Null for immutable base-catalog categories.</summary>
    public Guid? OwnerUserId { get; init; }

    public string Name { get; set; } = string.Empty;

    public bool IsArchived { get; set; }

    public string? CatalogVersion { get; init; }

    public DateTime CreatedAtUtc { get; init; }

    public DateTime UpdatedAtUtc { get; set; }

    public long Version { get; set; }
}

/// <summary>Links an exercise to a category; ownership follows the exercise.</summary>
public sealed class ExerciseCategoryAssignment
{
    public Guid ExerciseId { get; init; }

    public Guid CategoryId { get; init; }
}
