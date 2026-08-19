namespace Gainer.Contracts.Nutrition;

public sealed record NutritionTotalsResponse(
    decimal Kilocalories,
    decimal? ProteinGrams,
    decimal? CarbohydrateGrams,
    decimal? FatGrams);

public sealed record NutritionSourceResponse(
    string? Provider,
    string? Barcode,
    DateTime? RetrievedAtUtc,
    decimal BasisGrams);

public sealed record NutritionEntryResponse(
    Guid EntryId,
    string Meal,
    int Position,
    string ProductName,
    string? Brand,
    decimal AmountGrams,
    NutritionTotalsResponse Totals,
    NutritionTotalsResponse Per100Grams,
    NutritionSourceResponse? Source);

public sealed record NutritionDayResponse(
    Guid? NutritionDayId,
    DateOnly LocalDate,
    IReadOnlyList<NutritionEntryResponse> Entries,
    NutritionTotalsResponse Totals,
    DateTime? CreatedAtUtc,
    DateTime? UpdatedAtUtc,
    long Version);

public sealed record RecentNutritionEntriesResponse(IReadOnlyList<NutritionEntryResponse> Entries);
