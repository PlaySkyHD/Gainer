using System.ComponentModel;
using Gainer.Core.Nutrition;
using ModelContextProtocol.Server;

namespace Gainer.Api.Mcp;

/// <summary>Logged nutrition days, nutrition targets and saved meals.</summary>
[McpServerToolType]
public sealed class GainerNutritionTools(
    INutritionQueries nutrition,
    ISmartNutritionQueries smartNutrition,
    TimeProvider timeProvider)
{
    private const int MaximumNutritionDays = 31;

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

    /// <summary>The version in effect on a day: the latest start on or before it, still running then.</summary>
    private static NutritionTargetVersionDraft? EffectiveOn(IReadOnlyList<NutritionTargetVersionDraft> versions, DateOnly day) =>
        versions
            .Where(version => version.EffectiveFrom <= day && (version.EffectiveUntil is null || version.EffectiveUntil >= day))
            .OrderByDescending(version => version.EffectiveFrom)
            .FirstOrDefault();

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
