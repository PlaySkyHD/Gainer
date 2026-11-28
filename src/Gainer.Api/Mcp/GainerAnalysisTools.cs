using System.ComponentModel;
using Gainer.Core.Insights;
using Gainer.Core.Training;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace Gainer.Api.Mcp;

/// <summary>The app's training analysis: progress status, fatigue signals and a rule-based recommendation per exercise.</summary>
[McpServerToolType]
public sealed class GainerAnalysisTools(ITrainingAnalysisQueries analysis, IExerciseResolver exercises, TimeProvider timeProvider)
{
    [McpServerTool(Name = "get_training_analysis", Title = "Trainingsanalyse", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("The app's training analysis for a period ending today (local days, Europe/Berlin), computed exactly " +
        "as in the app. Per exercise trained in the period: sessions (completed workouts with at least one recorded " +
        "working set; warm-ups never count), first and last day, best estimated one-rep max (Epley, effective weight " +
        "as in get_workout_summary), trends that compare the mean of the first third with the mean of the last third " +
        "of the sessions (at least one session each, from two sessions) for e1RM, top weight, top-set repetitions and " +
        "session volume, plus volume (kg × repetitions) and working sets per week. Status: InsufficientData below 3 " +
        "sessions; Regressing when the e1RM change is -2.5 % or less; Progressing when it is +2.5 % or more and the " +
        "best e1RM was reached within the last 3 sessions; otherwise Stagnating. Fatigue signals with evidence: " +
        "DecliningRepetitions (top-set repetitions fell twice in a row over the last 3 sessions at the same or a " +
        "lower top weight), FailureOnMostSets (in each of the last 2 sessions at least 2 working sets have an RIR " +
        "and more than half of them RIR 0), VolumeAndStrengthDrop (last session at least 20 % less volume and 5 % " +
        "less e1RM than the mean of up to 3 sessions before). Recommendation for the next session from the last " +
        "session: Deload (90 % of the logged weight rounded down to the step) on any fatigue signal or Regressing; " +
        "ChangeStimulus when Stagnating with at least 4 sessions since the best e1RM; otherwise double progression " +
        "in a repetition range chosen by the best top set (up to 5 reps: 3-5, up to 12: 6-12, above: 13-20): all " +
        "top sets at the top of the range -> IncreaseWeight by the step (smallest difference between logged weights " +
        "in the period, at most 2.5 kg, default 2.5 kg) for strength and weighted bodyweight exercises, " +
        "ChangeStimulus for bodyweight-only and assisted ones; a top set below the range -> KeepWeight; otherwise " +
        "IncreaseReps by one. Weights in recommendations are the logged weights (added or assistance weight); " +
        "Text is the German reason the app shows. Overall: 7-day buckets from the period start across all " +
        "exercises (also with exerciseId), the weekly volume trend over complete buckets and Fatigued when at least " +
        "one exercise has a signal and those are at least a third of the exercises with 3 or more sessions. The " +
        "recommendations are rule-based suggestions from logged data, not medical or coaching advice. Values in " +
        "results are PascalCase; inputs accept any case.")]
    public async Task<TrainingAnalysisResult> GetTrainingAnalysis(
        [Description("fourWeeks (4 weeks from Monday), threeMonths (13 weeks, default) or year (12 months).")]
        string period = "threeMonths",
        [Description("Only this exercise (ID from search_exercises); omit for all exercises of the period.")]
        Guid? exerciseId = null,
        CancellationToken cancellationToken = default)
    {
        TrendPeriod parsed = period.Trim().ToLowerInvariant() switch
        {
            "fourweeks" => TrendPeriod.FourWeeks,
            "threemonths" => TrendPeriod.ThreeMonths,
            "year" => TrendPeriod.Year,
            _ => throw new McpException("period must be fourWeeks, threeMonths or year."),
        };
        if (exerciseId is { } id && await exercises.ResolveAsync(id, includeArchived: true, cancellationToken) is null)
        {
            throw new McpException("The exercise was not found.");
        }

        TrainingAnalysisSnapshot snapshot = await analysis.AnalysisAsync(
            parsed, McpDates.Today(timeProvider), McpDates.TimeZone, cancellationToken);
        return new TrainingAnalysisResult(
            parsed,
            snapshot.Start,
            snapshot.Today,
            snapshot.Exercises
                .Where(item => exerciseId is null || item.ExerciseId == exerciseId)
                .Select(ToResult)
                .ToList(),
            new TrainingAnalysisOverallResult(
                Round(snapshot.Overall.WeeklyVolumeChangePercent),
                snapshot.Overall.ExercisesWithFatigue,
                snapshot.Overall.EligibleExercises,
                snapshot.Overall.Fatigued,
                snapshot.Overall.Weeks
                    .Select(week => new AnalysisWeekResult(
                        week.Start,
                        Min(week.Start.AddDays(6), snapshot.Today),
                        week.Complete,
                        Round(week.VolumeKg),
                        week.WorkingSets))
                    .ToList()));
    }

    private static ExerciseAnalysisResult ToResult(ExerciseAnalysis item) => new(
        item.ExerciseId,
        item.Name,
        item.ExerciseType,
        item.Status,
        item.Sessions.Count,
        item.Sessions.Count == 0 ? null : item.Sessions[0].Day,
        item.Sessions.Count == 0 ? null : item.Sessions[^1].Day,
        Round(item.BestEstimatedOneRepMaxKg),
        item.SessionsSinceBest,
        new ExerciseTrendResult(
            Round(item.EstimatedOneRepMaxFirstKg),
            Round(item.EstimatedOneRepMaxLastKg),
            Round(item.EstimatedOneRepMaxChangePercent),
            Round(item.TopWeightChangePercent),
            Round(item.TopRepetitionsChange),
            Round(item.VolumeChangePercent),
            Round(item.VolumePerWeekKg),
            Round(item.WorkingSetsPerWeek)),
        item.FatigueSignals
            .Select(signal => new FatigueSignalResult(
                signal.Kind,
                signal.Sessions,
                signal.FromRepetitions,
                signal.ToRepetitions,
                Round(signal.WeightKg),
                signal.ZeroRirSets,
                signal.RatedSets,
                Round(signal.VolumeChangePercent),
                Round(signal.EstimatedOneRepMaxChangePercent)))
            .ToList(),
        new RecommendationResult(
            item.Recommendation.Kind,
            Round(item.Recommendation.SuggestedWeightKg),
            item.Recommendation.SuggestedRepetitions,
            item.Recommendation.RepetitionRangeLow,
            item.Recommendation.RepetitionRangeHigh,
            Round(item.Recommendation.WeightStepKg),
            item.Recommendation.Text),
        item.Sessions
            .Select(session => new AnalysisSessionResult(
                session.WorkoutId,
                session.Day,
                session.WorkingSets,
                Round(session.VolumeKg),
                Round(session.EstimatedOneRepMaxKg),
                Round(session.TopWeightKg),
                session.TopSetMinRepetitions,
                session.TopSetMaxRepetitions,
                session.TopLoggedWeightKg))
            .ToList());

    private static DateOnly Min(DateOnly left, DateOnly right) => left < right ? left : right;

    private static decimal Round(decimal value) => TrainingStatistics.RoundForOutput(value);

    private static decimal? Round(decimal? value) => TrainingStatistics.RoundForOutput(value);
}

public sealed record TrainingAnalysisResult(
    TrendPeriod Period,
    DateOnly From,
    DateOnly Through,
    IReadOnlyList<ExerciseAnalysisResult> Exercises,
    TrainingAnalysisOverallResult Overall);

public sealed record ExerciseAnalysisResult(
    Guid ExerciseId,
    string Name,
    ExerciseType ExerciseType,
    ExerciseProgressStatus Status,
    int Sessions,
    DateOnly? FirstDay,
    DateOnly? LastDay,
    decimal? BestEstimatedOneRepMaxKg,
    int SessionsSinceBest,
    ExerciseTrendResult Trend,
    IReadOnlyList<FatigueSignalResult> FatigueSignals,
    RecommendationResult Recommendation,
    IReadOnlyList<AnalysisSessionResult> SessionDetails);

/// <summary>First-third and last-third means and their changes; null below two sessions.</summary>
public sealed record ExerciseTrendResult(
    decimal? EstimatedOneRepMaxFirstKg,
    decimal? EstimatedOneRepMaxLastKg,
    decimal? EstimatedOneRepMaxChangePercent,
    decimal? TopWeightChangePercent,
    decimal? TopSetRepetitionsChange,
    decimal? SessionVolumeChangePercent,
    decimal VolumePerWeekKgRepetitions,
    decimal WorkingSetsPerWeek);

public sealed record FatigueSignalResult(
    FatigueSignalKind Kind,
    int Sessions,
    int? FromRepetitions,
    int? ToRepetitions,
    decimal? TopWeightKg,
    int? ZeroRirSets,
    int? RatedSets,
    decimal? VolumeChangePercent,
    decimal? EstimatedOneRepMaxChangePercent);

public sealed record RecommendationResult(
    RecommendationKind Kind,
    decimal? SuggestedWeightKg,
    int? SuggestedRepetitions,
    int? RepetitionRangeLow,
    int? RepetitionRangeHigh,
    decimal? WeightStepKg,
    string Text);

public sealed record AnalysisSessionResult(
    Guid WorkoutId,
    DateOnly Day,
    int WorkingSets,
    decimal VolumeKgRepetitions,
    decimal EstimatedOneRepMaxKg,
    decimal TopEffectiveWeightKg,
    int TopSetMinRepetitions,
    int TopSetMaxRepetitions,
    decimal? TopLoggedWeightKg);

public sealed record AnalysisWeekResult(DateOnly From, DateOnly Through, bool Complete, decimal VolumeKgRepetitions, int WorkingSets);

public sealed record TrainingAnalysisOverallResult(
    decimal? WeeklyVolumeChangePercent,
    int ExercisesWithFatigue,
    int ExercisesWithEnoughSessions,
    bool Fatigued,
    IReadOnlyList<AnalysisWeekResult> Weeks);
