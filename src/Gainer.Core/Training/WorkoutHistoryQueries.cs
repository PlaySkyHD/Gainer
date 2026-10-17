namespace Gainer.Core.Training;

public sealed record WorkoutHistorySummary(
    Guid WorkoutId,
    string Title,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    int CompletedSetCount,
    long Version);

public interface IWorkoutHistoryQueries
{
    Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(int offset, int limit, CancellationToken cancellationToken = default);
    Task<WorkoutSnapshot?> GetAsync(Guid workoutId, CancellationToken cancellationToken = default);
}

public interface IWorkoutRotationQueries
{
    /// <summary>Returns the plan of the most recent finished, not deleted workout that started from the rotation.</summary>
    Task<Guid?> LastFinishedPlanIdAsync(IReadOnlyList<Guid> rotationPlanIds, CancellationToken cancellationToken = default);

    /// <summary>Returns the suggested next plan of the user's rotation, or null when there is none.</summary>
    Task<Guid?> NextPlanIdAsync(CancellationToken cancellationToken = default);
}
