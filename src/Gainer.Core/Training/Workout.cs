using Gainer.Core.Security;

namespace Gainer.Core.Training;

public sealed class Workout : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid? SourceTemplateId { get; init; }
    public string TemplateNameSnapshot { get; init; } = string.Empty;
    public WorkoutStatus Status { get; set; }
    public DateTime StartedAtUtc { get; init; }
    public DateTime? CompletedAtUtc { get; set; }
    public DateTime? DiscardedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}

public sealed class WorkoutExercise : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid WorkoutId { get; init; }
    public Guid? SourceExerciseId { get; init; }
    public string ExerciseNameSnapshot { get; set; } = string.Empty;
    public int Position { get; set; }
    public int PlannedSets { get; set; }
    public int MinimumRepetitions { get; set; }
    public int MaximumRepetitions { get; set; }
    public decimal? TargetRir { get; set; }
    public int? RestSeconds { get; set; }
    public string? Notes { get; set; }
    public DateTime? WorkoutCompletedAtUtc { get; set; }
}

public sealed class WorkoutSet : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid WorkoutId { get; init; }
    public Guid WorkoutExerciseId { get; init; }
    public int Position { get; set; }
    public decimal? WeightKg { get; set; }
    public int? Repetitions { get; set; }
    public decimal? Rir { get; set; }
    public string? Notes { get; set; }
    public bool IsCompleted { get; set; }
    public DateTime? CompletedAtUtc { get; set; }
}

public enum WorkoutStatus
{
    Running,
    Completed,
    Discarded,
}
