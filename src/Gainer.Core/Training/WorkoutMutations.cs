using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

public sealed record WorkoutSetValues(
    Guid SetId,
    string SetType,
    decimal? WeightKg,
    int? Repetitions,
    decimal? Rir,
    string? Notes);

public sealed record WorkoutExerciseValues(
    Guid WorkoutExerciseId,
    Guid SourceExerciseId,
    string ExerciseNameSnapshot,
    string ExerciseTypeSnapshot,
    string? Notes,
    Guid? SupersetId,
    IReadOnlyList<WorkoutSetValues> Sets);

/// <summary>Complete editable state of a workout; the client builds it and the server validates it as one aggregate.</summary>
public sealed record WorkoutValues(
    Guid WorkoutId,
    string Title,
    string? Notes,
    DateTime StartedAtUtc,
    DateTime? EndedAtUtc,
    string PreviousValueSource,
    Guid? SourcePlanId,
    Guid? SourceWorkoutId,
    IReadOnlyList<WorkoutExerciseValues> Exercises);

public sealed record CreateWorkoutMutation : ITypedMutation
{
    private CreateWorkoutMutation(MutationMetadata metadata, WorkoutValues workout)
    {
        Metadata = metadata;
        Workout = workout;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.Workout, workout.WorkoutId), 0));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public WorkoutValues Workout { get; }

    public static CreateWorkoutMutation Create(MutationMetadata metadata, WorkoutValues workout)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(workout);
        if (workout.WorkoutId == Guid.Empty)
        {
            throw new ArgumentException("The workout identifier cannot be empty.", nameof(workout));
        }
        return new(metadata, workout);
    }
}

public sealed record SaveWorkoutMutation : ITypedMutation
{
    private SaveWorkoutMutation(MutationMetadata metadata, long baseVersion, WorkoutValues workout)
    {
        Metadata = metadata;
        BaseVersion = baseVersion;
        Workout = workout;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.Workout, workout.WorkoutId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public long BaseVersion { get; }
    public WorkoutValues Workout { get; }

    public static SaveWorkoutMutation Create(MutationMetadata metadata, long baseVersion, WorkoutValues workout)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(workout);
        if (workout.WorkoutId == Guid.Empty)
        {
            throw new ArgumentException("The workout identifier cannot be empty.", nameof(workout));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, baseVersion, workout);
    }
}

public sealed record DeleteWorkoutMutation : ITypedMutation
{
    private DeleteWorkoutMutation(MutationMetadata metadata, Guid workoutId, long baseVersion)
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

    public static DeleteWorkoutMutation Create(MutationMetadata metadata, Guid workoutId, long baseVersion)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (workoutId == Guid.Empty)
        {
            throw new ArgumentException("The workout identifier cannot be empty.", nameof(workoutId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, workoutId, baseVersion);
    }
}

/// <summary>Result of a deletion; the tombstone is captured through the change collector.</summary>
public sealed record DeleteWorkoutResult(Guid WorkoutId, long Version);

/// <summary>Flat pull snapshot: the workout fields plus server metadata.</summary>
public sealed record WorkoutSnapshot(
    Guid WorkoutId,
    string Title,
    string? Notes,
    DateTime StartedAtUtc,
    DateTime? EndedAtUtc,
    string PreviousValueSource,
    Guid? SourcePlanId,
    Guid? SourceWorkoutId,
    IReadOnlyList<WorkoutExerciseValues> Exercises,
    DateTime? DeletedAtUtc,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.Workout, WorkoutId);
}

public interface IWorkoutMutationHandler
{
    Task<WorkoutSnapshot> CreateAsync(CreateWorkoutMutation mutation, CancellationToken cancellationToken = default);
    Task<WorkoutSnapshot> SaveAsync(SaveWorkoutMutation mutation, CancellationToken cancellationToken = default);
    Task<DeleteWorkoutResult> DeleteAsync(DeleteWorkoutMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class WorkoutValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The workout is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class WorkoutConflictException(string message) : Exception(message);

/// <summary>The user already has an active workout; the client must resume or end it first.</summary>
public sealed class ActiveWorkoutExistsException : Exception
{
    public ActiveWorkoutExistsException()
        : base("An active workout already exists for this user.")
    {
    }
}

public sealed class WorkoutNotFoundException : Exception;
