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
