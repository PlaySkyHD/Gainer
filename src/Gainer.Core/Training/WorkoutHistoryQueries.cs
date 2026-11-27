namespace Gainer.Core.Training;

public sealed record WorkoutHistorySummary(
    Guid WorkoutId,
    string Title,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    int CompletedSetCount,
    long Version,
    Guid? SourcePlanId = null);

/// <summary>Workouts that started on the local days <see cref="From"/> through <see cref="Through"/>.</summary>
public sealed record WorkoutHistoryRange(DateOnly From, DateOnly Through, TimeZoneInfo TimeZone);

public interface IWorkoutHistoryQueries
{
    Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(int offset, int limit, CancellationToken cancellationToken = default);

    /// <summary>Completed workouts, newest first, optionally limited to a range of local start days.</summary>
    Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(
        WorkoutHistoryRange? range,
        int offset,
        int limit,
        CancellationToken cancellationToken = default);

    Task<WorkoutSnapshot?> GetAsync(Guid workoutId, CancellationToken cancellationToken = default);
}
