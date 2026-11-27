using Gainer.Core.Insights;
using Gainer.Core.Nutrition;

namespace Gainer.Core.Training;

/// <summary>The stored rhythm as the projection needs it; slots, shifts and exceptions in their stored order.</summary>
public sealed record ScheduleProjectionInput(
    TrainingScheduleMode Mode,
    DateOnly? AnchorDate,
    DateOnly ValidFrom,
    IReadOnlyList<Guid?> SlotPlanIds,
    IReadOnlyList<ScheduleShiftInput> Shifts,
    IReadOnlyList<ScheduleExceptionInput> Exceptions);

/// <summary>From <paramref name="FromDate"/> on the cycle lies <paramref name="Days"/> days later; the freed days are paused.</summary>
public sealed record ScheduleShiftInput(DateOnly FromDate, int Days)
{
    public bool Pauses(DateOnly date) => date >= FromDate && date < FromDate.AddDays(Days);
}

/// <summary>Moves (or, without <paramref name="MovedToDate"/>, skips) the workout of one plan planned on one day.</summary>
public sealed record ScheduleExceptionInput(DateOnly Date, Guid PlanId, DateOnly? MovedToDate)
{
    public bool IsSkip => MovedToDate is null;
}

/// <summary>A plan of the user, archived ones included: a slot with an archived or unknown plan is a rest day.</summary>
public sealed record SchedulePlanInput(Guid PlanId, string Name, bool IsArchived);

/// <summary>A strength workout; only finished, not deleted workouts count for the local day of their start.</summary>
public sealed record ScheduleWorkoutInput(
    Guid WorkoutId,
    DateTime StartedAtUtc,
    DateTime? EndedAtUtc,
    DateTime? DeletedAtUtc,
    Guid? SourcePlanId);

/// <summary>What the rhythm itself plans for a day, before exceptions.</summary>
public enum ScheduleBaseKind
{
    /// <summary>No rhythm, before its valid-from day or without usable slots.</summary>
    None,

    /// <summary>Rest day, also for a slot whose plan is archived or unknown.</summary>
    Rest,

    /// <summary>Freed by shifting the cycle.</summary>
    Paused,

    /// <summary>An active plan is planned.</summary>
    Training,
}

/// <summary>Status of a planned workout on its day.</summary>
public enum ScheduledTrainingStatus
{
    /// <summary>Today or later and not done yet.</summary>
    Planned,

    /// <summary>A finished workout from this plan was started that day.</summary>
    Done,

    /// <summary>In the past, no workout was finished that day.</summary>
    Missed,

    /// <summary>In the past, a workout from another plan was finished that day.</summary>
    InsteadOf,

    /// <summary>Only this workout lies on another day.</summary>
    Moved,

    /// <summary>This workout is dropped.</summary>
    Skipped,
}

/// <summary>A planned workout on a day.</summary>
/// <param name="Date">Day on which the workout is shown.</param>
/// <param name="OriginDate">Day on which the rhythm plans it; differs from <paramref name="Date"/> for moved-in workouts.</param>
/// <param name="MovedToDate">Target of a move for <see cref="ScheduledTrainingStatus.Moved"/>.</param>
/// <param name="CompletedBy">Finished workouts from this plan started that day.</param>
/// <param name="Instead">For <see cref="ScheduledTrainingStatus.InsteadOf"/>: the workouts finished instead.</param>
public sealed record ScheduledTraining(
    Guid PlanId,
    string PlanName,
    DateOnly Date,
    DateOnly OriginDate,
    ScheduledTrainingStatus Status,
    DateOnly? MovedToDate,
    IReadOnlyList<Guid> CompletedBy,
    IReadOnlyList<Guid> Instead)
{
    /// <summary>Moved here from another day by an exception.</summary>
    public bool IsMovedIn => OriginDate != Date;

    /// <summary>Planned and not done yet.</summary>
    public bool IsOpen => Status == ScheduledTrainingStatus.Planned;
}

/// <summary>A day of the projection with the workout the rhythm plans (moved or skipped included) and the moved-in ones.</summary>
/// <param name="SlotIndex">Slot of the rhythm that day; null without rhythm and on paused days.</param>
/// <param name="ArchivedPlanId">Plan of the slot that is archived or unknown and therefore counts as rest day.</param>
public sealed record ScheduleDay(
    DateOnly Date,
    ScheduleBaseKind BaseKind,
    int? SlotIndex,
    Guid? ArchivedPlanId,
    IReadOnlyList<ScheduledTraining> Trainings)
{
    /// <summary>Workouts that are actually due or done that day (not moved away or skipped).</summary>
    public IReadOnlyList<ScheduledTraining> Effective =>
        Trainings.Where(item => item.Status is not (ScheduledTrainingStatus.Moved or ScheduledTrainingStatus.Skipped)).ToList();

    /// <summary>No workout is due: rest day, paused, or everything moved away.</summary>
    public bool IsFree => Effective.Count == 0;
}

/// <summary>
/// Port of the app's training schedule projection (<c>TrainingScheduleProjection</c> in training_schedule.dart); the
/// rules are in contracts/fixtures/training-schedule.json. Pure and deterministic: rhythm, plans, workouts and today are
/// passed in, workouts count for the local day of their start in <c>timeZone</c>.
/// </summary>
public sealed class TrainingScheduleProjection
{
    /// <summary>How far <see cref="NextPlannedAfter"/> looks ahead by default, as in the app.</summary>
    public const int DefaultHorizonDays = 60;

    /// <summary>Longest single shift of the cycle (contract), used to find today's cycle slot on paused days.</summary>
    private const int MaxShiftDays = 31;

    private readonly Dictionary<Guid, SchedulePlanInput> plans;
    private readonly Dictionary<DateOnly, List<ScheduleWorkoutInput>> finishedByDay;

    public TrainingScheduleProjection(
        ScheduleProjectionInput? schedule,
        IEnumerable<SchedulePlanInput> plans,
        IEnumerable<ScheduleWorkoutInput> workouts,
        DateOnly today,
        TimeZoneInfo timeZone)
    {
        ArgumentNullException.ThrowIfNull(plans);
        ArgumentNullException.ThrowIfNull(workouts);
        ArgumentNullException.ThrowIfNull(timeZone);
        Schedule = schedule;
        Today = today;
        this.plans = new Dictionary<Guid, SchedulePlanInput>();
        foreach (SchedulePlanInput plan in plans) this.plans[plan.PlanId] = plan;
        finishedByDay = [];
        foreach (ScheduleWorkoutInput workout in workouts)
        {
            if (workout.EndedAtUtc is null || workout.DeletedAtUtc is not null) continue;
            DateOnly day = LocalDays.DateOf(workout.StartedAtUtc, timeZone);
            if (!finishedByDay.TryGetValue(day, out List<ScheduleWorkoutInput>? list))
            {
                list = [];
                finishedByDay[day] = list;
            }
            list.Add(workout);
        }
    }

    /// <summary>Null without rhythm; then every day is <see cref="ScheduleBaseKind.None"/>.</summary>
    public ScheduleProjectionInput? Schedule { get; }

    public DateOnly Today { get; }

    public bool IsCycle => Schedule?.Mode == TrainingScheduleMode.Cycle;

    /// <summary>Name of a plan; "Plan" for an unknown one, as in the app.</summary>
    public string PlanName(Guid planId) => plans.GetValueOrDefault(planId)?.Name ?? "Plan";

    /// <summary>Finished, not deleted strength workouts started on <paramref name="date"/>, also without rhythm.</summary>
    public IReadOnlyList<ScheduleWorkoutInput> FinishedOn(DateOnly date) =>
        finishedByDay.TryGetValue(date, out List<ScheduleWorkoutInput>? list) ? list : [];

    public bool HasFinishedOn(DateOnly date) => FinishedOn(date).Count > 0;

    /// <summary>Active plan the rhythm plans on <paramref name="date"/> without exceptions.</summary>
    public Guid? BasePlanOn(DateOnly date)
    {
        if (Schedule is not { } active) return null;
        RawSlot raw = RawSlotOn(active, date);
        if (raw.Kind != RawSlotKind.Slot) return null;
        Guid? planId = active.SlotPlanIds[raw.Index];
        return IsActivePlan(planId) ? planId : null;
    }

    /// <summary>An exception applies only while its day still plans the same plan.</summary>
    public bool IsEffective(ScheduleExceptionInput exception)
    {
        ArgumentNullException.ThrowIfNull(exception);
        return BasePlanOn(exception.Date) == exception.PlanId;
    }

    /// <summary>Cycle slot of <paramref name="date"/>; null for weekly schedules, paused days and before valid-from.</summary>
    public int? CycleSlotIndexOn(DateOnly date)
    {
        if (Schedule is not { } active || !IsCycle) return null;
        RawSlot raw = RawSlotOn(active, date);
        return raw.Kind == RawSlotKind.Slot ? raw.Index : null;
    }

    /// <summary>
    /// Cycle slot that counts for <paramref name="date"/> as the editor's "today is": on a paused day the slot before
    /// the next day that is not paused. Null for weekly schedules or without slots.
    /// </summary>
    public int? EffectiveCycleIndex(DateOnly date)
    {
        if (Schedule is not { } active || !IsCycle || active.SlotPlanIds.Count == 0) return null;
        for (int offset = 0; offset <= MaxShiftDays * 2; offset++)
        {
            if (CycleSlotIndexOn(date.AddDays(offset)) is { } index) return Modulo(index - offset, active.SlotPlanIds.Count);
        }
        return null;
    }

    public ScheduleDay Day(DateOnly date)
    {
        if (Schedule is not { } active) return new ScheduleDay(date, ScheduleBaseKind.None, null, null, []);
        BaseSlot slot = BaseOf(active, RawSlotOn(active, date));
        IReadOnlyList<ScheduleWorkoutInput> finished = FinishedOn(date);

        var entries = new List<Entry>();
        if (slot.BasePlan is { } basePlan)
        {
            entries.Add(new Entry(basePlan, date,
                active.Exceptions.FirstOrDefault(item => item.Date == date && item.PlanId == basePlan)));
        }
        foreach (ScheduleExceptionInput exception in active.Exceptions)
        {
            if (exception.MovedToDate == date && exception.Date != date && IsEffective(exception))
            {
                entries.Add(new Entry(exception.PlanId, exception.Date, null));
            }
        }

        // Workouts from planned plans do not count as "instead".
        HashSet<Guid> scheduledPlans = entries.Where(item => item.Exception is null).Select(item => item.PlanId).ToHashSet();
        ScheduleWorkoutInput[] others = finished
            .Where(workout => workout.SourcePlanId is not { } planId || !scheduledPlans.Contains(planId))
            .ToArray();
        return new ScheduleDay(
            date,
            slot.Kind,
            slot.SlotIndex,
            slot.ArchivedPlanId,
            entries.Select(entry => Training(entry, date, finished, others)).ToList());
    }

    /// <summary>Days from <paramref name="from"/> through <paramref name="through"/>, inclusive.</summary>
    public IReadOnlyList<ScheduleDay> Days(DateOnly from, DateOnly through)
    {
        var days = new List<ScheduleDay>();
        for (DateOnly date = from; date <= through; date = date.AddDays(1)) days.Add(Day(date));
        return days;
    }

    /// <summary>Next open workout after <paramref name="after"/> within <paramref name="horizonDays"/> days.</summary>
    public ScheduledTraining? NextPlannedAfter(DateOnly after, int horizonDays = DefaultHorizonDays)
    {
        if (Schedule is null) return null;
        for (int offset = 1; offset <= horizonDays; offset++)
        {
            ScheduledTraining? open = Day(after.AddDays(offset)).Trainings.FirstOrDefault(item => item.IsOpen);
            if (open is not null) return open;
        }
        return null;
    }

    /// <summary>
    /// Day kind without a choice of the user: training day when a strength workout was finished that day or the rhythm
    /// has a workout due or done there (also missed or moved in); otherwise rest day, also without rhythm.
    /// </summary>
    public NutritionDayKind AutomaticDayKind(DateOnly date) =>
        HasFinishedOn(date) || Day(date).Effective.Count > 0 ? NutritionDayKind.Training : NutritionDayKind.Rest;

    private ScheduledTraining Training(
        Entry entry,
        DateOnly date,
        IReadOnlyList<ScheduleWorkoutInput> finished,
        ScheduleWorkoutInput[] others)
    {
        string name = PlanName(entry.PlanId);
        if (entry.Exception is { } exception)
        {
            return new ScheduledTraining(
                entry.PlanId,
                name,
                date,
                entry.Origin,
                exception.IsSkip ? ScheduledTrainingStatus.Skipped : ScheduledTrainingStatus.Moved,
                exception.MovedToDate,
                [],
                []);
        }

        Guid[] completed = finished.Where(workout => workout.SourcePlanId == entry.PlanId).Select(workout => workout.WorkoutId).ToArray();
        ScheduledTrainingStatus status;
        if (completed.Length > 0) status = ScheduledTrainingStatus.Done;
        else if (date >= Today) status = ScheduledTrainingStatus.Planned;
        else if (others.Length > 0) status = ScheduledTrainingStatus.InsteadOf;
        else status = ScheduledTrainingStatus.Missed;
        return new ScheduledTraining(
            entry.PlanId,
            name,
            date,
            entry.Origin,
            status,
            null,
            completed,
            status == ScheduledTrainingStatus.InsteadOf ? others.Select(workout => workout.WorkoutId).ToArray() : []);
    }

    /// <summary>A known plan that is not archived; slots with any other plan are rest days.</summary>
    public bool IsActivePlan(Guid? planId) =>
        planId is { } id && plans.TryGetValue(id, out SchedulePlanInput? plan) && !plan.IsArchived;

    private BaseSlot BaseOf(ScheduleProjectionInput active, RawSlot raw)
    {
        switch (raw.Kind)
        {
            case RawSlotKind.Slot:
                Guid? planId = active.SlotPlanIds[raw.Index];
                return IsActivePlan(planId)
                    ? new BaseSlot(ScheduleBaseKind.Training, raw.Index, null, planId)
                    : new BaseSlot(ScheduleBaseKind.Rest, raw.Index, planId, null);
            case RawSlotKind.Paused:
                return new BaseSlot(ScheduleBaseKind.Paused, null, null, null);
            default:
                return new BaseSlot(ScheduleBaseKind.None, null, null, null);
        }
    }

    private static RawSlot RawSlotOn(ScheduleProjectionInput active, DateOnly date)
    {
        int count = active.SlotPlanIds.Count;
        if (date < active.ValidFrom || count == 0) return RawSlot.None;
        if (active.Mode == TrainingScheduleMode.Weekly)
        {
            // Position 0 is Monday.
            return count == 7 ? new RawSlot(RawSlotKind.Slot, ((int)date.DayOfWeek + 6) % 7) : RawSlot.None;
        }

        if (active.AnchorDate is not { } anchor) return RawSlot.None;
        int shifted = 0;
        foreach (ScheduleShiftInput shift in active.Shifts)
        {
            if (shift.FromDate > date) continue;
            if (shift.Pauses(date)) return new RawSlot(RawSlotKind.Paused, 0);
            shifted += shift.Days;
        }
        return new RawSlot(RawSlotKind.Slot, Modulo(date.DayNumber - anchor.DayNumber - shifted, count));
    }

    /// <summary>Never negative for a positive divisor, like Dart's <c>%</c>, also before the anchor.</summary>
    private static int Modulo(int value, int divisor) => ((value % divisor) + divisor) % divisor;

    private enum RawSlotKind
    {
        None,
        Paused,
        Slot,
    }

    private readonly record struct RawSlot(RawSlotKind Kind, int Index)
    {
        public static RawSlot None => new(RawSlotKind.None, 0);
    }

    private readonly record struct BaseSlot(ScheduleBaseKind Kind, int? SlotIndex, Guid? ArchivedPlanId, Guid? BasePlan);

    private readonly record struct Entry(Guid PlanId, DateOnly Origin, ScheduleExceptionInput? Exception);
}
