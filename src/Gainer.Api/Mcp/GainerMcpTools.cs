using System.ComponentModel;
using Gainer.Core.Insights;
using Gainer.Core.Training;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace Gainer.Api.Mcp;

/// <summary>
/// Read-only tools for connected assistants. Every query runs in the request of the connector token,
/// so the user comes from the token and never from an argument; foreign IDs resolve to nothing.
/// </summary>
[McpServerToolType]
public sealed class GainerMcpTools(
    IInsightQueries insights,
    IWorkoutHistoryQueries workoutHistory,
    IExerciseCatalogQueries catalog,
    IExerciseResolver exercises,
    TimeProvider timeProvider)
{
    private const int MaximumWorkouts = 50;
    private const int MaximumExercises = 50;

    private static TimeZoneInfo TimeZone => LocalDays.Default;

    /// <summary>Goal, body weight, nutrition and training of a period.</summary>
    [McpServerTool(Name = "get_overview", Title = "Überblick", ReadOnly = true, Idempotent = true, OpenWorld = false,
        UseStructuredContent = true)]
    [Description("Summary of the user's fitness data for a period of local days: active goal, body weight (latest, " +
        "average, 7-day average, weekly trend and the daily weight series), average daily nutrition and strength " +
        "training (workouts, workouts in the last 7 days, volume, best set). " +
        "Weights in kg, volume in kg × repetitions. Call twice with endDaysAgo to compare periods.")]
    public async Task<OverviewResult> GetOverview(
        [Description("Length of the period in days: 7, 30 or 90.")] int days = 30,
        [Description("How many days before today the period ends; 0 ends today.")] int endDaysAgo = 0,
        CancellationToken cancellationToken = default)
    {
        if (days is not (7 or 30 or 90))
        {
            throw new McpException("days must be 7, 30 or 90.");
        }

        if (endDaysAgo is < 0 or > 730)
        {
            throw new McpException("endDaysAgo must be between 0 and 730.");
        }

        DateOnly through = timeProvider.Today(TimeZone).AddDays(-endDaysAgo);
        DashboardInsightSnapshot data = await insights.DashboardAsync(through, days, TimeZone, cancellationToken);
        return new OverviewResult(
            data.From,
            data.Through,
            data.ActiveGoal is { } goal
                ? new GoalResult(goal.Kind.ToString(), goal.StartWeightKg, goal.TargetWeightKg, goal.TargetDate)
                : null,
            new WeightResult(
                data.LatestWeight?.WeightKg,
                data.LatestWeight?.Date,
                Round(data.Weight.AverageKg),
                Round(data.Weight.TrendKgPerWeek),
                data.Weight.ObservedDays,
                Round(data.SevenDayWeight.AverageKg),
                data.WeightSeries.Select(point => new WeightPointResult(point.Date, point.WeightKg)).ToList()),
            new NutritionResult(
                Round(data.Nutrition.CaloriesKcal.Value),
                Round(data.Nutrition.ProteinGrams.Value),
                Round(data.Nutrition.CarbohydrateGrams.Value),
                Round(data.Nutrition.FatGrams.Value),
                Round(data.Nutrition.FiberGrams?.Value),
                data.Nutrition.ObservedDays),
            new TrainingResult(
                data.Training.WorkoutCount,
                Round(data.Training.VolumeKgRepetitions),
                data.Training.BestSet is { } best
                    ? new BestSetResult(best.ExerciseId, best.EffectiveWeightKg, best.Repetitions, Round(best.EstimatedOneRepMaxKg))
                    : null,
                data.Training.BodyweightMissing,
                data.WorkoutsLast7Days));
    }

    /// <summary>Completed workouts, newest first.</summary>
    [McpServerTool(Name = "list_workouts", Title = "Trainings", ReadOnly = true, Idempotent = true, OpenWorld = false,
        UseStructuredContent = true)]
    [Description("Completed strength workouts, newest first, with title, start, end and number of completed sets. " +
        "Use get_workout for exercises and sets.")]
    public async Task<WorkoutListResult> ListWorkouts(
        [Description("Number of workouts to skip.")] int offset = 0,
        [Description("Number of workouts to return, 1 to 50.")] int limit = 10,
        CancellationToken cancellationToken = default)
    {
        if (offset < 0 || limit is < 1 or > MaximumWorkouts)
        {
            throw new McpException("offset must be at least 0 and limit between 1 and 50.");
        }

        IReadOnlyList<WorkoutHistorySummary> items = await workoutHistory.ListAsync(offset, limit, cancellationToken);
        return new WorkoutListResult(items
            .Select(item => new WorkoutSummaryResult(
                item.WorkoutId, item.Title, item.StartedAtUtc, item.EndedAtUtc, item.CompletedSetCount))
            .ToList());
    }

    /// <summary>One workout with exercises and sets.</summary>
    [McpServerTool(Name = "get_workout", Title = "Training", ReadOnly = true, Idempotent = true, OpenWorld = false,
        UseStructuredContent = true)]
    [Description("One workout with its exercises and sets (set type, weight in kg, repetitions, reps in reserve).")]
    public async Task<WorkoutResult> GetWorkout(
        [Description("ID of the workout from list_workouts.")] Guid workoutId,
        CancellationToken cancellationToken = default)
    {
        WorkoutSnapshot? workout = await workoutHistory.GetAsync(workoutId, cancellationToken);
        if (workout is null || workout.DeletedAtUtc is not null)
        {
            throw new McpException("The workout was not found.");
        }

        return new WorkoutResult(
            workout.WorkoutId,
            workout.Title,
            workout.Notes,
            workout.StartedAtUtc,
            workout.EndedAtUtc,
            workout.Exercises
                .Select(exercise => new WorkoutExerciseResult(
                    exercise.SourceExerciseId,
                    exercise.ExerciseNameSnapshot,
                    exercise.ExerciseTypeSnapshot,
                    exercise.Notes,
                    exercise.Sets
                        .Select(set => new WorkoutSetResult(set.SetType, set.WeightKg, set.Repetitions, set.Rir, set.Notes))
                        .ToList()))
                .ToList());
    }

    /// <summary>Exercises of the catalog and the user's own ones.</summary>
    [McpServerTool(Name = "search_exercises", Title = "Übungen suchen", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("Searches the user's exercise catalog by name and returns IDs for get_exercise_progress, " +
        "with type and primary and secondary muscles.")]
    public async Task<ExerciseListResult> SearchExercises(
        [Description("Part of the exercise name, e.g. \"Kniebeuge\"; empty lists all.")] string? query = null,
        [Description("Number of exercises to return, 1 to 50.")] int limit = 20,
        CancellationToken cancellationToken = default)
    {
        if (limit is < 1 or > MaximumExercises)
        {
            throw new McpException("limit must be between 1 and 50.");
        }

        ExerciseCatalogPage page = await catalog.SearchAsync(
            new ExerciseCatalogFilter(Search: string.IsNullOrWhiteSpace(query) ? null : query.Trim(), Limit: limit),
            cancellationToken);
        return new ExerciseListResult(page.Items
            .Select(item => new ExerciseResult(
                item.Id, item.Name, item.ExerciseType.ToString(), item.IsCustom, item.PrimaryMuscles, item.SecondaryMuscles))
            .ToList());
    }

    /// <summary>Development of one exercise over time.</summary>
    [McpServerTool(Name = "get_exercise_progress", Title = "Übungsentwicklung", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("Development of one exercise: per workout the volume, max weight, max repetitions and estimated " +
        "one-rep max (Epley), plus current personal records.")]
    public async Task<ExerciseProgressResult> GetExerciseProgress(
        [Description("ID of the exercise from search_exercises.")] Guid exerciseId,
        [Description("Window in days: 7, 30 or 90; omit for all time.")] int? days = null,
        CancellationToken cancellationToken = default)
    {
        if (days is not (null or 7 or 30 or 90))
        {
            throw new McpException("days must be 7, 30, 90 or omitted.");
        }

        // Archived exercises keep their history; foreign ones resolve to null.
        ExerciseCatalogItem exercise = await exercises.ResolveAsync(exerciseId, includeArchived: true, cancellationToken)
            ?? throw new McpException("The exercise was not found.");
        ExerciseProgressSnapshot data = await insights.ExerciseProgressAsync(
            exerciseId, days, timeProvider.GetUtcNow().UtcDateTime, TimeZone, cancellationToken);
        return new ExerciseProgressResult(
            exercise.Id,
            exercise.Name,
            data.Points
                .Select(point => new ExerciseProgressPointResult(
                    point.WorkoutId,
                    point.CompletedAtUtc,
                    Round(point.VolumeKgRepetitions),
                    point.MaxWeightKg,
                    point.MaxRepetitions,
                    Round(point.EstimatedOneRepMaxKg),
                    point.BodyweightMissing))
                .ToList(),
            new RecordsResult(
                Round(data.Records.Current(RecordKind.MaxWeight)?.Value),
                Round(data.Records.Current(RecordKind.EstimatedOneRepMax)?.Value),
                Round(data.Records.Current(RecordKind.Volume)?.Value),
                Round(data.Records.Current(RecordKind.MaxRepetitions)?.Value)));
    }

    private static decimal Round(decimal value) => TrainingStatistics.RoundForOutput(value);

    private static decimal? Round(decimal? value) => value is { } present ? Round(present) : null;
}

public sealed record OverviewResult(
    DateOnly From,
    DateOnly Through,
    GoalResult? Goal,
    WeightResult Weight,
    NutritionResult Nutrition,
    TrainingResult Training);

public sealed record GoalResult(string Kind, decimal StartWeightKg, decimal TargetWeightKg, DateOnly? TargetDate);

public sealed record WeightResult(
    decimal? LatestKg,
    DateOnly? LatestDate,
    decimal? AverageKg,
    decimal? TrendKgPerWeek,
    int DaysWithWeight,
    decimal? SevenDayAverageKg,
    IReadOnlyList<WeightPointResult> Series);

public sealed record WeightPointResult(DateOnly Date, decimal WeightKg);

public sealed record NutritionResult(
    decimal? CaloriesKcalPerDay,
    decimal? ProteinGramsPerDay,
    decimal? CarbohydrateGramsPerDay,
    decimal? FatGramsPerDay,
    decimal? FiberGramsPerDay,
    int DaysWithNutrition);

public sealed record TrainingResult(
    int Workouts,
    decimal VolumeKgRepetitions,
    BestSetResult? BestSet,
    bool BodyweightMissingForSomeSets,
    int WorkoutsLast7Days);

public sealed record BestSetResult(Guid ExerciseId, decimal WeightKg, int Repetitions, decimal EstimatedOneRepMaxKg);

public sealed record WorkoutListResult(IReadOnlyList<WorkoutSummaryResult> Workouts);

public sealed record WorkoutSummaryResult(
    Guid WorkoutId,
    string Title,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    int CompletedSets);

public sealed record WorkoutResult(
    Guid WorkoutId,
    string Title,
    string? Notes,
    DateTime StartedAtUtc,
    DateTime? EndedAtUtc,
    IReadOnlyList<WorkoutExerciseResult> Exercises);

public sealed record WorkoutExerciseResult(
    Guid ExerciseId,
    string Name,
    string Type,
    string? Notes,
    IReadOnlyList<WorkoutSetResult> Sets);

public sealed record WorkoutSetResult(string SetType, decimal? WeightKg, int? Repetitions, decimal? RepsInReserve, string? Notes);

public sealed record ExerciseListResult(IReadOnlyList<ExerciseResult> Exercises);

public sealed record ExerciseResult(
    Guid ExerciseId,
    string Name,
    string Type,
    bool IsCustom,
    IReadOnlyList<string> PrimaryMuscles,
    IReadOnlyList<string> SecondaryMuscles);

public sealed record ExerciseProgressResult(
    Guid ExerciseId,
    string Name,
    IReadOnlyList<ExerciseProgressPointResult> Workouts,
    RecordsResult Records);

public sealed record ExerciseProgressPointResult(
    Guid WorkoutId,
    DateTime CompletedAtUtc,
    decimal VolumeKgRepetitions,
    decimal? MaxWeightKg,
    int MaxRepetitions,
    decimal? EstimatedOneRepMaxKg,
    bool BodyweightMissing);

public sealed record RecordsResult(
    decimal? MaxWeightKg,
    decimal? EstimatedOneRepMaxKg,
    decimal? VolumeKgRepetitions,
    decimal? MaxRepetitions);
