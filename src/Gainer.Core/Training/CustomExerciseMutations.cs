using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

/// <summary>Editable values of a custom exercise; the exercise type is the stored value and has no fallback.</summary>
public sealed record CustomExerciseValues(
    string Name,
    string ExerciseType,
    string? Description = null,
    string? TargetMuscle = null,
    string? MuscleGroup = null,
    string? Equipment = null,
    string? Notes = null,
    decimal? BodyweightFactor = null,
    decimal? WeightFactor = null,
    IReadOnlyList<Guid>? CategoryIds = null,
    IReadOnlyList<string>? PrimaryMuscles = null,
    IReadOnlyList<string>? SecondaryMuscles = null);

public sealed record CreateCustomExerciseMutation : ITypedMutation<CustomExerciseSnapshot>
{
    private CreateCustomExerciseMutation(
        MutationMetadata metadata,
        Guid exerciseId,
        CustomExerciseValues values)
    {
        Metadata = metadata;
        ExerciseId = exerciseId;
        Values = values;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.CustomExercise, exerciseId), 0));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid ExerciseId { get; }
    public CustomExerciseValues Values { get; }

    public static CreateCustomExerciseMutation Create(
        MutationMetadata metadata,
        Guid exerciseId,
        CustomExerciseValues values) =>
        exerciseId != Guid.Empty
            ? new(metadata, exerciseId, values)
            : throw new ArgumentException("The exercise identifier cannot be empty.", nameof(exerciseId));
}

public sealed record UpdateCustomExerciseMutation : ITypedMutation<CustomExerciseSnapshot>
{
    private UpdateCustomExerciseMutation(
        MutationMetadata metadata,
        Guid exerciseId,
        long baseVersion,
        CustomExerciseValues values)
    {
        Metadata = metadata;
        ExerciseId = exerciseId;
        BaseVersion = baseVersion;
        Values = values;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.CustomExercise, exerciseId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid ExerciseId { get; }
    public long BaseVersion { get; }
    public CustomExerciseValues Values { get; }

    public static UpdateCustomExerciseMutation Create(
        MutationMetadata metadata,
        Guid exerciseId,
        long baseVersion,
        CustomExerciseValues values)
    {
        if (exerciseId == Guid.Empty)
        {
            throw new ArgumentException("The exercise identifier cannot be empty.", nameof(exerciseId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, exerciseId, baseVersion, values);
    }
}

public sealed record ArchiveCustomExerciseMutation : ITypedMutation<CustomExerciseSnapshot>
{
    private ArchiveCustomExerciseMutation(MutationMetadata metadata, Guid exerciseId, long baseVersion)
    {
        Metadata = metadata;
        ExerciseId = exerciseId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.CustomExercise, exerciseId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid ExerciseId { get; }
    public long BaseVersion { get; }

    public static ArchiveCustomExerciseMutation Create(
        MutationMetadata metadata,
        Guid exerciseId,
        long baseVersion)
    {
        if (exerciseId == Guid.Empty)
        {
            throw new ArgumentException("The exercise identifier cannot be empty.", nameof(exerciseId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, exerciseId, baseVersion);
    }
}

public sealed record CustomExerciseSnapshot(
    Guid ExerciseId,
    CustomExerciseValues Values,
    bool IsArchived,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.CustomExercise, ExerciseId);
}

public interface ICustomExerciseMutationHandler
{
    Task<CustomExerciseSnapshot> CreateAsync(CreateCustomExerciseMutation mutation, CancellationToken cancellationToken = default);
    Task<CustomExerciseSnapshot> UpdateAsync(UpdateCustomExerciseMutation mutation, CancellationToken cancellationToken = default);
    Task<CustomExerciseSnapshot> ArchiveAsync(ArchiveCustomExerciseMutation mutation, CancellationToken cancellationToken = default);
}

public interface IExerciseResolver
{
    Task<ExerciseCatalogItem?> ResolveAsync(Guid exerciseId, bool includeArchived, CancellationToken cancellationToken = default);
}

public sealed class CustomExerciseValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The custom exercise is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class CustomExerciseConflictException(string message) : Exception(message);

public sealed class CustomExerciseNotFoundException : Exception;
