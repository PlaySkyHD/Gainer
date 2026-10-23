namespace Gainer.Contracts.Nutrition;

public sealed record NutritionTotalsResponse(
    decimal Kilocalories,
    decimal? ProteinGrams,
    decimal? CarbohydrateGrams,
    decimal? FatGrams,
    decimal? SaltGrams = null,
    decimal? FiberGrams = null);

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
    NutritionSourceResponse? Source,
    decimal? PieceGrams = null,
    decimal? PieceCount = null);

public sealed record NutritionDayResponse(
    Guid? NutritionDayId,
    DateOnly LocalDate,
    IReadOnlyList<NutritionEntryResponse> Entries,
    NutritionTotalsResponse Totals,
    DateTime? CreatedAtUtc,
    DateTime? UpdatedAtUtc,
    long Version,
    NutritionProgressResponse? Progress,
    string? DayKind = null);

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
    NutrientProgressResponse? Salt = null,
    NutrientProgressResponse? Fiber = null);

public sealed record RecentNutritionEntriesResponse(IReadOnlyList<NutritionEntryResponse> Entries);

public sealed record ReusableMealComponentResponse(
    Guid ComponentId,
    int Position,
    string Name,
    string? Brand,
    decimal AmountGrams,
    NutritionTotalsResponse Totals,
    NutritionTotalsResponse Per100Grams,
    NutritionSourceResponse? Source,
    decimal? PieceGrams = null,
    decimal? PieceCount = null);

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
    decimal? SaltGrams = null,
    decimal? EffectiveSaltGrams = null,
    NutritionRestDayTargetResponse? RestDay = null,
    decimal? FiberGrams = null,
    decimal? EffectiveFiberGrams = null);

public sealed record NutritionRestDayTargetResponse(
    string InputMode,
    decimal Kilocalories,
    decimal ProteinGrams,
    decimal CarbohydrateGrams,
    decimal FatGrams,
    decimal? ProteinPercent,
    decimal? CarbohydratePercent,
    decimal? FatPercent,
    decimal MacroEnergyKilocalories,
    bool RequiresEnergyMismatchConfirmation);

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
    IReadOnlyList<string> DataGaps,
    decimal? SaltGrams = null,
    string? SourceUrl = null,
    decimal? PieceCount = null,
    decimal? PieceGrams = null,
    decimal? FiberGrams = null);

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
    bool CanConfirm,
    string Provider,
    string ProviderModelVersion,
    string ParserVersion,
    DateTime ScannedAtUtc,
    NutritionLabelFieldResponse? SaltGrams = null,
    NutritionLabelFieldResponse? FiberGrams = null);
