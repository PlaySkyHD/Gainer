using System.ComponentModel;
using Gainer.Core.Insights;
using Gainer.Core.Nutrition;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace Gainer.Api.Mcp;

/// <summary>Logged nutrition days, nutrition targets and saved meals.</summary>
[McpServerToolType]
public sealed class GainerNutritionTools(
    INutritionQueries nutrition,
    ISmartNutritionQueries smartNutrition,
    IWaterIntakeQueries water,
    INutritionDayTemplateQueries dayTemplates,
    TimeProvider timeProvider)
{
    private const int MaximumNutritionDays = 31;
    private const int MaximumWaterDays = 366;

    [McpServerTool(Name = "get_nutrition_days", Title = "Ernährungstage", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("Logged nutrition per local day: every entry (meal, product, brand, grams, pieces, kcal and macros), " +
        "the day totals, the day type (training or rest day, if set) and the nutrition target in effect that day. " +
        "Days without entries have empty entries and zero totals. Defaults to today; at most 31 days.")]
    public async Task<NutritionDaysResult> GetNutritionDays(
        [Description("First local day (YYYY-MM-DD); default through.")] DateOnly? from = null,
        [Description("Last local day (YYYY-MM-DD); default today.")] DateOnly? through = null,
        CancellationToken cancellationToken = default)
    {
        (DateOnly start, DateOnly end) = McpDates.Range(timeProvider, from, through, 1, MaximumNutritionDays);
        Dictionary<DateOnly, NutritionDaySnapshot> logged = (await nutrition.GetDaysAsync(start, end, cancellationToken))
            .ToDictionary(day => day.LocalDate);
        IReadOnlyList<NutritionTargetVersionDraft> versions =
            (await smartNutrition.GetNutritionTargetScheduleAsync(cancellationToken))?.Versions ?? [];
        var days = new List<NutritionDayResult>();
        for (DateOnly day = start; day <= end; day = day.AddDays(1))
        {
            NutritionDaySnapshot? log = logged.GetValueOrDefault(day);
            NutritionTargetVersionDraft? target = EffectiveOn(versions, day);
            days.Add(new NutritionDayResult(
                day,
                log?.DayKind,
                log?.Totals ?? NutritionTotals.Empty,
                (log?.Entries ?? []).Select(Entry).ToList(),
                target is null ? null : Target(target)));
        }

        return new NutritionDaysResult(days);
    }

    [McpServerTool(Name = "get_nutrition_averages", Title = "Ernährungsdurchschnitt", ReadOnly = true,
        Idempotent = true, OpenWorld = false, UseStructuredContent = true)]
    [Description("The app's nutrition averages for the last 7 or 30 local days: the window ends today when today " +
        "has entries, otherwise yesterday, so an unstarted day does not lower the averages. Averages per logged day " +
        "(days with entries; empty days do not count) of kcal and of protein, carbohydrates, fat, fiber and salt in " +
        "grams (each over the logged days that have a value), how many logged days were within ±10 % of that day's " +
        "kcal target (inclusive) out of the logged days with a target, the average target, and the kcal per day " +
        "(omitted for days without entries). The target of a day is the target version in effect; its rest-day " +
        "target applies only when the day is explicitly set as rest day. Unlike the app, days without a chosen day " +
        "type always use the training-day target, because the automatic day type from the training schedule is " +
        "only computed on the phone.")]
    public async Task<NutritionAveragesResult> GetNutritionAverages(
        [Description("Window length in days: 7 or 30.")] int days = 7,
        CancellationToken cancellationToken = default)
    {
        if (days is not (7 or 30))
        {
            throw new McpException("days must be 7 or 30.");
        }

        DateOnly today = McpDates.Today(timeProvider);
        NutritionAverageDayInput[] logged = (await nutrition.GetDaysAsync(today.AddDays(-days), today, cancellationToken))
            .Select(day => new NutritionAverageDayInput(day.LocalDate, day.Entries.Count > 0 ? day.Totals : null, day.DayKind))
            .ToArray();
        NutritionAverageTargetInput[] targets =
            ((await smartNutrition.GetNutritionTargetScheduleAsync(cancellationToken))?.Versions ?? [])
            .Select(version => new NutritionAverageTargetInput(
                version.EffectiveFrom, version.EffectiveUntil, version.Kilocalories, version.RestDay?.Kilocalories))
            .ToArray();
        NutritionAveragesSnapshot averages = NutritionAverages.Compute(logged, targets, today, days);
        return new NutritionAveragesResult(
            averages.WindowDays,
            averages.From,
            averages.Through,
            averages.IncludesToday,
            averages.LoggedDays,
            Round(averages.AverageKilocalories),
            Round(averages.AverageProteinGrams),
            Round(averages.AverageCarbohydrateGrams),
            Round(averages.AverageFatGrams),
            Round(averages.AverageFiberGrams),
            Round(averages.AverageSaltGrams),
            Round(averages.AverageTargetKilocalories),
            averages.DaysWithinTarget,
            averages.DaysWithTarget,
            averages.Days
                .Select(day => new NutritionAverageDayResult(day.Date, Round(day.Kilocalories), Round(day.TargetKilocalories),
                    day.Kilocalories is null ? null : day.WithinTarget))
                .ToList());
    }

    [McpServerTool(Name = "get_nutrition_targets", Title = "Ernährungsziele", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("All versions of the nutrition target schedule, oldest first: kcal, protein, carbohydrates and fat " +
        "in grams (and percent when entered so), fiber, salt, the separate rest-day target and the dates each version " +
        "applies.")]
    public async Task<NutritionTargetsResult> GetNutritionTargets(CancellationToken cancellationToken = default) =>
        new(((await smartNutrition.GetNutritionTargetScheduleAsync(cancellationToken))?.Versions ?? [])
            .OrderBy(version => version.EffectiveFrom)
            .Select(Target)
            .ToList());

    [McpServerTool(Name = "list_saved_meals", Title = "Gespeicherte Gerichte", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("Saved (reusable) meals with their components, standard portion and nutrition per component.")]
    public async Task<SavedMealsResult> ListSavedMeals(
        [Description("Include archived meals.")] bool includeArchived = false,
        CancellationToken cancellationToken = default) =>
        new((await smartNutrition.GetReusableMealsAsync(includeArchived, cancellationToken))
            .Select(meal => new SavedMealResult(
                meal.Name,
                meal.Description,
                meal.StandardPortion,
                meal.Status == ReusableMealStatus.Archived,
                meal.Components
                    .OrderBy(component => component.Position)
                    .Select(component => new SavedMealComponentResult(
                        component.Name, component.Brand, component.AmountGrams, component.Totals))
                    .ToList()))
            .ToList());

    [McpServerTool(Name = "get_water", Title = "Wasser", ReadOnly = true, Idempotent = true, OpenWorld = false,
        UseStructuredContent = true)]
    [Description("Water drunk per local day in milliliters, oldest first; only days with a stored value are listed. " +
        "Defaults to today; at most 366 days. The daily water goal is stored only on the phone and is not available.")]
    public async Task<WaterResult> GetWater(
        [Description("First local day (YYYY-MM-DD); default through.")] DateOnly? from = null,
        [Description("Last local day (YYYY-MM-DD); default today.")] DateOnly? through = null,
        CancellationToken cancellationToken = default)
    {
        (DateOnly start, DateOnly end) = McpDates.Range(timeProvider, from, through, 1, MaximumWaterDays);
        return new WaterResult(start, end, (await water.GetDaysAsync(start, end, cancellationToken))
            .Select(day => new WaterDayResult(day.LocalDate, day.AmountMl))
            .ToList());
    }

    [McpServerTool(Name = "list_day_templates", Title = "Tagesvorlagen", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("Nutrition day templates (saved full days that can be applied to a day), by name: day type the " +
        "template is meant for (training or rest day, if set), the entries (meal, product, brand, grams, pieces, " +
        "kcal and macros) and the template totals.")]
    public async Task<DayTemplatesResult> ListDayTemplates(CancellationToken cancellationToken = default) =>
        new((await dayTemplates.ListAsync(cancellationToken))
            .Select(template => new DayTemplateResult(
                template.Name,
                template.DayKind,
                template.Totals,
                template.Entries.Select(Entry).ToList()))
            .ToList());

    /// <summary>The version in effect on a day: the latest start on or before it, still running then.</summary>
    private static NutritionTargetVersionDraft? EffectiveOn(IReadOnlyList<NutritionTargetVersionDraft> versions, DateOnly day) =>
        versions
            .Where(version => version.EffectiveFrom <= day && (version.EffectiveUntil is null || version.EffectiveUntil >= day))
            .OrderByDescending(version => version.EffectiveFrom)
            .FirstOrDefault();

    private static decimal? Round(decimal? value) => TrainingStatistics.RoundForOutput(value);

    private static NutritionEntryResult Entry(NutritionEntrySnapshot entry) => new(
        entry.Meal,
        entry.ProductName,
        entry.Brand,
        entry.AmountGrams,
        entry.Portion?.PieceCount,
        entry.Totals);

    private static NutritionTargetResult Target(NutritionTargetVersionDraft target) => new(
        target.Name,
        target.Category,
        target.EffectiveFrom,
        target.EffectiveUntil,
        target.Kilocalories,
        target.ProteinGrams,
        target.CarbohydrateGrams,
        target.FatGrams,
        target.FiberGrams,
        target.SaltGrams,
        target.RestDay is { } rest
            ? new RestDayTargetResult(rest.Kilocalories, rest.ProteinGrams, rest.CarbohydrateGrams, rest.FatGrams)
            : null);
}

public sealed record NutritionDaysResult(IReadOnlyList<NutritionDayResult> Days);

public sealed record NutritionDayResult(
    DateOnly Date,
    NutritionDayKind? DayKind,
    NutritionTotals Totals,
    IReadOnlyList<NutritionEntryResult> Entries,
    NutritionTargetResult? Target);

public sealed record NutritionEntryResult(
    MealType Meal,
    string Product,
    string? Brand,
    decimal Grams,
    decimal? Pieces,
    NutritionTotals Nutrition);

public sealed record NutritionAveragesResult(
    int Days,
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
    IReadOnlyList<NutritionAverageDayResult> DailyKilocalories);

public sealed record NutritionAverageDayResult(DateOnly Date, decimal? Kilocalories, decimal? TargetKilocalories, bool? WithinTarget);

public sealed record NutritionTargetsResult(IReadOnlyList<NutritionTargetResult> Versions);

public sealed record NutritionTargetResult(
    string Name,
    NutritionGoalCategory Category,
    DateOnly EffectiveFrom,
    DateOnly? EffectiveUntil,
    decimal Kilocalories,
    decimal ProteinGrams,
    decimal CarbohydrateGrams,
    decimal FatGrams,
    decimal? FiberGrams,
    decimal? SaltGrams,
    RestDayTargetResult? RestDay);

public sealed record RestDayTargetResult(
    decimal Kilocalories,
    decimal ProteinGrams,
    decimal CarbohydrateGrams,
    decimal FatGrams);

public sealed record SavedMealsResult(IReadOnlyList<SavedMealResult> Meals);

public sealed record SavedMealResult(
    string Name,
    string? Description,
    decimal StandardPortion,
    bool Archived,
    IReadOnlyList<SavedMealComponentResult> Components);

public sealed record SavedMealComponentResult(string Name, string? Brand, decimal Grams, NutritionTotals Nutrition);

public sealed record WaterResult(DateOnly From, DateOnly Through, IReadOnlyList<WaterDayResult> Days);

public sealed record WaterDayResult(DateOnly Date, int Milliliters);

public sealed record DayTemplatesResult(IReadOnlyList<DayTemplateResult> Templates);

public sealed record DayTemplateResult(
    string Name,
    NutritionDayKind? DayKind,
    NutritionTotals Totals,
    IReadOnlyList<NutritionEntryResult> Entries);
