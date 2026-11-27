using System.ComponentModel;
using Gainer.Core.Insights;
using Gainer.Core.Training;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace Gainer.Api.Mcp;

/// <summary>Training plans and the summary of one completed workout.</summary>
[McpServerToolType]
public sealed class GainerTrainingTools(ITrainingPlanQueries plans, IWorkoutSummaryQueries summaries)
{
    [McpServerTool(Name = "list_training_plans", Title = "Trainingspläne", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("The user's training plans in their order: name, notes, archived flag and the entries in order " +
        "(exercise ID and name, warm-up sets, working sets, superset ID shared by entries trained together, notes).")]
    public async Task<TrainingPlansResult> ListTrainingPlans(
        [Description("Include archived plans.")] bool includeArchived = false,
        CancellationToken cancellationToken = default) =>
        new((await plans.ListAsync(includeArchived, cancellationToken)).Select(Plan).ToList());

    [McpServerTool(Name = "get_training_plan", Title = "Trainingsplan", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("One training plan, archived or not, with the same fields as list_training_plans.")]
    public async Task<TrainingPlanResult> GetTrainingPlan(
        [Description("ID of the plan from list_training_plans or list_workouts.")] Guid planId,
        CancellationToken cancellationToken = default) =>
        Plan(await plans.GetAsync(planId, cancellationToken)
            ?? throw new McpException("The training plan was not found."));

    [McpServerTool(Name = "get_workout_summary", Title = "Trainingszusammenfassung", ReadOnly = true,
        Idempotent = true, OpenWorld = false, UseStructuredContent = true)]
    [Description("Summary of one completed workout as on the app's summary screen: duration, counted sets " +
        "(warm-ups and sets without repetitions, or without weight for weighted exercises, do not count), total " +
        "repetitions, volume in kg × repetitions, best set per exercise (highest estimated one-rep max, Epley), " +
        "personal records first set in this workout, and which workout it was overall and in its Monday-to-Sunday " +
        "week (local days, Europe/Berlin). Weights are effective weights in kg including the body weight share. " +
        "Record values: MaxWeight and EstimatedOneRepMax in kg, Volume in kg × repetitions, MaxRepetitions as count.")]
    public async Task<WorkoutSummaryToolResult> GetWorkoutSummary(
        [Description("ID of the workout from list_workouts.")] Guid workoutId,
        CancellationToken cancellationToken = default)
    {
        WorkoutSummarySnapshot data = await summaries.WorkoutSummaryAsync(workoutId, McpDates.TimeZone, cancellationToken)
            ?? throw new McpException("The completed workout was not found.");
        TrainingSummary summary = data.Summary;
        return new WorkoutSummaryToolResult(
            data.WorkoutId,
            data.Title,
            data.StartedAtUtc,
            data.EndedAtUtc,
            (int)Math.Round(summary.Duration.TotalMinutes, MidpointRounding.AwayFromZero),
            summary.SetCount,
            summary.TotalRepetitions,
            TrainingStatistics.RoundForOutput(summary.VolumeKg),
            summary.BestSets
                .GroupBy(best => best.ExerciseId)
                .Select(group => TrainingStatistics.BestOf(group)!)
                .Select(best => new WorkoutBestSetResult(
                    best.ExerciseId,
                    data.ExerciseNames.GetValueOrDefault(best.ExerciseId),
                    TrainingStatistics.RoundForOutput(best.EffectiveWeightKg),
                    best.Repetitions,
                    TrainingStatistics.RoundForOutput(best.EstimatedOneRepMaxKg)))
                .ToList(),
            summary.NewRecords
                .Select(record => new WorkoutRecordResult(
                    record.ExerciseId,
                    data.ExerciseNames.GetValueOrDefault(record.ExerciseId),
                    record.Kind,
                    TrainingStatistics.RoundForOutput(record.Value)))
                .ToList(),
            data.Counts.Total,
            data.Counts.ThisWeek,
            data.BodyweightMissing);
    }

    private static TrainingPlanResult Plan(TrainingPlanDetail detail) => new(
        detail.Plan.PlanId,
        detail.Plan.Name,
        detail.Plan.Notes,
        detail.Plan.IsArchived,
        detail.Plan.Entries
            .Select(entry => new TrainingPlanEntryResult(
                entry.ExerciseId,
                detail.ExerciseNames.GetValueOrDefault(entry.ExerciseId),
                entry.WarmupSets,
                entry.WorkingSets,
                entry.SupersetId,
                entry.Notes))
            .ToList());
}

public sealed record TrainingPlansResult(IReadOnlyList<TrainingPlanResult> Plans);

public sealed record TrainingPlanResult(
    Guid PlanId,
    string Name,
    string? Notes,
    bool Archived,
    IReadOnlyList<TrainingPlanEntryResult> Entries);

public sealed record TrainingPlanEntryResult(
    Guid ExerciseId,
    string? ExerciseName,
    int WarmupSets,
    int WorkingSets,
    Guid? SupersetId,
    string? Notes);

public sealed record WorkoutSummaryToolResult(
    Guid WorkoutId,
    string Title,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    int DurationMinutes,
    int CountedSets,
    int TotalRepetitions,
    decimal VolumeKgRepetitions,
    IReadOnlyList<WorkoutBestSetResult> BestSets,
    IReadOnlyList<WorkoutRecordResult> NewRecords,
    int WorkoutNumberOverall,
    int WorkoutNumberThisWeek,
    bool BodyweightMissingForSomeSets);

public sealed record WorkoutBestSetResult(
    Guid ExerciseId,
    string? ExerciseName,
    decimal WeightKg,
    int Repetitions,
    decimal EstimatedOneRepMaxKg);

public sealed record WorkoutRecordResult(Guid ExerciseId, string? ExerciseName, RecordKind Kind, decimal Value);
