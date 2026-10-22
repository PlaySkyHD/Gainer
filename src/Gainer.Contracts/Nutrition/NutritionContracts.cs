namespace Gainer.Contracts.Nutrition;

public sealed record NutritionTotalsResponse(
    decimal Kilocalories,
    decimal? ProteinGrams,
    decimal? CarbohydrateGrams,
    decimal? FatGrams,
    decimal? SaltGrams);

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
    long Version,
    NutritionProgressResponse? Progress);

public sealed record NutrientProgressResponse(
    decimal Consumed,
    decimal Target,
    decimal RemainingOrOver,
    decimal Ratio,
    bool IsComplete);

public sealed record NutritionProgressResponse(
    NutrientProgressResponse Kilocalories,
    NutrientProgressResponse Protein,
    NutrientProgressResponse Carbohydrates,
    NutrientProgressResponse Fat,
    NutrientProgressResponse Salt);

public sealed record RecentNutritionEntriesResponse(IReadOnlyList<NutritionEntryResponse> Entries);

public sealed record ReusableMealComponentResponse(
    Guid ComponentId,
    int Position,
    string Name,
    string? Brand,
    decimal AmountGrams,
    NutritionTotalsResponse Totals,
    NutritionTotalsResponse Per100Grams,
    NutritionSourceResponse? Source);

public sealed record ReusableMealResponse(
    Guid ReusableMealId,
    string Name,
    string? Description,
    decimal StandardPortion,
    string Status,
    IReadOnlyList<ReusableMealComponentResponse> Components,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version);

public sealed record ReusableMealsResponse(IReadOnlyList<ReusableMealResponse> Meals);

public sealed record NutritionTargetVersionResponse(
    Guid TargetVersionId,
    string Name,
    string Category,
    DateOnly EffectiveFrom,
    DateOnly? EffectiveUntil,
    decimal Kilocalories,
    string InputMode,
    decimal ProteinGrams,
    decimal CarbohydrateGrams,
    decimal FatGrams,
    decimal? ProteinPercent,
    decimal? CarbohydratePercent,
    decimal? FatPercent,
    string Origin,
    string? AlgorithmVersion,
    string? Reason,
    decimal MacroEnergyKilocalories,
    bool RequiresEnergyMismatchConfirmation,
    decimal? SaltGrams,
    decimal EffectiveSaltGrams);

public sealed record NutritionTargetScheduleResponse(
    Guid? NutritionTargetScheduleId,
    IReadOnlyList<NutritionTargetVersionResponse> Versions,
    DateTime? CreatedAtUtc,
    DateTime? UpdatedAtUtc,
    long Version);

public sealed record EffectiveNutritionTargetResponse(
    DateOnly LocalDate,
    NutritionTargetVersionResponse? Target);

public sealed record MealEstimateComponentResponse(
    string Name,
    decimal AmountGrams,
    decimal Kilocalories,
    decimal? ProteinGrams,
    decimal? CarbohydrateGrams,
    decimal? FatGrams,
    string Confidence,
    IReadOnlyList<string> DataGaps);

public sealed record MealEstimateResponse(
    IReadOnlyList<MealEstimateComponentResponse> Components,
    string Provider,
    string SchemaVersion,
    DateTime EstimatedAtUtc);

public sealed record NutritionLabelFieldResponse(
    decimal? OriginalValue,
    decimal? Per100Grams,
    string Status,
    string? Evidence);

public sealed record NutritionLabelScanResponse(
    string Basis,
    decimal? ServingMassGrams,
    NutritionLabelFieldResponse Kilocalories,
    NutritionLabelFieldResponse ProteinGrams,
    NutritionLabelFieldResponse CarbohydrateGrams,
    NutritionLabelFieldResponse FatGrams,
    NutritionLabelFieldResponse SaltGrams,
    bool CanConfirm,
    string Provider,
    string ProviderModelVersion,
    string ParserVersion,
    DateTime ScannedAtUtc);
