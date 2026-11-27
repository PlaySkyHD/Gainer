using Gainer.Core.BodyTracking;

namespace Gainer.Core.Insights;

public sealed record DashboardInsightSnapshot(
    long AsOfRevision,
    DateOnly From,
    DateOnly Through,
    BodyGoalSnapshot? ActiveGoal,
    WeightPoint? LatestWeight,
    IReadOnlyList<WeightPoint> WeightSeries,
    WeightInsights SevenDayWeight,
    WeightInsights Weight,
    NutritionInsights Nutrition,
    TrainingInsights Training,
    int WorkoutsLast7Days);

public sealed record ExerciseProgressPoint(
    Guid WorkoutId,
    DateTime CompletedAtUtc,
    decimal VolumeKgRepetitions,
    decimal? MaxWeightKg,
    int MaxRepetitions,
    decimal? EstimatedOneRepMaxKg,
    bool BodyweightMissing);

public sealed record ExerciseProgressSnapshot(
    long AsOfRevision,
    Guid ExerciseId,
    int? WindowDays,
    DateTime FromUtc,
    DateTime ThroughUtc,
    IReadOnlyList<ExerciseProgressPoint> Points,
    BestSet? BestSet,
    ExerciseRecords Records);

/// <summary>
/// Summary of one completed workout as on the app's summary screen. <see cref="Counts"/> counts the completed
/// workouts that started up to this one, so it reads "n-th workout overall, m-th in its week".
/// </summary>
public sealed record WorkoutSummarySnapshot(
    Guid WorkoutId,
    string Title,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    TrainingSummary Summary,
    WorkoutCounts Counts,
    IReadOnlyDictionary<Guid, string> ExerciseNames,
    bool BodyweightMissing);

public interface IWorkoutSummaryQueries
{
    /// <summary>Null for unknown, foreign, deleted or still active workouts.</summary>
    Task<WorkoutSummarySnapshot?> WorkoutSummaryAsync(
        Guid workoutId,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default);
}

public interface IInsightQueries
{
    Task<DashboardInsightSnapshot> DashboardAsync(
        DateOnly through,
        int days,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default);

    Task<ExerciseProgressSnapshot> ExerciseProgressAsync(
        Guid exerciseId,
        int? windowDays,
        DateTime throughUtc,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default);
}
