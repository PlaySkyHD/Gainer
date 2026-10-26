using Gainer.Core.Mutations;

namespace Gainer.Core.Sync;

/// <summary>
/// Lowest sync protocol that understands each resource type. A client below that version cannot apply the
/// resource and must update before it may pull or write it. Every <see cref="ResourceKind"/> has an entry, so a new
/// type cannot reach older apps by accident.
/// </summary>
public static class SyncResourceProtocol
{
    /// <summary>Oldest accepted protocol; its types are understood by every supported client.</summary>
    public const int BaseVersion = 2;

    /// <summary>
    /// Protocol that introduced <see cref="ResourceKind.WaterIntakeDay"/>. It also guards the cardio, training
    /// schedule and nutrition day template types, which shipped after protocol 3 without their own version.
    /// </summary>
    public const int WaterIntakeVersion = 4;

    private static readonly Dictionary<string, int> MinimumVersions = new(StringComparer.Ordinal)
    {
        [nameof(ResourceKind.BodyGoal)] = BaseVersion,
        [nameof(ResourceKind.DailyCheckIn)] = BaseVersion,
        [nameof(ResourceKind.CustomExercise)] = BaseVersion,
        [nameof(ResourceKind.TrainingPlan)] = BaseVersion,
        [nameof(ResourceKind.Workout)] = BaseVersion,
        [nameof(ResourceKind.NutritionDay)] = BaseVersion,
        [nameof(ResourceKind.ReusableMeal)] = BaseVersion,
        [nameof(ResourceKind.NutritionTargetSchedule)] = BaseVersion,
        [nameof(ResourceKind.ExerciseCategory)] = BaseVersion,
        [nameof(ResourceKind.CardioSession)] = WaterIntakeVersion,
        [nameof(ResourceKind.TrainingSchedule)] = WaterIntakeVersion,
        [nameof(ResourceKind.NutritionDayTemplate)] = WaterIntakeVersion,
        [nameof(ResourceKind.WaterIntakeDay)] = WaterIntakeVersion,
    };

    /// <summary>Resource types with an entry in the table.</summary>
    public static IReadOnlyCollection<string> KnownTypes => MinimumVersions.Keys;

    /// <summary>Gets the lowest protocol that understands <paramref name="resourceType"/>.</summary>
    public static int MinimumVersionFor(string resourceType) =>
        MinimumVersions.TryGetValue(resourceType, out int version) ? version : 0;

    /// <summary>True when a client speaking <paramref name="protocolVersion"/> can apply <paramref name="resourceType"/>.</summary>
    public static bool Supports(int protocolVersion, string resourceType) =>
        protocolVersion >= MinimumVersionFor(resourceType);

    /// <summary>Resource types a client speaking <paramref name="protocolVersion"/> cannot apply.</summary>
    public static IReadOnlyList<string> TypesNewerThan(int protocolVersion) =>
        MinimumVersions.Where(item => item.Value > protocolVersion).Select(item => item.Key).ToArray();
}
