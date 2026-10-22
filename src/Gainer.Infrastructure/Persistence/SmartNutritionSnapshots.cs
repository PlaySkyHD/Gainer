using Gainer.Core.Nutrition;

namespace Gainer.Infrastructure.Persistence;

internal static class SmartNutritionSnapshots
{
    public static ReusableMealSnapshot ReusableMeal(
        ReusableMeal meal,
        IEnumerable<ReusableMealComponent>? componentSource = null)
    {
        ReusableMealComponentDraft[] components = (componentSource ?? meal.Components)
            .OrderBy(item => item.Position)
            .ThenBy(item => item.Id)
            .Select(Component)
            .ToArray();
        return new ReusableMealSnapshot(
            meal.Id,
            meal.Name,
            meal.Description,
            meal.StandardPortion,
            meal.Status,
            components,
            meal.CreatedAtUtc,
            meal.UpdatedAtUtc,
            meal.Version);
    }

    public static ReusableMealComponentDraft Component(ReusableMealComponent component)
    {
        NutritionSourceSnapshot? source = string.IsNullOrWhiteSpace(component.Provider) &&
            string.IsNullOrWhiteSpace(component.Barcode) && component.RetrievedAtUtc is null
                ? null
                : new NutritionSourceSnapshot(
                    component.Provider,
                    component.Barcode,
                    component.RetrievedAtUtc,
                    component.BasisGrams);
        return ReusableMealComponentDraft.Create(
            component.Id,
            component.Position,
            component.Name,
            component.AmountGrams,
            new NutritionPer100Grams(
                component.KilocaloriesPer100Grams,
                component.ProteinGramsPer100Grams,
                component.CarbohydrateGramsPer100Grams,
                component.FatGramsPer100Grams,
                component.SaltGramsPer100Grams),
            component.Brand,
            source,
            NutritionPortion.From(component.PieceGrams, component.PieceCount));
    }

    public static NutritionTargetScheduleSnapshot TargetSchedule(
        NutritionTargetSchedule schedule,
        IEnumerable<NutritionTargetVersion>? versionSource = null)
    {
        NutritionTargetVersionDraft[] versions = (versionSource ?? schedule.Versions)
            .OrderBy(item => item.EffectiveFrom)
            .ThenBy(item => item.Id)
            .Select(TargetVersion)
            .ToArray();
        return new NutritionTargetScheduleSnapshot(
            schedule.Id,
            versions,
            schedule.CreatedAtUtc,
            schedule.UpdatedAtUtc,
            schedule.Version);
    }

    public static NutritionTargetVersionDraft TargetVersion(NutritionTargetVersion version) =>
        NutritionTargetVersionDraft.Restore(
            version.Id,
            version.Name,
            version.Category,
            version.EffectiveFrom,
            version.EffectiveUntil,
            version.Kilocalories,
            version.InputMode,
            version.ProteinGrams,
            version.CarbohydrateGrams,
            version.FatGrams,
            version.ProteinPercent,
            version.CarbohydratePercent,
            version.FatPercent,
            version.Origin,
            version.AlgorithmVersion,
            version.Reason,
            version.SaltGrams);
}
