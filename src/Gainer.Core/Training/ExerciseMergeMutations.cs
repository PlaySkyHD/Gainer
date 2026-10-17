using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

/// <summary>
/// Repoints the user's workout blocks and plan entries from an own exercise to a target exercise and archives the source.
/// The target version is only expected when the target is an own exercise; base exercises are read-only here.
/// </summary>
public sealed record MergeExercisesMutation : ITypedMutation<MergeExercisesResult>
{
    private MergeExercisesMutation(
        MutationMetadata metadata,
        Guid sourceExerciseId,
        long sourceBaseVersion,
        Guid targetExerciseId,
        long? targetBaseVersion)
    {
        Metadata = metadata;
        SourceExerciseId = sourceExerciseId;
        SourceBaseVersion = sourceBaseVersion;
        TargetExerciseId = targetExerciseId;
        TargetBaseVersion = targetBaseVersion;

        var expectations = new List<ResourceVersionExpectation>
        {
            ResourceVersionExpectation.Create(ResourceKey.Create(ResourceKind.CustomExercise, sourceExerciseId), sourceBaseVersion),
        };
        if (targetBaseVersion is { } version)
        {
            expectations.Add(ResourceVersionExpectation.Create(ResourceKey.Create(ResourceKind.CustomExercise, targetExerciseId), version));
        }
        Scope = AtomicMutationScope.Create(expectations.ToArray());
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid SourceExerciseId { get; }
    public long SourceBaseVersion { get; }
    public Guid TargetExerciseId { get; }

    /// <summary>Null when the target is a base exercise.</summary>
    public long? TargetBaseVersion { get; }

    public static MergeExercisesMutation Create(
        MutationMetadata metadata,
        Guid sourceExerciseId,
        long sourceBaseVersion,
        Guid targetExerciseId,
        long? targetBaseVersion)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (sourceExerciseId == Guid.Empty || targetExerciseId == Guid.Empty)
        {
            throw new ArgumentException("The exercise identifiers cannot be empty.");
        }
        if (sourceExerciseId == targetExerciseId)
        {
            throw new ArgumentException("The source and target exercise must differ.", nameof(targetExerciseId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(sourceBaseVersion);
        if (targetBaseVersion is { } version)
        {
            ArgumentOutOfRangeException.ThrowIfNegativeOrZero(version);
        }
        return new(metadata, sourceExerciseId, sourceBaseVersion, targetExerciseId, targetBaseVersion);
    }
}

/// <summary>Reports how many user-owned resources were repointed by a merge.</summary>
public sealed record MergeExercisesResult(int UpdatedWorkoutCount, int UpdatedPlanCount);
