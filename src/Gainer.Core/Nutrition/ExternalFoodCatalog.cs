namespace Gainer.Core.Nutrition;

public sealed record FoodCatalogProduct(
    string Barcode,
    string ProductName,
    string? Brand,
    decimal BasisGrams,
    NutritionPer100Grams NutrientsPer100Grams,
    IReadOnlyList<string> QualityIndicators,
    DateTime RetrievedAtUtc,
    bool IsStale,
    string Source = "Open Food Facts");

public sealed record FoodCatalogSearchResult(
    IReadOnlyList<FoodCatalogProduct> Products,
    int Page,
    bool HasMore);

public interface IExternalFoodCatalog
{
    Task<FoodCatalogProduct> GetByBarcodeAsync(string barcode, CancellationToken cancellationToken = default);

    Task<FoodCatalogSearchResult> SearchAsync(
        string query,
        int page,
        int pageSize,
        CancellationToken cancellationToken = default);
}

public sealed class FoodCatalogException(
    string code,
    string message,
    bool isTemporary,
    int? providerStatusCode = null,
    Exception? innerException = null) : Exception(message, innerException)
{
    public string Code { get; } = code;
    public bool IsTemporary { get; } = isTemporary;
    public int? ProviderStatusCode { get; } = providerStatusCode;
}
