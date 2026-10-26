namespace Gainer.Core.BodyTracking;

/// <summary>
/// Plausible upper bounds for body tracking values. They stay below the storage ranges, so an implausible value is a
/// validation error instead of a numeric overflow in the database.
/// </summary>
public static class BodyTrackingLimits
{
    public const decimal MaxWeightKg = 1_000m;
    public const decimal MaxCheckInKilocalories = 100_000m;
    public const decimal MaxCheckInMacroGrams = 10_000m;
}
