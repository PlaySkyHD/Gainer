using Gainer.Core.Training;

namespace Gainer.Core.Insights;

/// <summary>Figures of the app's statistics and muscle map, computed by the ports of the app's rules.</summary>
public interface ITrainingAnalysisQueries
{
    /// <summary>Trend tiles of a period ending <paramref name="today"/> (local day in <paramref name="timeZone"/>).</summary>
    Task<TrainingTrendsSnapshot> TrendsAsync(
        TrendPeriod period,
        bool includeWarmups,
        DateOnly today,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default);

    /// <summary>Minutes trained per local day of the last twelve months, from strength workouts and cardio sessions.</summary>
    Task<TrainingHeatmapSnapshot> HeatmapAsync(
        DateOnly today,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Planned working sets per muscle: of one plan, or of all plans that are not archived without
    /// <paramref name="planId"/>. Null for an unknown or foreign plan.
    /// </summary>
    Task<MuscleVolumeSnapshot?> PlannedMuscleVolumeAsync(Guid? planId, CancellationToken cancellationToken = default);

    /// <summary>Recorded working sets per muscle of workouts started in [<paramref name="fromUtc"/>, <paramref name="toUtc"/>), per week.</summary>
    Task<MuscleVolumeSnapshot> TrainedMuscleVolumeAsync(
        DateTime fromUtc,
        DateTime toUtc,
        int weeks,
        CancellationToken cancellationToken = default);
}
