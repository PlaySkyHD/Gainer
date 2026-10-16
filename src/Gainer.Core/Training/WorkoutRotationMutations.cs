using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

public sealed record WorkoutRotationEntry(Guid ItemId, Guid TemplateId);

public sealed record SaveWorkoutRotationMutation : ITypedMutation<WorkoutRotationSnapshot>
{
    private SaveWorkoutRotationMutation(
        MutationMetadata metadata,
        Guid rotationId,
        long baseVersion,
        IReadOnlyList<WorkoutRotationEntry> entries)
    {
        Metadata = metadata;
        RotationId = rotationId;
        BaseVersion = baseVersion;
        Entries = entries;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.WorkoutRotation, rotationId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid RotationId { get; }
    public long BaseVersion { get; }
    public IReadOnlyList<WorkoutRotationEntry> Entries { get; }

    public static SaveWorkoutRotationMutation Create(
        MutationMetadata metadata,
        Guid rotationId,
        long baseVersion,
        IReadOnlyList<WorkoutRotationEntry> entries)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(entries);
        if (rotationId == Guid.Empty)
        {
            throw new ArgumentException("The rotation identifier cannot be empty.", nameof(rotationId));
        }
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        return new(metadata, rotationId, baseVersion, entries);
    }
}

public sealed record AdvanceWorkoutRotationMutation : ITypedMutation<WorkoutRotationSnapshot>
{
    private AdvanceWorkoutRotationMutation(
        MutationMetadata metadata,
        Guid rotationId,
        long baseVersion,
        Guid completedTemplateId)
    {
        Metadata = metadata;
        RotationId = rotationId;
        BaseVersion = baseVersion;
        CompletedTemplateId = completedTemplateId;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.WorkoutRotation, rotationId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid RotationId { get; }
    public long BaseVersion { get; }
    public Guid CompletedTemplateId { get; }

    public static AdvanceWorkoutRotationMutation Create(
        MutationMetadata metadata,
        Guid rotationId,
        long baseVersion,
        Guid completedTemplateId)
    {
        if (rotationId == Guid.Empty || completedTemplateId == Guid.Empty)
        {
            throw new ArgumentException("Rotation and template identifiers cannot be empty.");
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, rotationId, baseVersion, completedTemplateId);
    }
}

public sealed record WorkoutRotationSnapshot(
    Guid RotationId,
    IReadOnlyList<WorkoutRotationEntry> Entries,
    Guid? LastCompletedTemplateId,
    Guid? NextTemplateId,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.WorkoutRotation, RotationId);
}

public interface IWorkoutRotationHandler
{
    Task<WorkoutRotationSnapshot> SaveAsync(SaveWorkoutRotationMutation mutation, CancellationToken cancellationToken = default);
    Task<WorkoutRotationSnapshot> AdvanceAsync(AdvanceWorkoutRotationMutation mutation, CancellationToken cancellationToken = default);
    Task<WorkoutRotationSnapshot?> GetAsync(CancellationToken cancellationToken = default);
}

public sealed class WorkoutRotationValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The workout rotation is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class WorkoutRotationConflictException(string message) : Exception(message);

public sealed class WorkoutRotationNotFoundException : Exception;
