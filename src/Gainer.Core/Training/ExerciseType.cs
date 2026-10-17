namespace Gainer.Core.Training;

/// <summary>Determines which inputs a set of an exercise requires and how its load is evaluated.</summary>
public enum ExerciseType
{
    Strength,
    BodyweightLoaded,
    BodyweightOnly,
    Assisted,
}

/// <summary>Maps exercise types to their persisted, case-insensitive storage values.</summary>
public static class ExerciseTypes
{
    public static string ToStorageValue(ExerciseType value) => value switch
    {
        ExerciseType.Strength => "strength",
        ExerciseType.BodyweightLoaded => "bodyweightLoaded",
        ExerciseType.BodyweightOnly => "bodyweightOnly",
        ExerciseType.Assisted => "assisted",
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, "Unknown exercise type."),
    };

    /// <summary>Parses a storage value; unknown or empty values are rejected instead of falling back to a default.</summary>
    public static ExerciseType Parse(string? value) =>
        TryParse(value, out ExerciseType type) ? type : throw new UnknownExerciseTypeException(value);

    public static bool TryParse(string? value, out ExerciseType type)
    {
        ExerciseType[] matches = Enum.GetValues<ExerciseType>()
            .Where(candidate => string.Equals(value, ToStorageValue(candidate), StringComparison.OrdinalIgnoreCase))
            .ToArray();
        type = matches.Length > 0 ? matches[0] : default;
        return matches.Length > 0;
    }
}
