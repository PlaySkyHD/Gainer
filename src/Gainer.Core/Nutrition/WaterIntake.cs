using Gainer.Core.Mutations;
using Gainer.Core.Security;

namespace Gainer.Core.Nutrition;

/// <summary>Water a user drank on one local day, in whole milliliters.</summary>
public sealed class WaterIntakeDay : UserOwnedEntity
{
    public Guid Id { get; init; }
    public DateOnly LocalDate { get; init; }
    public int AmountMl { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}

public static class WaterIntakeLimits
{
    public const int MinDailyMl = 0;
    public const int MaxDailyMl = 10_000;
}

public sealed record WaterIntakeDaySnapshot(
    Guid WaterIntakeDayId,
    DateOnly LocalDate,
    int AmountMl,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.WaterIntakeDay, WaterIntakeDayId);
}

/// <summary>
/// Sets the water total of one local day; creates the day from base version 0. Quick buttons and corrections both
/// send the new total: the base version already guards against lost updates, and a total survives outbox coalescing.
/// </summary>
public sealed record SetWaterIntakeMutation : ITypedMutation<WaterIntakeDaySnapshot>
{
    private SetWaterIntakeMutation(
        MutationMetadata metadata,
        Guid waterIntakeDayId,
        DateOnly localDate,
        long baseVersion,
        int amountMl)
    {
        Metadata = metadata;
        WaterIntakeDayId = waterIntakeDayId;
        LocalDate = localDate;
        BaseVersion = baseVersion;
        AmountMl = amountMl;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.WaterIntakeDay, waterIntakeDayId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid WaterIntakeDayId { get; }
    public DateOnly LocalDate { get; }
    public long BaseVersion { get; }

    /// <summary>New total of the day in milliliters.</summary>
    public int AmountMl { get; }

    public static SetWaterIntakeMutation Create(
        MutationMetadata metadata,
        Guid waterIntakeDayId,
        DateOnly localDate,
        long baseVersion,
        int amountMl)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (waterIntakeDayId == Guid.Empty)
        {
            throw new ArgumentException("The water intake day identifier cannot be empty.", nameof(waterIntakeDayId));
        }
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        if (amountMl is < WaterIntakeLimits.MinDailyMl or > WaterIntakeLimits.MaxDailyMl)
        {
            throw Invalid(
                nameof(AmountMl),
                $"Amount must be between {WaterIntakeLimits.MinDailyMl} and {WaterIntakeLimits.MaxDailyMl} ml.");
        }
        return new SetWaterIntakeMutation(metadata, waterIntakeDayId, localDate, baseVersion, amountMl);
    }

    private static NutritionValidationException Invalid(string field, string message) =>
        new(new Dictionary<string, string>(StringComparer.Ordinal) { [field] = message });
}

public interface IWaterIntakeMutationHandler
{
    Task<WaterIntakeDaySnapshot> SetAsync(
        SetWaterIntakeMutation mutation,
        CancellationToken cancellationToken = default);
}

public sealed class WaterIntakeConflictException(string message) : Exception(message);

public sealed class WaterIntakeNotFoundException : Exception;
