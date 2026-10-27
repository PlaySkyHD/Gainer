using Gainer.Core.Mutations;

namespace Gainer.Core.BodyTracking;

public sealed record ActiveBodyGoalExpectation(Guid GoalId, long Version);

/// <summary>The weight and date values of a body goal.</summary>
public sealed record BodyGoalPlan(
    BodyGoalKind Kind,
    decimal StartWeightKg,
    decimal TargetWeightKg,
    DateOnly StartDate,
    DateOnly? TargetDate = null);

public sealed record ActivateBodyGoalMutation : ITypedMutation<BodyGoalSnapshot>
{
    private ActivateBodyGoalMutation(
        MutationMetadata metadata,
        Guid goalId,
        BodyGoalPlan plan,
        ActiveBodyGoalExpectation? expectedActiveGoal)
    {
        Metadata = metadata;
        GoalId = goalId;
        Kind = plan.Kind;
        StartWeightKg = plan.StartWeightKg;
        TargetWeightKg = plan.TargetWeightKg;
        StartDate = plan.StartDate;
        TargetDate = plan.TargetDate;
        ExpectedActiveGoal = expectedActiveGoal;
        ResourceVersionExpectation create = ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.BodyGoal, goalId),
            baseVersion: 0);
        Scope = expectedActiveGoal is null
            ? AtomicMutationScope.Create(create)
            : AtomicMutationScope.Create(
                create,
                ResourceVersionExpectation.Create(
                    ResourceKey.Create(ResourceKind.BodyGoal, expectedActiveGoal.GoalId),
                    expectedActiveGoal.Version));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid GoalId { get; }
    public BodyGoalKind Kind { get; }
    public decimal StartWeightKg { get; }
    public decimal TargetWeightKg { get; }
    public DateOnly StartDate { get; }
    public DateOnly? TargetDate { get; }
    public ActiveBodyGoalExpectation? ExpectedActiveGoal { get; }

    public static ActivateBodyGoalMutation Create(
        MutationMetadata metadata,
        Guid goalId,
        BodyGoalPlan plan,
        ActiveBodyGoalExpectation? expectedActiveGoal = null)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(plan);
        if (goalId == Guid.Empty)
        {
            throw new ArgumentException("The goal identifier cannot be empty.", nameof(goalId));
        }

        return new ActivateBodyGoalMutation(
            metadata,
            goalId,
            plan,
            expectedActiveGoal);
    }
}

public sealed record BodyGoalSnapshot(
    Guid GoalId,
    BodyGoalKind Kind,
    decimal StartWeightKg,
    decimal TargetWeightKg,
    DateOnly StartDate,
    DateOnly? TargetDate,
    DateTime CreatedAtUtc,
    DateTime? EndedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.BodyGoal, GoalId);
}

public interface IBodyGoalMutationHandler
{
    Task<BodyGoalSnapshot> ActivateAsync(
        ActivateBodyGoalMutation mutation,
        CancellationToken cancellationToken = default);
}

public sealed class BodyGoalValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The body goal is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class BodyGoalConflictException(string message) : Exception(message);
