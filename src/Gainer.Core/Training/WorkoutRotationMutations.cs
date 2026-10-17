using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

public sealed record SaveWorkoutRotationMutation : ITypedMutation<WorkoutRotationSnapshot>
{
    private SaveWorkoutRotationMutation(
        MutationMetadata metadata,
        Guid rotationId,
        long baseVersion,
        IReadOnlyList<Guid> planIds)
    {
        Metadata = metadata;
        RotationId = rotationId;
        BaseVersion = baseVersion;
        PlanIds = planIds;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.WorkoutRotation, rotationId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid RotationId { get; }
    public long BaseVersion { get; }
    public IReadOnlyList<Guid> PlanIds { get; }

    public static SaveWorkoutRotationMutation Create(
        MutationMetadata metadata,
        Guid rotationId,
        long baseVersion,
        IReadOnlyList<Guid> planIds)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(planIds);
        if (rotationId == Guid.Empty)
        {
            throw new ArgumentException("The rotation identifier cannot be empty.", nameof(rotationId));
        }
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        return new(metadata, rotationId, baseVersion, planIds);
    }
}

public sealed record WorkoutRotationSnapshot(
    Guid RotationId,
    IReadOnlyList<Guid> PlanIds,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.WorkoutRotation, RotationId);
}

public interface IWorkoutRotationHandler
{
    Task<WorkoutRotationSnapshot> SaveAsync(SaveWorkoutRotationMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class WorkoutRotationValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The workout rotation is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class WorkoutRotationConflictException(string message) : Exception(message);

public sealed class WorkoutRotationNotFoundException : Exception;
