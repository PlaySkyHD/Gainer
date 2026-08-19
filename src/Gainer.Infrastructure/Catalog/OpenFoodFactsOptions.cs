namespace Gainer.Infrastructure.Catalog;

public sealed class OpenFoodFactsOptions
{
    public const string SectionName = "OpenFoodFacts";
    public string BaseUrl { get; set; } = "https://world.openfoodfacts.org/";
    public string ApplicationName { get; set; } = "Gainer";
    public string ApplicationVersion { get; set; } = "1.0";
    public string ContactEmail { get; set; } = string.Empty;
    public int TimeoutSeconds { get; set; } = 8;
    public int MaximumResponseBytes { get; set; } = 1_000_000;
    public int BarcodeRequestsPerMinute { get; set; } = 12;
    public int SearchRequestsPerMinute { get; set; } = 8;
    public int BarcodeCacheMinutes { get; set; } = 1_440;
    public int BarcodeStaleHours { get; set; } = 168;
    public int SearchCacheMinutes { get; set; } = 5;
}
