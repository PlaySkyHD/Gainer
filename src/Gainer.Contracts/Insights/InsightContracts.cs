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
    int MealDiaryDays,
    int LegacyCheckInDays,
    MetricAverageResponse CaloriesKcal,
    MetricAverageResponse ProteinGrams,
    MetricAverageResponse CarbohydrateGrams,
    MetricAverageResponse FatGrams);

/// <summary>Bester Satz; <c>EffectiveWeightKg</c> enthält Zusatz-, Körpergewichtsanteil bzw. Unterstützung.</summary>
public sealed record BestSetResponse(
    Guid WorkoutId,
    Guid ExerciseId,
    DateTime CompletedAtUtc,
    decimal EffectiveWeightKg,
    int Repetitions,
    decimal EstimatedOneRepMaxKg);

public sealed record TrainingInsightsResponse(
    string VolumeAlgorithmVersion,
    string EstimatedOneRepMaxAlgorithmVersion,
    string VolumeUnit,
    int WorkoutCount,
    decimal VolumeKgRepetitions,
    BestSetResponse? BestSet,
    bool BodyweightMissing);

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
    decimal? MaxWeightKg,
    int MaxRepetitions,
    decimal? EstimatedOneRepMaxKg,
    bool BodyweightMissing);

public sealed record RecordEventResponse(Guid WorkoutId, decimal Value);

public sealed record RepetitionRecordResponse(int Repetitions, decimal? MaxWeightKg);

/// <summary>Aktuelle Rekorde je Übung über die gesamte Historie; <c>null</c> ohne erfassten Satz.</summary>
public sealed record ExerciseRecordsResponse(
    RecordEventResponse? MaxWeightKg,
    RecordEventResponse? EstimatedOneRepMaxKg,
    RecordEventResponse? VolumeKgRepetitions,
    RecordEventResponse? MaxRepetitions,
    IReadOnlyList<RepetitionRecordResponse> RepetitionRecords);

public sealed record ExerciseProgressResponse(
    long AsOfRevision,
    Guid ExerciseId,
    int? WindowDays,
    DateTime FromUtc,
    DateTime ThroughUtc,
    string VolumeAlgorithmVersion,
    string EstimatedOneRepMaxAlgorithmVersion,
    IReadOnlyList<ExerciseProgressPointResponse> Points,
    BestSetResponse? BestSet,
    ExerciseRecordsResponse Records);
