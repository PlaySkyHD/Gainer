namespace Gainer.Contracts.Nutrition;

public sealed record FoodCatalogProductResponse(
    string Barcode,
    string ProductName,
    string? Brand,
    decimal BasisGrams,
    decimal KilocaloriesPer100Grams,
    decimal? ProteinGramsPer100Grams,
    decimal? CarbohydrateGramsPer100Grams,
    decimal? FatGramsPer100Grams,
    IReadOnlyList<string> QualityIndicators,
    DateTime RetrievedAtUtc,
    bool IsStale,
    string Source);

public sealed record FoodCatalogSearchResponse(
    IReadOnlyList<FoodCatalogProductResponse> Products,
    int Page,
    bool HasMore);
