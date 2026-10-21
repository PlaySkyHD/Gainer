using Gainer.Core.Security;

namespace Gainer.Core.Training;

/// <summary>
/// Date-bound training rhythm of a user; at most one live schedule exists per user. A deleted schedule stays as a
/// tombstone row without children so that saving the same id from its tombstone version can recreate it.
/// </summary>
public sealed class TrainingSchedule : UserOwnedEntity
{
    public Guid Id { get; init; }
    public TrainingScheduleMode Mode { get; set; }

    /// <summary>Cycle only: the day on which slot 0 lies before any shift; null for weekly schedules.</summary>
    public DateOnly? AnchorDate { get; set; }

    /// <summary>Day of the last change to mode or slots; nothing is planned before it.</summary>
    public DateOnly ValidFrom { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
    public DateTime? DeletedAtUtc { get; set; }
}

/// <summary>One day of the rhythm; a missing plan is a rest day. Weekly position 0 is Monday.</summary>
public sealed class TrainingScheduleSlot : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid ScheduleId { get; init; }
    public int Position { get; init; }
    public Guid? PlanId { get; init; }
}

/// <summary>Cycle only: from <see cref="FromDate"/> on, the whole rhythm lies <see cref="Days"/> days later.</summary>
public sealed class TrainingScheduleShift : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid ScheduleId { get; init; }
    public int Position { get; init; }
    public DateOnly FromDate { get; init; }
    public int Days { get; init; }
}

/// <summary>Moves (or, without a target date, skips) the planned workout of one plan on one day.</summary>
public sealed class TrainingScheduleException : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid ScheduleId { get; init; }
    public int Position { get; init; }
    public DateOnly Date { get; init; }
    public Guid PlanId { get; init; }
    public DateOnly? MovedToDate { get; init; }
}

public enum TrainingScheduleMode
{
    Cycle,
    Weekly,
}

/// <summary>Maps schedule modes to their wire and storage values.</summary>
public static class TrainingScheduleModes
{
    public const string Cycle = "cycle";
    public const string Weekly = "weekly";

    public static string ToWireValue(TrainingScheduleMode mode) => mode switch
    {
        TrainingScheduleMode.Cycle => Cycle,
        TrainingScheduleMode.Weekly => Weekly,
        _ => throw new ArgumentOutOfRangeException(nameof(mode)),
    };

    public static bool TryParse(string? value, out TrainingScheduleMode mode)
    {
        switch (value)
        {
            case Cycle:
                mode = TrainingScheduleMode.Cycle;
                return true;
            case Weekly:
                mode = TrainingScheduleMode.Weekly;
                return true;
            default:
                mode = default;
                return false;
        }
    }

    public static TrainingScheduleMode Parse(string value) =>
        TryParse(value, out TrainingScheduleMode mode)
            ? mode
            : throw new ArgumentOutOfRangeException(nameof(value), value, "Unknown training schedule mode.");
}
