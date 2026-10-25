using Gainer.Core.Mutations;

namespace Gainer.Core.Sync;

/// <summary>
/// Lowest sync protocol that understands each resource type. A client below that version cannot apply the
/// resource and must update before it may pull or write it; older types are understood by every supported client.
/// </summary>
public static class SyncResourceProtocol
{
    /// <summary>Protocol that introduced <see cref="ResourceKind.WaterIntakeDay"/>.</summary>
    public const int WaterIntakeVersion = 4;

    private static readonly Dictionary<string, int> MinimumVersions = new(StringComparer.Ordinal)
    {
        [nameof(ResourceKind.WaterIntakeDay)] = WaterIntakeVersion,
    };

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
