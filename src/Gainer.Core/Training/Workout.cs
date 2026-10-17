using Gainer.Core.Security;

namespace Gainer.Core.Training;

public sealed class Workout : UserOwnedEntity
{
    public Guid Id { get; init; }
    public string Title { get; set; } = string.Empty;
    public string? Notes { get; set; }
    public DateTime StartedAtUtc { get; set; }

    /// <summary>Null while the workout is active.</summary>
    public DateTime? EndedAtUtc { get; set; }
    public PreviousValueSource PreviousValueSource { get; set; }
    public Guid? SourcePlanId { get; set; }
    public Guid? SourceWorkoutId { get; set; }
    public DateTime? DeletedAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}

public sealed class WorkoutExercise : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid WorkoutId { get; init; }
    public Guid SourceExerciseId { get; set; }
    public string ExerciseNameSnapshot { get; set; } = string.Empty;
    public ExerciseType ExerciseTypeSnapshot { get; set; }
    public int Position { get; set; }
    public string? Notes { get; set; }
    public Guid? SupersetId { get; set; }
}

public sealed class WorkoutSet : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid WorkoutId { get; init; }
    public Guid WorkoutExerciseId { get; init; }
    public int Position { get; set; }
    public WorkoutSetType SetType { get; set; }
    public decimal? WeightKg { get; set; }
    public int? Repetitions { get; set; }
    public decimal? Rir { get; set; }
    public string? Notes { get; set; }
}

public enum WorkoutSetType
{
    Normal,
    Warmup,
    Dropset,
}

/// <summary>Maps set types to their persisted values; unknown values fall back to a normal set.</summary>
public static class WorkoutSetTypes
{
    public static string ToStorageValue(WorkoutSetType value) => value switch
    {
        WorkoutSetType.Normal => "normal",
        WorkoutSetType.Warmup => "warmup",
        WorkoutSetType.Dropset => "dropset",
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, "Unknown set type."),
    };

    public static WorkoutSetType ParseOrNormal(string? value) =>
        TryParse(value, out WorkoutSetType type) ? type : WorkoutSetType.Normal;

    public static bool TryParse(string? value, out WorkoutSetType type)
    {
        WorkoutSetType[] matches = Enum.GetValues<WorkoutSetType>()
            .Where(candidate => string.Equals(value, ToStorageValue(candidate), StringComparison.OrdinalIgnoreCase))
            .ToArray();
        type = matches.Length > 0 ? matches[0] : default;
        return matches.Length > 0;
    }
}

public enum PreviousValueSource
{
    Exercise,
    Plan,
    Workout,
}

/// <summary>Maps previous-value sources to their wire values.</summary>
public static class PreviousValueSources
{
    public static string ToStorageValue(PreviousValueSource value) => value switch
    {
        PreviousValueSource.Exercise => "exercise",
        PreviousValueSource.Plan => "plan",
        PreviousValueSource.Workout => "workout",
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, "Unknown previous value source."),
    };

    public static PreviousValueSource Parse(string? value) =>
        TryParse(value, out PreviousValueSource source) ? source : throw new UnknownPreviousValueSourceException(value);

    public static bool TryParse(string? value, out PreviousValueSource source)
    {
        PreviousValueSource[] matches = Enum.GetValues<PreviousValueSource>()
            .Where(candidate => string.Equals(value, ToStorageValue(candidate), StringComparison.Ordinal))
            .ToArray();
        source = matches.Length > 0 ? matches[0] : default;
        return matches.Length > 0;
    }
}

public sealed class UnknownPreviousValueSourceException(string? value)
    : ArgumentException($"The previous value source '{value}' is unknown.");
