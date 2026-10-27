using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

public sealed record TrainingPlanEntryValues(
    Guid EntryId,
    Guid ExerciseId,
    int WarmupSets,
    int WorkingSets,
    string? Notes,
    Guid? SupersetId);

/// <summary>Complete editable state of a training plan.</summary>
public sealed record TrainingPlanValues(
    Guid PlanId,
    string Name,
    string? Notes,
    string PreviousValueSource,
    IReadOnlyList<TrainingPlanEntryValues> Entries);

public sealed record TrainingPlanVersion(Guid PlanId, long BaseVersion);

public sealed record CreateTrainingPlanMutation : ITypedMutation
{
    private CreateTrainingPlanMutation(MutationMetadata metadata, TrainingPlanValues plan)
    {
        Metadata = metadata;
        Plan = plan;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.TrainingPlan, plan.PlanId), 0));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public TrainingPlanValues Plan { get; }

    public static CreateTrainingPlanMutation Create(MutationMetadata metadata, TrainingPlanValues plan)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(plan);
        if (plan.PlanId == Guid.Empty)
        {
            throw new ArgumentException("The plan identifier cannot be empty.", nameof(plan));
        }
        return new(metadata, plan);
    }
}

public sealed record UpdateTrainingPlanMutation : ITypedMutation
{
    private UpdateTrainingPlanMutation(MutationMetadata metadata, long baseVersion, TrainingPlanValues plan)
    {
        Metadata = metadata;
        BaseVersion = baseVersion;
        Plan = plan;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.TrainingPlan, plan.PlanId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public long BaseVersion { get; }
    public TrainingPlanValues Plan { get; }

    public static UpdateTrainingPlanMutation Create(MutationMetadata metadata, long baseVersion, TrainingPlanValues plan)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(plan);
        if (plan.PlanId == Guid.Empty)
        {
            throw new ArgumentException("The plan identifier cannot be empty.", nameof(plan));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, baseVersion, plan);
    }
}

public sealed record ArchiveTrainingPlanMutation : ITypedMutation
{
    private ArchiveTrainingPlanMutation(MutationMetadata metadata, Guid planId, long baseVersion)
    {
        Metadata = metadata;
        PlanId = planId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.TrainingPlan, planId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid PlanId { get; }
    public long BaseVersion { get; }

    public static ArchiveTrainingPlanMutation Create(MutationMetadata metadata, Guid planId, long baseVersion)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (planId == Guid.Empty)
        {
            throw new ArgumentException("The plan identifier cannot be empty.", nameof(planId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, planId, baseVersion);
    }
}

/// <summary>Stores a new order for a set of plans in one atomic mutation; list order becomes the sort order.</summary>
public sealed record ReorderTrainingPlansMutation : ITypedMutation
{
    private ReorderTrainingPlansMutation(MutationMetadata metadata, IReadOnlyList<TrainingPlanVersion> plans)
    {
        Metadata = metadata;
        Plans = plans;
        Scope = AtomicMutationScope.Create(plans
            .Select(item => ResourceVersionExpectation.Create(
                ResourceKey.Create(ResourceKind.TrainingPlan, item.PlanId), item.BaseVersion))
            .ToArray());
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public IReadOnlyList<TrainingPlanVersion> Plans { get; }

    public static ReorderTrainingPlansMutation Create(MutationMetadata metadata, IReadOnlyList<TrainingPlanVersion> plans)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(plans);
        if (plans.Count is < 1 or > TrainingPlanValidation.MaximumPlansPerReorder ||
            plans.Any(item => item.PlanId == Guid.Empty || item.BaseVersion <= 0) ||
            plans.Select(item => item.PlanId).Distinct().Count() != plans.Count)
        {
            throw new TrainingPlanValidationException(new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["Plans"] = $"Plans must be unique, non-empty and carry positive versions; at most {TrainingPlanValidation.MaximumPlansPerReorder} plans.",
            });
        }
        return new(metadata, plans);
    }
}

public sealed record TrainingPlanSnapshot(
    Guid PlanId,
    string Name,
    string? Notes,
    string PreviousValueSource,
    IReadOnlyList<TrainingPlanEntryValues> Entries,
    int SortOrder,
    bool IsArchived,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.TrainingPlan, PlanId);
}

public interface ITrainingPlanMutationHandler
{
    Task<TrainingPlanSnapshot> CreateAsync(CreateTrainingPlanMutation mutation, CancellationToken cancellationToken = default);
    Task<TrainingPlanSnapshot> UpdateAsync(UpdateTrainingPlanMutation mutation, CancellationToken cancellationToken = default);
    Task<TrainingPlanSnapshot> ArchiveAsync(ArchiveTrainingPlanMutation mutation, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<TrainingPlanSnapshot>> ReorderAsync(ReorderTrainingPlansMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class TrainingPlanValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The training plan is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class TrainingPlanConflictException(string message) : Exception(message);

public sealed class TrainingPlanNotFoundException : Exception;
