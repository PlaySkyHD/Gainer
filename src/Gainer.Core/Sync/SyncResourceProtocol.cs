using Gainer.Core.Mutations;

namespace Gainer.Core.Sync;

/// <summary>
/// Lowest sync protocol that understands each resource type. A client below that version cannot apply the
/// resource and must update before it may pull or write it. Every <see cref="ResourceKind"/> has an entry, so a new
/// type cannot reach older apps by accident; a type without an entry is treated as needing the current protocol.
/// </summary>
/// <remarks>
/// Core does not reference <c>Gainer.Contracts</c>, so the protocol numbers are repeated here. A unit test keeps
/// them equal to <c>SyncProtocol.PreviousVersion</c>, <c>TrainingContractVersion</c> and <c>CurrentVersion</c>.
/// </remarks>
public static class SyncResourceProtocol
{
    /// <summary>Oldest accepted protocol: body, check-in and nutrition types.</summary>
    public const int ProtocolTwo = 2;

    /// <summary>
    /// Rebuilt training contract. Protocol-2 apps do not know training plans and exercise categories and expect the
    /// replaced workout and exercise payloads, whose feed history the training rebuild deleted.
    /// </summary>
    public const int ProtocolThree = 3;

    /// <summary>
    /// Water intake, plus cardio sessions, training schedules and nutrition day templates, which shipped after
    /// protocol 3 without their own version.
    /// </summary>
    public const int ProtocolFour = 4;

    /// <summary>Newest protocol this server speaks.</summary>
    public const int CurrentVersion = ProtocolFour;

    private static readonly Dictionary<string, int> MinimumVersions = new(StringComparer.Ordinal)
    {
        [nameof(ResourceKind.BodyGoal)] = ProtocolTwo,
        [nameof(ResourceKind.DailyCheckIn)] = ProtocolTwo,
        [nameof(ResourceKind.NutritionDay)] = ProtocolTwo,
        [nameof(ResourceKind.ReusableMeal)] = ProtocolTwo,
        [nameof(ResourceKind.NutritionTargetSchedule)] = ProtocolTwo,
        [nameof(ResourceKind.CustomExercise)] = ProtocolThree,
        [nameof(ResourceKind.TrainingPlan)] = ProtocolThree,
        [nameof(ResourceKind.Workout)] = ProtocolThree,
        [nameof(ResourceKind.ExerciseCategory)] = ProtocolThree,
        [nameof(ResourceKind.CardioSession)] = ProtocolFour,
        [nameof(ResourceKind.TrainingSchedule)] = ProtocolFour,
        [nameof(ResourceKind.NutritionDayTemplate)] = ProtocolFour,
        [nameof(ResourceKind.WaterIntakeDay)] = ProtocolFour,
    };

    /// <summary>Resource types with an entry in the table.</summary>
    public static IReadOnlyCollection<string> KnownTypes => MinimumVersions.Keys;

    /// <summary>
    /// Gets the lowest protocol that understands <paramref name="resourceType"/>. Types without an entry fail closed
    /// and require <see cref="CurrentVersion"/>.
    /// </summary>
    public static int MinimumVersionFor(string resourceType) =>
        MinimumVersions.TryGetValue(resourceType, out int version) ? version : CurrentVersion;

    /// <summary>True when a client speaking <paramref name="protocolVersion"/> can apply <paramref name="resourceType"/>.</summary>
    public static bool Supports(int protocolVersion, string resourceType) =>
        protocolVersion >= MinimumVersionFor(resourceType);

    /// <summary>Resource types a client speaking <paramref name="protocolVersion"/> cannot apply.</summary>
    public static IReadOnlyList<string> TypesNewerThan(int protocolVersion) =>
        MinimumVersions.Where(item => item.Value > protocolVersion).Select(item => item.Key).ToArray();
}
