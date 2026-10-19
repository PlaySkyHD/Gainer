using Gainer.Core.Security;

namespace Gainer.Core.BodyTracking;

/// <summary>A user's daily body and optional nutrition/activity values in canonical units.</summary>
public sealed class DailyCheckIn : UserOwnedEntity
{
    public Guid Id { get; init; }

    public DateOnly LocalDate { get; init; }

    public decimal WeightKg { get; set; }

    public decimal? CaloriesKcal { get; set; }

    public decimal? ProteinGrams { get; set; }

    public decimal? CarbohydrateGrams { get; set; }

    public decimal? FatGrams { get; set; }

    public int? Steps { get; set; }

    public int? SleepMinutes { get; set; }

    public int? RestingHeartRateBpm { get; set; }

    public int? RestingHrvMs { get; set; }

    public DateTime CreatedAtUtc { get; init; }

    public DateTime UpdatedAtUtc { get; set; }

    public long Version { get; set; }
}
