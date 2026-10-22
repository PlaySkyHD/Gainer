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

