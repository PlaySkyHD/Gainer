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
    [Description("Logged nutrition per local day: every entry (meal, product, brand, grams, kcal and macros), the day " +
        "totals, the day type (training or rest day, if set) and the nutrition target in effect that day. Days " +
        "without entries are listed with no entries. Defaults to today; at most 31 days.")]
    public async Task<NutritionDaysResult> GetNutritionDays(
        [Description("First local day (YYYY-MM-DD); default through.")] DateOnly? from = null,
        [Description("Last local day (YYYY-MM-DD); default today.")] DateOnly? through = null,
        CancellationToken cancellationToken = default)
    {
        (DateOnly start, DateOnly end) = McpDates.Range(timeProvider, from, through, 1, MaximumNutritionDays);
        var days = new List<NutritionDayResult>();
        for (DateOnly day = start; day <= end; day = day.AddDays(1))
        {
            NutritionDaySnapshot? logged = await nutrition.GetDayAsync(day, cancellationToken);
            NutritionTargetVersionDraft? target = await smartNutrition.GetEffectiveNutritionTargetAsync(day, cancellationToken);
            days.Add(new NutritionDayResult(
                day,
                logged?.DayKind,
                logged?.Totals,
                logged?.Entries ?? [],
                target));
        }

        return new NutritionDaysResult(days);
    }

    [McpServerTool(Name = "get_nutrition_targets", Title = "Ernährungsziele", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("All versions of the nutrition target schedule: kcal, protein, carbohydrates, fat (grams or percent), " +
        "fiber, salt, the separate rest-day target and the dates each version applies.")]
    public async Task<NutritionTargetScheduleSnapshot?> GetNutritionTargets(CancellationToken cancellationToken = default) =>
        await smartNutrition.GetNutritionTargetScheduleAsync(cancellationToken);

    [McpServerTool(Name = "list_saved_meals", Title = "Gespeicherte Gerichte", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("Saved (reusable) meals with their components, standard portion and nutrition per component.")]
    public async Task<SavedMealsResult> ListSavedMeals(
        [Description("Include archived meals.")] bool includeArchived = false,
        CancellationToken cancellationToken = default) =>
        new(await smartNutrition.GetReusableMealsAsync(includeArchived, cancellationToken));
}

public sealed record NutritionDaysResult(IReadOnlyList<NutritionDayResult> Days);

public sealed record NutritionDayResult(
    DateOnly Date,
    NutritionDayKind? DayKind,
    NutritionTotals? Totals,
    IReadOnlyList<NutritionEntrySnapshot> Entries,
    NutritionTargetVersionDraft? Target);

public sealed record SavedMealsResult(IReadOnlyList<ReusableMealSnapshot> Meals);
