using Gainer.Core.Nutrition;

namespace Gainer.Infrastructure.Persistence;

internal static class NutritionSnapshots
{
    public static NutritionDaySnapshot Day(NutritionDay day, IEnumerable<NutritionEntry>? entrySource = null)
    {
        NutritionEntrySnapshot[] entries = (entrySource ?? day.Entries)
            .OrderBy(item => item.Meal)
            .ThenBy(item => item.Position)
            .ThenBy(item => item.Id)
            .Select(Entry)
            .ToArray();
        return new NutritionDaySnapshot(
            day.Id,
            day.LocalDate,
            entries,
            NutritionCalculator.Sum(entries.Select(item => item.Totals)),
            day.CreatedAtUtc,
            day.UpdatedAtUtc,
            day.Version,
            day.DayKind);
    }

    public static NutritionEntrySnapshot Entry(NutritionEntryValues entry)
    {
        decimal basisFactor = 100m / entry.BasisGrams;
        var per100 = new NutritionPer100Grams(
            entry.KilocaloriesPerBasis * basisFactor,
            Scale(entry.ProteinGramsPerBasis, basisFactor),
            Scale(entry.CarbohydrateGramsPerBasis, basisFactor),
            Scale(entry.FatGramsPerBasis, basisFactor),
            Scale(entry.SaltGramsPerBasis, basisFactor),
            Scale(entry.FiberGramsPerBasis, basisFactor));
        NutritionSourceSnapshot? source = string.IsNullOrWhiteSpace(entry.Provider) &&
            string.IsNullOrWhiteSpace(entry.Barcode) && entry.RetrievedAtUtc is null
                ? null
                : new NutritionSourceSnapshot(entry.Provider, entry.Barcode, entry.RetrievedAtUtc, entry.BasisGrams);
        return new NutritionEntrySnapshot(
            entry.Id,
            entry.Meal,
            entry.Position,
            entry.ProductName,
            entry.Brand,
            entry.AmountGrams,
            new NutritionTotals(
                entry.Kilocalories, entry.ProteinGrams, entry.CarbohydrateGrams, entry.FatGrams, entry.SaltGrams, entry.FiberGrams),
            per100,
            source,
            NutritionPortion.From(entry.PieceGrams, entry.PieceCount));
    }

    private static decimal? Scale(decimal? value, decimal factor) =>
        value is null ? null : decimal.Round(value.Value * factor, 2, MidpointRounding.AwayFromZero);
}
