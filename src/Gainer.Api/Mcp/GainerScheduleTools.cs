using System.ComponentModel;
using Gainer.Core.Nutrition;
using Gainer.Core.Training;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace Gainer.Api.Mcp;

/// <summary>The training rhythm as the app projects it: today's card, calendar markers and the coming days.</summary>
[McpServerToolType]
public sealed class GainerScheduleTools(ITrainingScheduleQueries schedules, TimeProvider timeProvider)
{
    private const int DefaultScheduleDays = 15;
    private const int MaximumScheduleDays = 62;

    [McpServerTool(Name = "get_training_schedule", Title = "Trainingsrhythmus", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("The training rhythm and its projection per local day (Europe/Berlin), computed as in the app's " +
        "calendar and \"Nächste 14 Tage\" list. The rhythm is a Cycle (ordered slots of plans and rest days repeating " +
        "from AnchorDate, shiftable) or Weekly (seven slots, position 0 = Monday); nothing is planned before ValidFrom; " +
        "TodayCycleSlot is the cycle slot that counts for today. A slot without plan is a rest day; PlanArchived marks " +
        "a slot whose plan is archived, which also counts as rest day. " +
        "Per day: BaseKind (None without rhythm or before ValidFrom, Rest also for a slot whose plan is archived, " +
        "Paused for days freed by shifting the cycle, Training), the slot index, the finished strength workouts started " +
        "that day, the AutomaticDayKind that selects the rest-day nutrition target (Training when a strength workout " +
        "was finished or a workout of the rhythm is due, done, missed or moved in; otherwise Rest) and the workouts: " +
        "the one the rhythm plans there plus those moved in from another day (MovedInFrom). Status: Planned (today or " +
        "later, not done), Done (a finished workout from this plan was started that day), Missed (past, no workout " +
        "finished), InsteadOf (past, a workout from another plan was finished instead), Moved (only this workout lies " +
        "on MovedToDate) or Skipped. Defaults to today and the next 14 days; at most 62 days, past days allowed.")]
    public async Task<TrainingScheduleResult> GetTrainingSchedule(
        [Description("First local day (YYYY-MM-DD); default today.")] DateOnly? from = null,
        [Description("Number of days from the first day, 1 to 62; default 15 (today and the next 14 days).")] int days = DefaultScheduleDays,
        CancellationToken cancellationToken = default)
    {
        if (days is < 1 or > MaximumScheduleDays)
        {
            throw new McpException($"days must be between 1 and {MaximumScheduleDays}.");
        }

        DateOnly today = McpDates.Today(timeProvider);
        DateOnly start = from ?? today;
        DateOnly through = start.AddDays(days - 1);
        TrainingScheduleProjection projection = await schedules.ProjectionAsync(
            start, through, today, McpDates.TimeZone, cancellationToken);
        ScheduleProjectionInput? schedule = projection.Schedule;
        return new TrainingScheduleResult(
            today,
            start,
            through,
            schedule is null ? null : Rhythm(projection, schedule),
            projection.Days(start, through).Select(day => Day(projection, day)).ToList());
    }

    [McpServerTool(Name = "get_training_today", Title = "Heute", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("What the app's \"Heute\" card shows for today (local day, Europe/Berlin): whether a training rhythm " +
        "exists, today's projected day with the same fields as get_training_schedule (open, done, moved and skipped " +
        "workouts, finished workouts, AutomaticDayKind), and the next open (Planned) workout after today within 60 days, " +
        "which the card names on a rest day.")]
    public async Task<TrainingTodayResult> GetTrainingToday(CancellationToken cancellationToken = default)
    {
        DateOnly today = McpDates.Today(timeProvider);
        TrainingScheduleProjection projection = await schedules.ProjectionAsync(
            today, today.AddDays(TrainingScheduleProjection.DefaultHorizonDays), today, McpDates.TimeZone, cancellationToken);
        ScheduledTraining? next = projection.NextPlannedAfter(today);
        return new TrainingTodayResult(
            today,
            projection.Schedule is not null,
            Day(projection, projection.Day(today)),
            next is null ? null : Training(next));
    }

    private static ScheduleRhythmResult Rhythm(TrainingScheduleProjection projection, ScheduleProjectionInput schedule) => new(
        schedule.Mode,
        schedule.Mode == TrainingScheduleMode.Cycle ? schedule.AnchorDate : null,
        schedule.ValidFrom,
        projection.EffectiveCycleIndex(projection.Today),
        schedule.SlotPlanIds
            .Select((planId, index) => new ScheduleSlotResult(
                index,
                planId,
                planId is { } id ? projection.PlanName(id) : null,
                planId is not null && !projection.IsActivePlan(planId)))
            .ToList());

    private static ScheduleDayResult Day(TrainingScheduleProjection projection, ScheduleDay day) => new(
        day.Date,
        day.BaseKind,
        day.SlotIndex,
        day.ArchivedPlanId,
        day.IsFree,
        projection.AutomaticDayKind(day.Date),
        projection.FinishedOn(day.Date).Select(workout => workout.WorkoutId).ToList(),
        day.Trainings.Select(Training).ToList());

    private static ScheduledTrainingResult Training(ScheduledTraining training) => new(
        training.PlanId,
        training.PlanName,
        training.Date,
        training.Status,
        training.IsMovedIn ? training.OriginDate : null,
        training.MovedToDate,
        training.CompletedBy,
        training.Instead);
}

public sealed record TrainingScheduleResult(
    DateOnly Today,
    DateOnly From,
    DateOnly Through,
    ScheduleRhythmResult? Rhythm,
    IReadOnlyList<ScheduleDayResult> Days);

public sealed record ScheduleRhythmResult(
    TrainingScheduleMode Mode,
    DateOnly? AnchorDate,
    DateOnly ValidFrom,
    int? TodayCycleSlot,
    IReadOnlyList<ScheduleSlotResult> Slots);

public sealed record ScheduleSlotResult(int Position, Guid? PlanId, string? PlanName, bool PlanArchived);

public sealed record ScheduleDayResult(
    DateOnly Date,
    ScheduleBaseKind BaseKind,
    int? SlotIndex,
    Guid? ArchivedPlanId,
    bool IsFree,
    NutritionDayKind AutomaticDayKind,
    IReadOnlyList<Guid> FinishedWorkoutIds,
    IReadOnlyList<ScheduledTrainingResult> Trainings);

public sealed record ScheduledTrainingResult(
    Guid PlanId,
    string PlanName,
    DateOnly Date,
    ScheduledTrainingStatus Status,
    DateOnly? MovedInFrom,
    DateOnly? MovedToDate,
    IReadOnlyList<Guid> CompletedByWorkoutIds,
    IReadOnlyList<Guid> InsteadWorkoutIds);

public sealed record TrainingTodayResult(
    DateOnly Today,
    bool HasSchedule,
    ScheduleDayResult Day,
    ScheduledTrainingResult? NextPlanned);
