using System.ComponentModel;
using Gainer.Core.Insights;
using Gainer.Core.Training;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace Gainer.Api.Mcp;

/// <summary>Trend tiles, training heatmap and muscle map of the app's training statistics, computed as in the app.</summary>
[McpServerToolType]
public sealed class GainerStatisticsTools(ITrainingAnalysisQueries analysis, TimeProvider timeProvider)
{
    [McpServerTool(Name = "get_training_trends", Title = "Trainingsverlauf", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("The trend tiles of the app's training statistics for a period ending today (local days, " +
        "Europe/Berlin): completed workouts, workouts per week, average and total duration in minutes, volume in " +
        "kg × repetitions, counted sets, repetitions, repetitions per set and body weight in kg (latest check-in of " +
        "the period). Buckets are weeks from Monday for fourWeeks and threeMonths, calendar months for year and all; " +
        "the last bucket contains today. A bucket without data omits its averages (no zero). Sets and volume follow " +
        "get_workout_summary: warm-ups are excluded unless includeWarmups is true.")]
    public async Task<TrainingTrendsResult> GetTrainingTrends(
        [Description("fourWeeks (4 weeks from Monday), threeMonths (13 weeks), year (12 months) or all (from the " +
            "month of the first workout or check-in).")] string period = "threeMonths",
        [Description("Count warm-up sets in sets, repetitions and volume.")] bool includeWarmups = false,
        CancellationToken cancellationToken = default)
    {
        TrendPeriod parsed = period.Trim().ToLowerInvariant() switch
        {
            "fourweeks" => TrendPeriod.FourWeeks,
            "threemonths" => TrendPeriod.ThreeMonths,
            "year" => TrendPeriod.Year,
            "all" => TrendPeriod.All,
            _ => throw new McpException("period must be fourWeeks, threeMonths, year or all."),
        };
        DateOnly today = McpDates.Today(timeProvider);
        TrainingTrendsSnapshot trends = await analysis.TrendsAsync(parsed, includeWarmups, today, McpDates.TimeZone, cancellationToken);
        return new TrainingTrendsResult(
            parsed,
            trends.Start,
            trends.Today,
            parsed is TrendPeriod.FourWeeks or TrendPeriod.ThreeMonths ? "week" : "month",
            trends.WorkoutCount,
            Round(trends.WorkoutsPerWeek),
            trends.AverageDuration is { } average ? Minutes(average) : null,
            Minutes(trends.TotalDuration),
            Round(trends.VolumeKg),
            trends.SetCount,
            trends.Repetitions,
            Round(trends.RepetitionsPerSet),
            trends.LatestBodyweightKg,
            trends.Buckets
                .Select((bucket, index) => new TrendBucketResult(
                    bucket.Start,
                    index + 1 < trends.Buckets.Count ? trends.Buckets[index + 1].Start.AddDays(-1) : trends.Today,
                    bucket.Workouts,
                    Round(bucket.TotalMinutes),
                    Round(bucket.AverageMinutes),
                    Round(bucket.VolumeKg),
                    bucket.Sets,
                    bucket.Repetitions,
                    Round(bucket.RepetitionsPerSet),
                    Round(bucket.BodyweightKg)))
                .ToList());
    }

    [McpServerTool(Name = "get_training_heatmap", Title = "Trainingstage", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("The training heatmap of the app's statistics: the twelve months up to today (from the day after " +
        "today one year ago, local days Europe/Berlin), minutes trained per day from completed strength workouts and " +
        "cardio sessions (a session counts fully for its local start day) and the intensity level 1 to 4 per training " +
        "day: 1 plus the number of quartile bounds (minutes of all training days) the day exceeds; when all training " +
        "days are equally long every one has level 4. Only training days are listed; all other days have level 0.")]
    public async Task<TrainingHeatmapResult> GetTrainingHeatmap(CancellationToken cancellationToken = default)
    {
        TrainingHeatmapSnapshot heatmap = await analysis.HeatmapAsync(McpDates.Today(timeProvider), McpDates.TimeZone, cancellationToken);
        return new TrainingHeatmapResult(
            heatmap.Start,
            heatmap.Today,
            heatmap.WeekCount,
            heatmap.Days.Count,
            heatmap.Days.Sum(day => day.Minutes),
            heatmap.Bounds.Select(bound => Math.Round((decimal)bound, 2, MidpointRounding.AwayFromZero)).ToList(),
            heatmap.Days.Select(day => new TrainingHeatmapDayResult(day.Date, day.Minutes, day.Level)).ToList());
    }

    [McpServerTool(Name = "get_muscle_volume", Title = "Muskelvolumen", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("The app's muscle map: working sets per muscle, where a primary muscle counts each set fully and a " +
        "secondary muscle half. planned counts the working sets of the entries of one plan or of all plans that are " +
        "not archived (an archived plan counts nothing, as in the app). trained counts recorded sets without warm-ups " +
        "of completed workouts that started in the last 7 days (week) or 28 days (fourWeeks, as average per week). " +
        "All 17 muscles are listed by sets, highest first, with level None (0), Low (below 4), Medium (below 10), " +
        "High (up to 20) or VeryHigh, and the contributing exercises. Exercises without any muscles are listed " +
        "separately. Values in results are PascalCase; inputs accept any case.")]
    public async Task<MuscleVolumeResult> GetMuscleVolume(
        [Description("planned (from training plans) or trained (from completed workouts).")] string source = "planned",
        [Description("Only for planned: ID of one plan from list_training_plans; omit for all active plans.")]
        Guid? planId = null,
        [Description("Only for trained: week (last 7 days, default) or fourWeeks (last 28 days, per week).")]
        string? period = null,
        CancellationToken cancellationToken = default)
    {
        MuscleVolumeSnapshot volume;
        switch (source.Trim().ToLowerInvariant())
        {
            case "planned":
                if (period is not null) throw new McpException("period applies only to source trained.");
                volume = await analysis.PlannedMuscleVolumeAsync(planId, cancellationToken)
                    ?? throw new McpException("The training plan was not found.");
                break;
            case "trained":
                if (planId is not null) throw new McpException("planId applies only to source planned.");
                (int days, int weeks) = (period ?? "week").Trim().ToLowerInvariant() switch
                {
                    "week" => (7, 1),
                    "fourweeks" => (28, 4),
                    _ => throw new McpException("period must be week or fourWeeks."),
                };
                DateTime now = timeProvider.GetUtcNow().UtcDateTime;
                volume = await analysis.TrainedMuscleVolumeAsync(now.AddDays(-days), now, weeks, cancellationToken);
                break;
            default:
                throw new McpException("source must be planned or trained.");
        }

        return new MuscleVolumeResult(
            volume.Muscles
                .Select(muscle => new MuscleSetsResult(
                    muscle.Muscle,
                    Round(muscle.Sets),
                    muscle.Level,
                    muscle.Contributions
                        .Select(item => new MuscleContributionResult(
                            item.ExerciseId, item.ExerciseName, item.Role, Round(item.WorkingSets), Round(item.Sets)))
                        .ToList()))
                .ToList(),
            volume.ExercisesWithoutMuscles.Select(item => new ExerciseReferenceResult(item.ExerciseId, item.Name)).ToList());
    }

    private static decimal Minutes(TimeSpan duration) => Round(duration.Ticks / TimeSpan.TicksPerSecond / 60m);

    private static decimal Round(decimal value) => TrainingStatistics.RoundForOutput(value);

    private static decimal? Round(decimal? value) => TrainingStatistics.RoundForOutput(value);
}

public sealed record TrainingTrendsResult(
    TrendPeriod Period,
    DateOnly From,
    DateOnly Through,
    string BucketSize,
    int Workouts,
    decimal WorkoutsPerWeek,
    decimal? AverageDurationMinutes,
    decimal TotalDurationMinutes,
    decimal VolumeKgRepetitions,
    int Sets,
    int Repetitions,
    decimal? RepetitionsPerSet,
    decimal? LatestBodyweightKg,
    IReadOnlyList<TrendBucketResult> Buckets);

public sealed record TrendBucketResult(
    DateOnly From,
    DateOnly Through,
    int Workouts,
    decimal TotalDurationMinutes,
    decimal? AverageDurationMinutes,
    decimal VolumeKgRepetitions,
    int Sets,
    int Repetitions,
    decimal? RepetitionsPerSet,
    decimal? AverageBodyweightKg);

public sealed record TrainingHeatmapResult(
    DateOnly From,
    DateOnly Through,
    int Weeks,
    int TrainingDays,
    int TotalMinutes,
    IReadOnlyList<decimal> QuartileBoundsMinutes,
    IReadOnlyList<TrainingHeatmapDayResult> Days);

public sealed record TrainingHeatmapDayResult(DateOnly Date, int Minutes, int Level);

public sealed record MuscleVolumeResult(
    IReadOnlyList<MuscleSetsResult> Muscles,
    IReadOnlyList<ExerciseReferenceResult> ExercisesWithoutMuscles);

public sealed record MuscleSetsResult(
    string Muscle,
    decimal Sets,
    MuscleLevel Level,
    IReadOnlyList<MuscleContributionResult> Exercises);

public sealed record MuscleContributionResult(
    Guid ExerciseId,
    string Name,
    MuscleRole Role,
    decimal WorkingSets,
    decimal WeightedSets);

public sealed record ExerciseReferenceResult(Guid ExerciseId, string Name);
