namespace Gainer.Core.Training;

/// <summary>Checks the shape of a training schedule against the sync contract; plan ownership is checked by the handler.</summary>
public static class TrainingScheduleValidation
{
    public const int MinimumCycleSlots = 1;
    public const int MaximumCycleSlots = 28;
    public const int WeeklySlots = 7;
    public const int MinimumShiftDays = 1;
    public const int MaximumShiftDays = 31;
    public const int MaximumShiftsAndExceptions = 1_000;

    /// <summary>Moves go a few days forward or catch up from at most a week back; 31 days in either direction is ample.</summary>
    public const int MaximumMoveDays = 31;

    public static TrainingScheduleValues Normalize(TrainingScheduleValues schedule)
    {
        ArgumentNullException.ThrowIfNull(schedule);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        IReadOnlyList<TrainingScheduleSlotValues> slots = schedule.Slots ?? [];
        IReadOnlyList<TrainingScheduleShiftValues> shifts = schedule.Shifts ?? [];
        IReadOnlyList<TrainingScheduleExceptionValues> exceptions = schedule.Exceptions ?? [];
        if (schedule.Slots is null) errors[nameof(TrainingScheduleValues.Slots)] = "The slots are missing.";
        if (schedule.Shifts is null) errors[nameof(TrainingScheduleValues.Shifts)] = "The shifts are missing.";
        if (schedule.Exceptions is null) errors[nameof(TrainingScheduleValues.Exceptions)] = "The exceptions are missing.";

        if (!TrainingScheduleModes.TryParse(schedule.Mode, out TrainingScheduleMode mode))
        {
            errors[nameof(TrainingScheduleValues.Mode)] = "The mode must be 'cycle' or 'weekly'.";
        }
        else if (mode == TrainingScheduleMode.Cycle)
        {
            ValidateCycle(schedule, slots, errors);
        }
        else
        {
            ValidateWeekly(schedule, slots, shifts, errors);
        }

        ValidateSlots(slots, errors);
        ValidateShifts(shifts, errors);
        ValidateExceptions(exceptions, errors);
        if (shifts.Count + exceptions.Count > MaximumShiftsAndExceptions)
        {
            errors[nameof(TrainingScheduleValues.Exceptions)] =
                $"Shifts and exceptions together cannot exceed {MaximumShiftsAndExceptions} entries.";
        }

        if (errors.Count > 0)
        {
            throw new TrainingScheduleValidationException(errors);
        }
        return schedule with
        {
            Slots = slots.ToArray(),
            Shifts = shifts.ToArray(),
            Exceptions = exceptions.ToArray(),
        };
    }

    private static void ValidateCycle(
        TrainingScheduleValues schedule,
        IReadOnlyList<TrainingScheduleSlotValues> slots,
        Dictionary<string, string> errors)
    {
        if (slots.Count is < MinimumCycleSlots or > MaximumCycleSlots)
        {
            errors[nameof(TrainingScheduleValues.Slots)] =
                $"A cycle must contain between {MinimumCycleSlots} and {MaximumCycleSlots} slots.";
        }
        if (schedule.AnchorDate is null)
        {
            errors[nameof(TrainingScheduleValues.AnchorDate)] = "A cycle requires an anchor date.";
        }
    }

    private static void ValidateWeekly(
        TrainingScheduleValues schedule,
        IReadOnlyList<TrainingScheduleSlotValues> slots,
        IReadOnlyList<TrainingScheduleShiftValues> shifts,
        Dictionary<string, string> errors)
    {
        if (slots.Count != WeeklySlots)
        {
            errors[nameof(TrainingScheduleValues.Slots)] = "A weekly schedule must contain exactly seven slots, Monday first.";
        }
        if (schedule.AnchorDate is not null)
        {
            errors[nameof(TrainingScheduleValues.AnchorDate)] = "A weekly schedule has no anchor date.";
        }
        if (shifts.Count > 0)
        {
            errors[nameof(TrainingScheduleValues.Shifts)] = "Only a cycle can be shifted.";
        }
    }

    private static void ValidateSlots(IReadOnlyList<TrainingScheduleSlotValues> slots, Dictionary<string, string> errors)
    {
        if (errors.ContainsKey(nameof(TrainingScheduleValues.Slots)))
        {
            return;
        }
        if (slots.Any(item => item is null || item.PlanId == Guid.Empty))
        {
            errors[nameof(TrainingScheduleValues.Slots)] = "A slot plan identifier must not be empty.";
        }
        else if (slots.All(item => item.PlanId is null))
        {
            errors[nameof(TrainingScheduleValues.Slots)] = "At least one slot must reference a plan.";
        }
    }

    private static void ValidateShifts(IReadOnlyList<TrainingScheduleShiftValues> shifts, Dictionary<string, string> errors)
    {
        if (errors.ContainsKey(nameof(TrainingScheduleValues.Shifts)))
        {
            return;
        }
        if (shifts.Any(item => item is null || item.Days is < MinimumShiftDays or > MaximumShiftDays))
        {
            errors[nameof(TrainingScheduleValues.Shifts)] =
                $"A shift must move the schedule by {MinimumShiftDays} to {MaximumShiftDays} days.";
        }
        else if (shifts.Select(item => item.FromDate).Distinct().Count() != shifts.Count)
        {
            errors[nameof(TrainingScheduleValues.Shifts)] = "At most one shift can start on each day.";
        }
    }

    private static void ValidateExceptions(
        IReadOnlyList<TrainingScheduleExceptionValues> exceptions,
        Dictionary<string, string> errors)
    {
        if (errors.ContainsKey(nameof(TrainingScheduleValues.Exceptions)))
        {
            return;
        }
        if (exceptions.Any(item => item is null || item.PlanId == Guid.Empty))
        {
            errors[nameof(TrainingScheduleValues.Exceptions)] = "An exception plan identifier must not be empty.";
        }
        else if (exceptions.Select(item => (item.Date, item.PlanId)).Distinct().Count() != exceptions.Count)
        {
            errors[nameof(TrainingScheduleValues.Exceptions)] = "Each plan can have at most one exception per day.";
        }
        else if (exceptions.Any(item => item.MovedToDate is { } target &&
                     (target == item.Date || Math.Abs(target.DayNumber - item.Date.DayNumber) > MaximumMoveDays)))
        {
            errors[nameof(TrainingScheduleValues.Exceptions)] =
                $"A moved workout must land on another day at most {MaximumMoveDays} days away.";
        }
    }
}
