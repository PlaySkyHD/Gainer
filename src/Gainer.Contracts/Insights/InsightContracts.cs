namespace Gainer.Contracts.Insights;

public sealed record MetricAverageResponse(decimal? Value, int ObservedDays);

public sealed record WeightInsightsResponse(
    string AverageAlgorithmVersion,
    string TrendAlgorithmVersion,
    string Unit,
    DateOnly From,
    DateOnly Through,
    int ExpectedDays,
    int ObservedDays,
    decimal Coverage,
    decimal? AverageKg,
    decimal? TrendKgPerWeek);

public sealed record NutritionInsightsResponse(
    string AlgorithmVersion,
    int ExpectedDays,
    int ObservedDays,
    decimal Coverage,
    MetricAverageResponse CaloriesKcal,
    MetricAverageResponse ProteinGrams,
    MetricAverageResponse CarbohydrateGrams,
    MetricAverageResponse FatGrams);

public sealed record BestSetResponse(
    Guid WorkoutId,
    Guid ExerciseId,
    DateTime CompletedAtUtc,
    decimal WeightKg,
    int Repetitions,
    decimal EstimatedOneRepMaxKg);

public sealed record TrainingInsightsResponse(
    string VolumeAlgorithmVersion,
    string EstimatedOneRepMaxAlgorithmVersion,
    string VolumeUnit,
    int WorkoutCount,
    decimal VolumeKgRepetitions,
    BestSetResponse? BestSet);

public sealed record ActiveGoalInsightResponse(
    Guid GoalId,
    string Kind,
    decimal StartWeightKg,
    decimal TargetWeightKg,
    DateOnly StartDate,
    DateOnly? TargetDate);

public sealed record WeightPointResponse(DateOnly Date, decimal WeightKg);

public sealed record DashboardInsightsResponse(
    long AsOfRevision,
    DateOnly From,
    DateOnly Through,
    ActiveGoalInsightResponse? ActiveGoal,
    WeightPointResponse? LatestWeight,
    IReadOnlyList<WeightPointResponse> WeightSeries,
    WeightInsightsResponse SevenDayWeight,
    WeightInsightsResponse Weight,
    NutritionInsightsResponse Nutrition,
    TrainingInsightsResponse Training,
    int WorkoutsLast7Days);

public sealed record ExerciseProgressPointResponse(
    Guid WorkoutId,
    DateTime CompletedAtUtc,
    decimal VolumeKgRepetitions,
    decimal? BestWeightKg,
    int? BestRepetitions,
    decimal? EstimatedOneRepMaxKg);

public sealed record ExerciseProgressResponse(
    long AsOfRevision,
    Guid ExerciseId,
    int? WindowDays,
    DateTime FromUtc,
    DateTime ThroughUtc,
    IReadOnlyList<ExerciseProgressPointResponse> Points,
    BestSetResponse? BestSet);
