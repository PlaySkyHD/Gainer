using Gainer.Core.Mutations;

namespace Gainer.Core.BodyTracking;

public sealed record ActiveBodyGoalExpectation(Guid GoalId, long Version);

public sealed record ActivateBodyGoalMutation : ITypedMutation<BodyGoalSnapshot>
{
    private ActivateBodyGoalMutation(
        MutationMetadata metadata,
        Guid goalId,
        BodyGoalKind kind,
        decimal startWeightKg,
        decimal targetWeightKg,
        DateOnly startDate,
        DateOnly? targetDate,
        ActiveBodyGoalExpectation? expectedActiveGoal)
    {
        Metadata = metadata;
        GoalId = goalId;
        Kind = kind;
        StartWeightKg = startWeightKg;
        TargetWeightKg = targetWeightKg;
        StartDate = startDate;
        TargetDate = targetDate;
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
        BodyGoalKind kind,
        decimal startWeightKg,
        decimal targetWeightKg,
        DateOnly startDate,
        DateOnly? targetDate = null,
        ActiveBodyGoalExpectation? expectedActiveGoal = null)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (goalId == Guid.Empty)
        {
            throw new ArgumentException("The goal identifier cannot be empty.", nameof(goalId));
        }

        return new ActivateBodyGoalMutation(
            metadata,
            goalId,
            kind,
            startWeightKg,
            targetWeightKg,
            startDate,
            targetDate,
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
