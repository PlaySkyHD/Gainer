using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

public sealed record WorkoutSetSnapshotValues(
    Guid SetId,
    decimal? WeightKg,
    int? Repetitions,
    decimal? Rir,
    string? Notes,
    bool IsCompleted,
    DateTime? CompletedAtUtc = null);

public sealed record WorkoutExerciseSnapshotValues(
    Guid WorkoutExerciseId,
    Guid? SourceExerciseId,
    string ExerciseNameSnapshot,
    int PlannedSets,
    int MinimumRepetitions,
    int MaximumRepetitions,
    decimal? TargetRir,
    int? RestSeconds,
    string? Notes,
    IReadOnlyList<WorkoutSetSnapshotValues> Sets);

public sealed record StartWorkoutMutation : ITypedMutation<WorkoutSnapshot>
{
    private StartWorkoutMutation(MutationMetadata metadata, Guid workoutId, Guid templateId)
    {
        Metadata = metadata;
        WorkoutId = workoutId;
        TemplateId = templateId;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.Workout, workoutId), 0));
    }
    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid WorkoutId { get; }
    public Guid TemplateId { get; }
    public static StartWorkoutMutation Create(MutationMetadata metadata, Guid workoutId, Guid templateId) =>
        workoutId == Guid.Empty || templateId == Guid.Empty
            ? throw new ArgumentException("Workout and template identifiers cannot be empty.")
            : new(metadata, workoutId, templateId);
}

public sealed record EditWorkoutMutation : ITypedMutation<WorkoutSnapshot>
{
    private EditWorkoutMutation(
        MutationMetadata metadata,
        Guid workoutId,
        long baseVersion,
        IReadOnlyList<WorkoutExerciseSnapshotValues> exercises)
    {
        Metadata = metadata;
        WorkoutId = workoutId;
        BaseVersion = baseVersion;
        Exercises = exercises;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.Workout, workoutId), baseVersion));
    }
    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid WorkoutId { get; }
    public long BaseVersion { get; }
    public IReadOnlyList<WorkoutExerciseSnapshotValues> Exercises { get; }
    public static EditWorkoutMutation Create(
        MutationMetadata metadata,
        Guid workoutId,
        long baseVersion,
        IReadOnlyList<WorkoutExerciseSnapshotValues> exercises)
    {
        if (workoutId == Guid.Empty)
        {
            throw new ArgumentException("Workout identifier cannot be empty.", nameof(workoutId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, workoutId, baseVersion, exercises);
    }
}

public sealed record WorkoutSnapshot(
    Guid WorkoutId,
    Guid? SourceTemplateId,
    string TemplateNameSnapshot,
    WorkoutStatus Status,
    IReadOnlyList<WorkoutExerciseSnapshotValues> Exercises,
    DateTime StartedAtUtc,
    DateTime? CompletedAtUtc,
    DateTime? DiscardedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.Workout, WorkoutId);
}

public sealed record CompleteWorkoutMutation : ITypedMutation<CompleteWorkoutResult>
{
    private CompleteWorkoutMutation(
        MutationMetadata metadata,
        Guid workoutId,
        long baseVersion,
        Guid? rotationId,
        long? rotationBaseVersion)
    {
        Metadata = metadata;
        WorkoutId = workoutId;
        BaseVersion = baseVersion;
        RotationId = rotationId;
        RotationBaseVersion = rotationBaseVersion;
        var expectations = new List<ResourceVersionExpectation>
        {
            ResourceVersionExpectation.Create(ResourceKey.Create(ResourceKind.Workout, workoutId), baseVersion),
        };
        if (rotationId is { } id && rotationBaseVersion is { } version)
        {
            expectations.Add(ResourceVersionExpectation.Create(ResourceKey.Create(ResourceKind.WorkoutRotation, id), version));
        }
        Scope = AtomicMutationScope.Create([.. expectations]);
    }
    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid WorkoutId { get; }
    public long BaseVersion { get; }
    public Guid? RotationId { get; }
    public long? RotationBaseVersion { get; }

    public static CompleteWorkoutMutation Create(
        MutationMetadata metadata,
        Guid workoutId,
        long baseVersion,
        Guid? rotationId = null,
        long? rotationBaseVersion = null)
    {
        if (workoutId == Guid.Empty) throw new ArgumentException("Workout identifier cannot be empty.", nameof(workoutId));
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        if ((rotationId is null) != (rotationBaseVersion is null) || rotationId == Guid.Empty || rotationBaseVersion is <= 0)
        {
            throw new ArgumentException("Rotation id and positive version must be supplied together.");
        }
        return new(metadata, workoutId, baseVersion, rotationId, rotationBaseVersion);
    }
}

public sealed record CompleteWorkoutResult(
    WorkoutSnapshot Workout,
    WorkoutRotationSnapshot? Rotation);

public sealed record DiscardWorkoutMutation : ITypedMutation<WorkoutSnapshot>
{
    private DiscardWorkoutMutation(MutationMetadata metadata, Guid workoutId, long baseVersion)
    {
        Metadata = metadata;
        WorkoutId = workoutId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.Workout, workoutId), baseVersion));
    }
    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid WorkoutId { get; }
    public long BaseVersion { get; }
    public static DiscardWorkoutMutation Create(MutationMetadata metadata, Guid workoutId, long baseVersion)
    {
        if (workoutId == Guid.Empty)
        {
            throw new ArgumentException("Workout identifier cannot be empty.", nameof(workoutId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, workoutId, baseVersion);
    }
}

public interface IWorkoutMutationHandler
{
    Task<WorkoutSnapshot> StartAsync(StartWorkoutMutation mutation, CancellationToken cancellationToken = default);
    Task<WorkoutSnapshot> EditAsync(EditWorkoutMutation mutation, CancellationToken cancellationToken = default);
    Task<CompleteWorkoutResult> CompleteAsync(CompleteWorkoutMutation mutation, CancellationToken cancellationToken = default);
    Task<WorkoutSnapshot> DiscardAsync(DiscardWorkoutMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class WorkoutValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The workout is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class WorkoutConflictException(string message) : Exception(message);

public sealed class WorkoutNotFoundException : Exception;
