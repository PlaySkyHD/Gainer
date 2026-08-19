namespace Gainer.Core.Training;

public sealed record WorkoutHistorySummary(
    Guid WorkoutId,
    string TemplateNameSnapshot,
    DateTime StartedAtUtc,
    DateTime CompletedAtUtc,
    int CompletedSetCount,
    long Version);

public interface IWorkoutHistoryQueries
{
    Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(int offset, int limit, CancellationToken cancellationToken = default);
    Task<WorkoutSnapshot?> GetAsync(Guid workoutId, CancellationToken cancellationToken = default);
}

public sealed class HistoricalWorkoutImmutableException()
    : InvalidOperationException("Completed and discarded workout snapshots are immutable.");
