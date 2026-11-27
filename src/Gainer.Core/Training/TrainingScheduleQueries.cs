namespace Gainer.Core.Training;

/// <summary>Loads the user's training rhythm, plans and workouts for <see cref="TrainingScheduleProjection"/>.</summary>
public interface ITrainingScheduleQueries
{
    /// <summary>
    /// Projection of the user's rhythm (none when no live rhythm exists) with all plans, archived ones included, and
    /// the finished strength workouts started on the local days <paramref name="from"/> through
    /// <paramref name="through"/> in <paramref name="timeZone"/>. Days outside that range know no workouts.
    /// </summary>
    Task<TrainingScheduleProjection> ProjectionAsync(
        DateOnly from,
        DateOnly through,
        DateOnly today,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default);
}
