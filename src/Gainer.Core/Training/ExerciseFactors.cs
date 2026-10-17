namespace Gainer.Core.Training;

/// <summary>Resolves the effective calculation factors of an exercise (spec "Rechenfaktoren").</summary>
public static class ExerciseFactors
{
    public const decimal MaximumBodyweightFactor = 1m;
    public const decimal MaximumWeightFactor = 10m;

    /// <summary>Own factor first, then the catalog value, then the type default.</summary>
    public static decimal BodyweightFactor(Exercise exercise) =>
        exercise.BodyweightFactor ?? DefaultBodyweightFactor(exercise.ExerciseType);

    public static decimal WeightFactor(Exercise exercise) => exercise.WeightFactor ?? 1m;

    public static void EnsureValid(decimal? bodyweightFactor, decimal? weightFactor)
    {
        if (bodyweightFactor is < 0m or > MaximumBodyweightFactor)
        {
            throw new ArgumentOutOfRangeException(nameof(bodyweightFactor), bodyweightFactor, "Bodyweight factor must be between 0 and 1.");
        }

        if (weightFactor is <= 0m or > MaximumWeightFactor)
        {
            throw new ArgumentOutOfRangeException(nameof(weightFactor), weightFactor, "Weight factor must be greater than 0 and at most 10.");
        }
    }

    private static decimal DefaultBodyweightFactor(ExerciseType type) => type switch
    {
        ExerciseType.BodyweightLoaded or ExerciseType.BodyweightOnly or ExerciseType.Assisted => 1m,
        _ => 0m,
    };
}
