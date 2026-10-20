namespace Gainer.Core.Training;

/// <summary>Fixed muscle regions of the body map; the app keeps the same list.</summary>
public static class MuscleKeys
{
    public const int MaximumPrimary = 3;
    public const int MaximumSecondary = 6;

    public static IReadOnlyList<string> Known { get; } =
    [
        "chest",
        "frontDelts",
        "sideDelts",
        "rearDelts",
        "biceps",
        "triceps",
        "forearms",
        "abs",
        "obliques",
        "lats",
        "traps",
        "lowerBack",
        "glutes",
        "quads",
        "hamstrings",
        "adductors",
        "calves",
    ];

    private static readonly HashSet<string> KnownSet = new(Known, StringComparer.Ordinal);

    public static bool IsKnown(string? key) => key is not null && KnownSet.Contains(key);

    /// <summary>
    /// Returns an error message for an invalid primary/secondary pair, or null when it is valid:
    /// known keys only, no repetitions, no key in both lists, and within the list limits.
    /// </summary>
    public static string? Validate(IReadOnlyList<string> primary, IReadOnlyList<string> secondary)
    {
        ArgumentNullException.ThrowIfNull(primary);
        ArgumentNullException.ThrowIfNull(secondary);
        if (primary.Count > MaximumPrimary)
        {
            return $"An exercise can have at most {MaximumPrimary} primary muscles.";
        }
        if (secondary.Count > MaximumSecondary)
        {
            return $"An exercise can have at most {MaximumSecondary} secondary muscles.";
        }
        if (primary.Concat(secondary).Any(key => !IsKnown(key)))
        {
            return "One or more muscles are unknown.";
        }
        if (primary.Concat(secondary).Distinct(StringComparer.Ordinal).Count() != primary.Count + secondary.Count)
        {
            return "A muscle can be listed only once per exercise.";
        }
        return null;
    }
}
