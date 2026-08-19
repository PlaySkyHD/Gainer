namespace Gainer.Core.Insights;

public static class InsightAlgorithmVersions
{
    public const string WeightAverage = "weight-average-v1";
    public const string WeightTrend = "weight-trend-ols-v1";
    public const string NutritionAverage = "nutrition-average-v2-diary-priority";
    public const string TrainingVolume = "training-volume-v1";
    public const string EstimatedOneRepMax = "e1rm-epley-v1";
}

public sealed record WeightPoint(DateOnly Date, decimal WeightKg);

public sealed record NutritionPoint(
    DateOnly Date,
    decimal? CaloriesKcal,
    decimal? ProteinGrams,
    decimal? CarbohydrateGrams,
    decimal? FatGrams,
    string Source = NutritionSources.LegacyCheckIn);

public static class NutritionSources
{
    public const string MealDiary = "meal-diary";
    public const string LegacyCheckIn = "legacy-check-in";
}

public sealed record MetricAverage(decimal? Value, int ObservedDays);

public sealed record WeightInsights(
    string AverageAlgorithmVersion,
    string TrendAlgorithmVersion,
    string Unit,
    DateOnly From,
    DateOnly Through,
    int ExpectedDays,
    int ObservedDays,
    decimal Coverage,
    decimal? AverageKg,
    decimal? TrendKgPerWeek);

public sealed record NutritionInsights(
    string AlgorithmVersion,
    DateOnly From,
    DateOnly Through,
    int ExpectedDays,
    int ObservedDays,
    decimal Coverage,
    int MealDiaryDays,
    int LegacyCheckInDays,
    MetricAverage CaloriesKcal,
    MetricAverage ProteinGrams,
    MetricAverage CarbohydrateGrams,
    MetricAverage FatGrams);

public sealed record SetPerformance(
    Guid WorkoutId,
    Guid ExerciseId,
    DateTime CompletedAtUtc,
    decimal? WeightKg,
    int? Repetitions,
    bool IsCompleted);

public sealed record BestSet(
    Guid WorkoutId,
    Guid ExerciseId,
    DateTime CompletedAtUtc,
    decimal WeightKg,
    int Repetitions,
    decimal EstimatedOneRepMaxKg);

public sealed record TrainingInsights(
    string VolumeAlgorithmVersion,
    string EstimatedOneRepMaxAlgorithmVersion,
    string VolumeUnit,
    int WorkoutCount,
    decimal VolumeKgRepetitions,
    BestSet? BestSet);

public static class InsightAlgorithms
{
    public static WeightInsights Weight(
        IReadOnlyCollection<WeightPoint> source,
        DateOnly from,
        DateOnly through)
    {
        int expectedDays = PeriodDays(from, through);
        WeightPoint[] points = source
            .Where(item => item.Date >= from && item.Date <= through && item.WeightKg > 0)
            .GroupBy(item => item.Date)
            .Select(group => group.OrderByDescending(item => item.WeightKg).First())
            .OrderBy(item => item.Date)
            .ToArray();
        decimal? average = points.Length == 0
            ? null
            : Round(points.Average(item => item.WeightKg));
        decimal? trend = points.Length < 3 ? null : Round(OlsSlopePerDay(points) * 7m);
        return new WeightInsights(
            InsightAlgorithmVersions.WeightAverage,
            InsightAlgorithmVersions.WeightTrend,
            "kg",
            from,
            through,
            expectedDays,
            points.Length,
            Coverage(points.Length, expectedDays),
            average,
            trend);
    }

    public static NutritionInsights Nutrition(
        IReadOnlyCollection<NutritionPoint> source,
        DateOnly from,
        DateOnly through)
    {
        int expectedDays = PeriodDays(from, through);
        NutritionPoint[] points = source
            .Where(item => item.Date >= from && item.Date <= through)
            .GroupBy(item => item.Date)
            .Select(group => group.Last())
            .OrderBy(item => item.Date)
            .ToArray();
        int observedDays = points.Count(item => item.CaloriesKcal is not null || item.ProteinGrams is not null ||
            item.CarbohydrateGrams is not null || item.FatGrams is not null);
        return new NutritionInsights(
            InsightAlgorithmVersions.NutritionAverage,
            from,
            through,
            expectedDays,
            observedDays,
            Coverage(observedDays, expectedDays),
            points.Count(item => item.Source == NutritionSources.MealDiary),
            points.Count(item => item.Source == NutritionSources.LegacyCheckIn &&
                (item.CaloriesKcal is not null || item.ProteinGrams is not null ||
                 item.CarbohydrateGrams is not null || item.FatGrams is not null)),
            Average(points.Select(item => item.CaloriesKcal)),
            Average(points.Select(item => item.ProteinGrams)),
            Average(points.Select(item => item.CarbohydrateGrams)),
            Average(points.Select(item => item.FatGrams)));
    }

    public static TrainingInsights Training(
        IReadOnlyCollection<SetPerformance> sets,
        IReadOnlyCollection<Guid> completedWorkoutIds)
    {
        SetPerformance[] valid = sets.Where(item => item.IsCompleted &&
            item.WeightKg is > 0 && item.Repetitions is > 0).ToArray();
        decimal volume = Round(valid.Sum(item => item.WeightKg!.Value * item.Repetitions!.Value));
        BestSet? best = valid
            .Where(item => item.Repetitions is >= 1 and <= 12)
            .Select(item => new BestSet(
                item.WorkoutId,
                item.ExerciseId,
                item.CompletedAtUtc,
                item.WeightKg!.Value,
                item.Repetitions!.Value,
                Round(Epley(item.WeightKg.Value, item.Repetitions.Value))))
            .OrderByDescending(item => item.EstimatedOneRepMaxKg)
            .ThenByDescending(item => item.WeightKg)
            .ThenByDescending(item => item.Repetitions)
            .ThenByDescending(item => item.CompletedAtUtc)
            .ThenBy(item => item.WorkoutId)
            .FirstOrDefault();
        return new TrainingInsights(
            InsightAlgorithmVersions.TrainingVolume,
            InsightAlgorithmVersions.EstimatedOneRepMax,
            "kg·repetitions",
            completedWorkoutIds.Distinct().Count(),
            volume,
            best);
    }

    public static decimal Epley(decimal weightKg, int repetitions)
    {
        if (weightKg <= 0) throw new ArgumentOutOfRangeException(nameof(weightKg));
        if (repetitions is < 1 or > 12) throw new ArgumentOutOfRangeException(nameof(repetitions));
        return weightKg * (1m + repetitions / 30m);
    }

    private static decimal OlsSlopePerDay(IReadOnlyList<WeightPoint> points)
    {
        DateOnly origin = points[0].Date;
        decimal averageX = points.Average(item => (decimal)item.Date.DayNumber - origin.DayNumber);
        decimal averageY = points.Average(item => item.WeightKg);
        decimal numerator = points.Sum(item =>
        {
            decimal x = item.Date.DayNumber - origin.DayNumber;
            return (x - averageX) * (item.WeightKg - averageY);
        });
        decimal denominator = points.Sum(item =>
        {
            decimal x = item.Date.DayNumber - origin.DayNumber;
            return (x - averageX) * (x - averageX);
        });
        return denominator == 0 ? 0 : numerator / denominator;
    }

    private static MetricAverage Average(IEnumerable<decimal?> source)
    {
        decimal[] values = source.Where(item => item is not null).Select(item => item!.Value).ToArray();
        return new MetricAverage(values.Length == 0 ? null : Round(values.Average()), values.Length);
    }

    private static int PeriodDays(DateOnly from, DateOnly through) => through >= from
        ? through.DayNumber - from.DayNumber + 1
        : throw new ArgumentOutOfRangeException(nameof(through));

    private static decimal Coverage(int observedDays, int expectedDays) =>
        decimal.Round((decimal)observedDays / expectedDays, 4, MidpointRounding.AwayFromZero);

    private static decimal Round(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);
}
