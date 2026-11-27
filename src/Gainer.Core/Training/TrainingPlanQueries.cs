namespace Gainer.Core.Training;

/// <summary>A stored plan with the current names of the exercises its entries reference.</summary>
public sealed record TrainingPlanDetail(TrainingPlanSnapshot Plan, IReadOnlyDictionary<Guid, string> ExerciseNames);

public interface ITrainingPlanQueries
{
    /// <summary>The user's plans in their sort order; archived plans only on request.</summary>
    Task<IReadOnlyList<TrainingPlanDetail>> ListAsync(bool includeArchived, CancellationToken cancellationToken = default);

    /// <summary>One of the user's plans, archived or not; null for unknown or foreign IDs.</summary>
    Task<TrainingPlanDetail?> GetAsync(Guid planId, CancellationToken cancellationToken = default);
}
