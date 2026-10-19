using Gainer.Core.Mutations;

namespace Gainer.Core.BodyTracking;

public sealed record DailyCheckInValues(
    decimal WeightKg,
    decimal? CaloriesKcal = null,
    decimal? ProteinGrams = null,
    decimal? CarbohydrateGrams = null,
    decimal? FatGrams = null,
    int? Steps = null,
    int? SleepMinutes = null,
    int? RestingHeartRateBpm = null,
    int? RestingHrvMs = null);

public sealed record CreateDailyCheckInMutation : ITypedMutation<DailyCheckInSnapshot>
{
    private CreateDailyCheckInMutation(
        MutationMetadata metadata,
        Guid checkInId,
        DateOnly localDate,
        DailyCheckInValues values)
    {
        Metadata = metadata;
        CheckInId = checkInId;
        LocalDate = localDate;
        Values = values;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.DailyCheckIn, checkInId),
            0));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid CheckInId { get; }
    public DateOnly LocalDate { get; }
    public DailyCheckInValues Values { get; }

    public static CreateDailyCheckInMutation Create(
        MutationMetadata metadata,
        Guid checkInId,
        DateOnly localDate,
        DailyCheckInValues values)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(values);
        return checkInId != Guid.Empty
            ? new CreateDailyCheckInMutation(metadata, checkInId, localDate, values)
            : throw new ArgumentException("The check-in identifier cannot be empty.", nameof(checkInId));
    }
}

public sealed record CorrectDailyCheckInMutation : ITypedMutation<DailyCheckInSnapshot>
{
    private CorrectDailyCheckInMutation(
        MutationMetadata metadata,
        Guid checkInId,
        long baseVersion,
        DailyCheckInValues values)
    {
        Metadata = metadata;
        CheckInId = checkInId;
        BaseVersion = baseVersion;
        Values = values;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.DailyCheckIn, checkInId),
            baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid CheckInId { get; }
    public long BaseVersion { get; }
    public DailyCheckInValues Values { get; }

    public static CorrectDailyCheckInMutation Create(
        MutationMetadata metadata,
        Guid checkInId,
        long baseVersion,
        DailyCheckInValues values)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(values);
        if (checkInId == Guid.Empty)
        {
            throw new ArgumentException("The check-in identifier cannot be empty.", nameof(checkInId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new CorrectDailyCheckInMutation(metadata, checkInId, baseVersion, values);
    }
}

public sealed record DailyCheckInSnapshot(
    Guid CheckInId,
    DateOnly LocalDate,
    DailyCheckInValues Values,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.DailyCheckIn, CheckInId);
}

public interface IDailyCheckInMutationHandler
{
    Task<DailyCheckInSnapshot> CreateAsync(
        CreateDailyCheckInMutation mutation,
        CancellationToken cancellationToken = default);

    Task<DailyCheckInSnapshot> CorrectAsync(
        CorrectDailyCheckInMutation mutation,
        CancellationToken cancellationToken = default);
}

public sealed class DailyCheckInValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The daily check-in is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class DailyCheckInConflictException(string message) : Exception(message);

public sealed class DailyCheckInNotFoundException : Exception;
