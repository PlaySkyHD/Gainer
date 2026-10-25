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
    public const int MinAddedMl = 1;
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

/// <summary>How a water mutation changes the stored day amount.</summary>
public enum WaterIntakeChange
{
    /// <summary>Adds the amount to the stored total (quick buttons).</summary>
    Add = 1,

    /// <summary>Replaces the stored total (correction and undo).</summary>
    Set = 2,
}

/// <summary>Adds to or sets the water amount of one local day; creates the day from base version 0.</summary>
public sealed record ChangeWaterIntakeMutation : ITypedMutation<WaterIntakeDaySnapshot>
{
    private ChangeWaterIntakeMutation(
        MutationMetadata metadata,
        Guid waterIntakeDayId,
        DateOnly localDate,
        long baseVersion,
        WaterIntakeChange change,
        int amountMl)
    {
        Metadata = metadata;
        WaterIntakeDayId = waterIntakeDayId;
        LocalDate = localDate;
        BaseVersion = baseVersion;
        Change = change;
        AmountMl = amountMl;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.WaterIntakeDay, waterIntakeDayId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid WaterIntakeDayId { get; }
    public DateOnly LocalDate { get; }
    public long BaseVersion { get; }
    public WaterIntakeChange Change { get; }

    /// <summary>Added milliliters for <see cref="WaterIntakeChange.Add"/>, the new total for <see cref="WaterIntakeChange.Set"/>.</summary>
    public int AmountMl { get; }

    public static ChangeWaterIntakeMutation Create(
        MutationMetadata metadata,
        Guid waterIntakeDayId,
        DateOnly localDate,
        long baseVersion,
        WaterIntakeChange change,
        int amountMl)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (waterIntakeDayId == Guid.Empty)
        {
            throw new ArgumentException("The water intake day identifier cannot be empty.", nameof(waterIntakeDayId));
        }
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        if (!Enum.IsDefined(change)) throw new ArgumentOutOfRangeException(nameof(change));
        int minimum = change == WaterIntakeChange.Add ? WaterIntakeLimits.MinAddedMl : WaterIntakeLimits.MinDailyMl;
        if (amountMl < minimum || amountMl > WaterIntakeLimits.MaxDailyMl)
        {
            throw InvalidAmount($"Amount must be between {minimum} and {WaterIntakeLimits.MaxDailyMl} ml.");
        }
        return new ChangeWaterIntakeMutation(metadata, waterIntakeDayId, localDate, baseVersion, change, amountMl);
    }

    /// <summary>Total after applying this change to <paramref name="currentMl"/>; rejects totals above the daily limit.</summary>
    public int ApplyTo(int currentMl)
    {
        long total = Change == WaterIntakeChange.Add ? (long)currentMl + AmountMl : AmountMl;
        return total <= WaterIntakeLimits.MaxDailyMl
            ? (int)total
            : throw InvalidAmount($"The daily total cannot exceed {WaterIntakeLimits.MaxDailyMl} ml.");
    }

    private static NutritionValidationException InvalidAmount(string message) =>
        new(new Dictionary<string, string>(StringComparer.Ordinal) { [nameof(AmountMl)] = message });
}

public interface IWaterIntakeMutationHandler
{
    Task<WaterIntakeDaySnapshot> ChangeAsync(
        ChangeWaterIntakeMutation mutation,
        CancellationToken cancellationToken = default);
}

public sealed class WaterIntakeConflictException(string message) : Exception(message);

public sealed class WaterIntakeNotFoundException : Exception;
