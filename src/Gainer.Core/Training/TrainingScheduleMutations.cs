using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

/// <summary>A slot of the rhythm; the position is its index. A null plan is a rest day.</summary>
public sealed record TrainingScheduleSlotValues(Guid? PlanId);

public sealed record TrainingScheduleShiftValues(DateOnly FromDate, int Days);

/// <summary>A null target date skips the planned workout.</summary>
public sealed record TrainingScheduleExceptionValues(DateOnly Date, Guid PlanId, DateOnly? MovedToDate);

/// <summary>Complete state of a training schedule; every mutation carries all of it.</summary>
public sealed record TrainingScheduleValues(
    Guid ScheduleId,
    string Mode,
    DateOnly? AnchorDate,
    DateOnly ValidFrom,
    IReadOnlyList<TrainingScheduleSlotValues> Slots,
    IReadOnlyList<TrainingScheduleShiftValues> Shifts,
    IReadOnlyList<TrainingScheduleExceptionValues> Exceptions);

public sealed record SaveTrainingScheduleMutation : ITypedMutation
{
    private SaveTrainingScheduleMutation(MutationMetadata metadata, long baseVersion, TrainingScheduleValues schedule)
    {
        Metadata = metadata;
        BaseVersion = baseVersion;
        Schedule = schedule;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.TrainingSchedule, schedule.ScheduleId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }

    /// <summary>Zero creates the schedule; a positive value replaces it.</summary>
    public long BaseVersion { get; }
    public TrainingScheduleValues Schedule { get; }

    public static SaveTrainingScheduleMutation Create(
        MutationMetadata metadata,
        long baseVersion,
        TrainingScheduleValues schedule)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(schedule);
        if (schedule.ScheduleId == Guid.Empty)
        {
            throw new ArgumentException("The schedule identifier cannot be empty.", nameof(schedule));
        }
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        return new(metadata, baseVersion, schedule);
    }
}

public sealed record DeleteTrainingScheduleMutation : ITypedMutation
{
    private DeleteTrainingScheduleMutation(MutationMetadata metadata, Guid scheduleId, long baseVersion)
    {
        Metadata = metadata;
        ScheduleId = scheduleId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.TrainingSchedule, scheduleId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid ScheduleId { get; }
    public long BaseVersion { get; }

    public static DeleteTrainingScheduleMutation Create(MutationMetadata metadata, Guid scheduleId, long baseVersion)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (scheduleId == Guid.Empty)
        {
            throw new ArgumentException("The schedule identifier cannot be empty.", nameof(scheduleId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, scheduleId, baseVersion);
    }
}

/// <summary>Pull snapshot: the schedule fields of the save payload plus server metadata.</summary>
public sealed record TrainingScheduleSnapshot(
    Guid ScheduleId,
    string Mode,
    DateOnly? AnchorDate,
    DateOnly ValidFrom,
    IReadOnlyList<TrainingScheduleSlotValues> Slots,
    IReadOnlyList<TrainingScheduleShiftValues> Shifts,
    IReadOnlyList<TrainingScheduleExceptionValues> Exceptions,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.TrainingSchedule, ScheduleId);
}

public interface ITrainingScheduleMutationHandler
{
    Task<TrainingScheduleSnapshot> SaveAsync(SaveTrainingScheduleMutation mutation, CancellationToken cancellationToken = default);
    Task<long> DeleteAsync(DeleteTrainingScheduleMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class TrainingScheduleValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The training schedule is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class TrainingScheduleConflictException(string message) : Exception(message);

public sealed class TrainingScheduleNotFoundException : Exception;
