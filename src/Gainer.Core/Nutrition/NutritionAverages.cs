namespace Gainer.Core.Nutrition;

/// <summary>A stored nutrition day; <paramref name="Totals"/> is null when it has no entries.</summary>
public sealed record NutritionAverageDayInput(DateOnly Date, NutritionTotals? Totals, NutritionDayKind? DayKind);

/// <summary>The kcal of a target version and of its separate rest-day target, if any.</summary>
public sealed record NutritionAverageTargetInput(
    DateOnly EffectiveFrom,
    DateOnly? EffectiveUntil,
    decimal Kilocalories,
    decimal? RestDayKilocalories);

/// <summary>One calendar day of the window; the target is set only for logged days.</summary>
public sealed record NutritionAverageDay(DateOnly Date, decimal? Kilocalories, decimal? TargetKilocalories, bool WithinTarget);

public sealed record NutritionAveragesSnapshot(
    int WindowDays,
    DateOnly From,
    DateOnly Through,
    bool IncludesToday,
    int LoggedDays,
    decimal? AverageKilocalories,
    decimal? AverageProteinGrams,
    decimal? AverageCarbohydrateGrams,
    decimal? AverageFatGrams,
    decimal? AverageFiberGrams,
    decimal? AverageSaltGrams,
    decimal? AverageTargetKilocalories,
    int DaysWithinTarget,
    int DaysWithTarget,
    IReadOnlyList<NutritionAverageDay> Days);

/// <summary>
/// Port of the app's nutrition averages (<c>NutritionAverages.compute</c> in nutrition_averages.dart); the rules are in
/// contracts/fixtures/nutrition-averages.json. Unlike the app, a day without a chosen day kind always uses the
/// training-day target: the app derives the kind from the training schedule, which only the phone projects.
/// </summary>
public static class NutritionAverages
{
    public static NutritionAveragesSnapshot Compute(
        IReadOnlyCollection<NutritionAverageDayInput> days,
        IReadOnlyCollection<NutritionAverageTargetInput> targets,
        DateOnly today,
        int windowDays)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(windowDays, 1);
        Dictionary<DateOnly, NutritionAverageDayInput> byDate = days
            .GroupBy(day => day.Date)
            .ToDictionary(group => group.Key, group => group.Last());
        bool includesToday = byDate.GetValueOrDefault(today)?.Totals is not null;
        DateOnly through = includesToday ? today : today.AddDays(-1);
        DateOnly from = through.AddDays(1 - windowDays);

        var window = new List<NutritionAverageDay>();
        var logged = new List<NutritionTotals>();
        var targetsOfLoggedDays = new List<decimal>();
        for (DateOnly date = from; date <= through; date = date.AddDays(1))
        {
            NutritionAverageDayInput? day = byDate.GetValueOrDefault(date);
            if (day?.Totals is not { } totals)
            {
                window.Add(new NutritionAverageDay(date, null, null, false));
                continue;
            }

            logged.Add(totals);
            decimal? target = TargetOn(targets, date, day.DayKind);
            if (target is { } value) targetsOfLoggedDays.Add(value);
            window.Add(new NutritionAverageDay(date, totals.Kilocalories, target, IsWithin(totals.Kilocalories, target)));
        }

        return new NutritionAveragesSnapshot(
            windowDays,
            from,
            through,
            includesToday,
            logged.Count,
            Average(logged.Select(item => (decimal?)item.Kilocalories)),
            Average(logged.Select(item => item.ProteinGrams)),
            Average(logged.Select(item => item.CarbohydrateGrams)),
            Average(logged.Select(item => item.FatGrams)),
            Average(logged.Select(item => item.FiberGrams)),
            Average(logged.Select(item => item.SaltGrams)),
            Average(targetsOfLoggedDays.Select(item => (decimal?)item)),
            window.Count(item => item.WithinTarget),
            targetsOfLoggedDays.Count,
            window);
    }

    /// <summary>The kcal target on a day: rest-day kcal when the version has one and the day is set as rest day.</summary>
    public static decimal? TargetOn(IEnumerable<NutritionAverageTargetInput> targets, DateOnly date, NutritionDayKind? dayKind)
    {
        NutritionAverageTargetInput? version = targets
            .Where(item => item.EffectiveFrom <= date && (item.EffectiveUntil is null || item.EffectiveUntil >= date))
            .OrderBy(item => item.EffectiveFrom)
            .LastOrDefault();
        if (version is null) return null;
        return dayKind == NutritionDayKind.Rest && version.RestDayKilocalories is { } rest ? rest : version.Kilocalories;
    }

    /// <summary>Within ±10 % of the day's target, inclusive.</summary>
    private static bool IsWithin(decimal kilocalories, decimal? target) =>
        target is { } value && Math.Abs(kilocalories - value) <= value * 0.10m;

    private static decimal? Average(IEnumerable<decimal?> values)
    {
        decimal[] present = values.OfType<decimal>().ToArray();
        return present.Length == 0 ? null : present.Sum() / present.Length;
    }
}
