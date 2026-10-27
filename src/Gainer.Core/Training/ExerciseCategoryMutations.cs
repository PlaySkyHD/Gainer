using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

public sealed record CreateExerciseCategoryMutation : ITypedMutation
{
    private CreateExerciseCategoryMutation(MutationMetadata metadata, Guid categoryId, string name)
    {
        Metadata = metadata;
        CategoryId = categoryId;
        Name = name;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.ExerciseCategory, categoryId), 0));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid CategoryId { get; }
    public string Name { get; }

    public static CreateExerciseCategoryMutation Create(MutationMetadata metadata, Guid categoryId, string name) =>
        categoryId != Guid.Empty
            ? new(metadata, categoryId, name)
            : throw new ArgumentException("The category identifier cannot be empty.", nameof(categoryId));
}

public sealed record UpdateExerciseCategoryMutation : ITypedMutation
{
    private UpdateExerciseCategoryMutation(MutationMetadata metadata, Guid categoryId, long baseVersion, string name)
    {
        Metadata = metadata;
        CategoryId = categoryId;
        BaseVersion = baseVersion;
        Name = name;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.ExerciseCategory, categoryId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid CategoryId { get; }
    public long BaseVersion { get; }
    public string Name { get; }

    public static UpdateExerciseCategoryMutation Create(MutationMetadata metadata, Guid categoryId, long baseVersion, string name)
    {
        if (categoryId == Guid.Empty)
        {
            throw new ArgumentException("The category identifier cannot be empty.", nameof(categoryId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, categoryId, baseVersion, name);
    }
}

public sealed record ArchiveExerciseCategoryMutation : ITypedMutation
{
    private ArchiveExerciseCategoryMutation(MutationMetadata metadata, Guid categoryId, long baseVersion)
    {
        Metadata = metadata;
        CategoryId = categoryId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.ExerciseCategory, categoryId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid CategoryId { get; }
    public long BaseVersion { get; }

    public static ArchiveExerciseCategoryMutation Create(MutationMetadata metadata, Guid categoryId, long baseVersion)
    {
        if (categoryId == Guid.Empty)
        {
            throw new ArgumentException("The category identifier cannot be empty.", nameof(categoryId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, categoryId, baseVersion);
    }
}

public sealed record ExerciseCategorySnapshot(
    Guid CategoryId,
    string Name,
    bool IsArchived,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.ExerciseCategory, CategoryId);
}

public interface IExerciseCategoryMutationHandler
{
    Task<ExerciseCategorySnapshot> CreateAsync(CreateExerciseCategoryMutation mutation, CancellationToken cancellationToken = default);
    Task<ExerciseCategorySnapshot> UpdateAsync(UpdateExerciseCategoryMutation mutation, CancellationToken cancellationToken = default);
    Task<ExerciseCategorySnapshot> ArchiveAsync(ArchiveExerciseCategoryMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class ExerciseCategoryValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The exercise category is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class ExerciseCategoryConflictException(string message) : Exception(message);

public sealed class ExerciseCategoryNotFoundException : Exception;
