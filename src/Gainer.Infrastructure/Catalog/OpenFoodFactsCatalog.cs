using System.Globalization;
using System.Net;
using System.Text.Json;
using Gainer.Core.Nutrition;
using Microsoft.Extensions.Options;
using Polly.CircuitBreaker;
using Polly.Timeout;

namespace Gainer.Infrastructure.Catalog;

public sealed partial class OpenFoodFactsCatalog : IExternalFoodCatalog
{
    private const string ProductFields = "code,product_name,brands,nutriments,last_modified_t,nutrition_data_per,serving_quantity,serving_quantity_unit";
    private const string ProductIncompleteCode = "product_incomplete";
    private readonly HttpClient httpClient;
    private readonly OpenFoodFactsOptions settings;
    private readonly TimeProvider timeProvider;
    private readonly OpenFoodFactsCatalogState state;

    public OpenFoodFactsCatalog(
        HttpClient httpClient,
        IOptions<OpenFoodFactsOptions> options,
        TimeProvider timeProvider,
        OpenFoodFactsCatalogState state)
    {
        this.httpClient = httpClient;
        settings = Validate(options.Value);
        this.timeProvider = timeProvider;
        this.state = state;
        this.httpClient.BaseAddress ??= new Uri(settings.BaseUrl, UriKind.Absolute);
        if (this.httpClient.DefaultRequestHeaders.UserAgent.Count == 0)
        {
            this.httpClient.DefaultRequestHeaders.UserAgent.ParseAdd(
                $"{settings.ApplicationName}/{settings.ApplicationVersion} ({settings.ContactEmail})");
        }
    }

    public async Task<FoodCatalogProduct> GetByBarcodeAsync(
        string barcode,
        CancellationToken cancellationToken = default)
    {
        string normalized = ValidateBarcode(barcode);
        string key = $"barcode:{normalized}";
        DateTimeOffset now = timeProvider.GetUtcNow();
        if (state.TryFresh(key, now, out FoodCatalogProduct? cached)) return cached;
        try
        {
            // The call is shared by all concurrent callers of this key; it is cancelled only when all of them give up.
            return await state.DeduplicateAsync(key, async sharedToken =>
            {
                if (!state.BarcodeBudget.TryAcquire()) throw Temporary("provider_rate_limited", "The food catalog request budget is exhausted.", 429);
                using JsonDocument document = await SendAsync(
                    $"api/v3/product/{Uri.EscapeDataString(normalized)}.json?fields={ProductFields}",
                    sharedToken);
                FoodCatalogProduct product = ParseProductEnvelope(document.RootElement, normalized, now.UtcDateTime);
                state.Store(
                    key,
                    product,
                    now.AddMinutes(settings.BarcodeCacheMinutes),
                    now.AddHours(settings.BarcodeStaleHours));
                return product;
            }, cancellationToken);
        }
        catch (FoodCatalogException exception) when (exception.IsTemporary && state.TryStale(key, now, out cached))
        {
            return cached with { IsStale = true };
        }
    }

    public Task<FoodCatalogSearchResult> SearchAsync(
        string query,
        int page,
        int pageSize,
        CancellationToken cancellationToken = default)
    {
        string normalized = ValidateSearch(query, page, pageSize);
        string key = $"search:{normalized.ToUpperInvariant()}:{page}:{pageSize}";
        DateTimeOffset now = timeProvider.GetUtcNow();
        if (state.TryFresh(key, now, out FoodCatalogSearchResult? cached)) return Task.FromResult(cached);
        return state.DeduplicateAsync(key, async sharedToken =>
        {
            if (!state.SearchBudget.TryAcquire()) throw Temporary("provider_rate_limited", "The food catalog search budget is exhausted.", 429);
            string path = "cgi/search.pl?search_simple=1&action=process&json=1" +
                $"&search_terms={Uri.EscapeDataString(normalized)}&page={page}&page_size={pageSize}&fields={ProductFields}";
            using JsonDocument document = await SendAsync(path, sharedToken);
            FoodCatalogSearchResult result = ParseSearch(document.RootElement, page, pageSize, now.UtcDateTime);
            state.Store(key, result, now.AddMinutes(settings.SearchCacheMinutes), now.AddMinutes(settings.SearchCacheMinutes));
            return result;
        }, cancellationToken);
    }

    private async Task<JsonDocument> SendAsync(string path, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(settings.TimeoutSeconds));
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, path);
            using HttpResponseMessage response = await httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (response.StatusCode == HttpStatusCode.NotFound)
                throw new FoodCatalogException("product_not_found", "The product was not found.", false, 404);
            if (!response.IsSuccessStatusCode)
            {
                bool temporary = response.StatusCode is HttpStatusCode.TooManyRequests or HttpStatusCode.ServiceUnavailable or HttpStatusCode.BadGateway or HttpStatusCode.GatewayTimeout;
                throw new FoodCatalogException(
                    temporary ? "provider_unavailable" : "provider_error",
                    "The food catalog provider request failed.",
                    temporary,
                    (int)response.StatusCode);
            }
            if (response.Content.Headers.ContentLength is > 0 && response.Content.Headers.ContentLength > settings.MaximumResponseBytes)
                throw new FoodCatalogException("provider_response_too_large", "The food catalog response is too large.", true);
            await using Stream input = await response.Content.ReadAsStreamAsync(timeout.Token);
            await using var bounded = new MemoryStream(Math.Min(settings.MaximumResponseBytes, 64 * 1024));
            byte[] buffer = new byte[16 * 1024];
            int total = 0;
            while (true)
            {
                int read = await input.ReadAsync(buffer.AsMemory(0, buffer.Length), timeout.Token);
                if (read == 0) break;
                total += read;
                if (total > settings.MaximumResponseBytes)
                    throw new FoodCatalogException("provider_response_too_large", "The food catalog response is too large.", true);
                await bounded.WriteAsync(buffer.AsMemory(0, read), timeout.Token);
            }
            bounded.Position = 0;
            return await JsonDocument.ParseAsync(bounded, cancellationToken: timeout.Token);
        }
        catch (Exception exception) when (exception is TimeoutRejectedException ||
            (exception is OperationCanceledException && !cancellationToken.IsCancellationRequested))
        {
            throw Temporary("provider_timeout", "The food catalog provider timed out.", innerException: exception);
        }
        catch (Exception exception) when (exception is HttpRequestException or BrokenCircuitException)
        {
            throw Temporary("provider_unavailable", "The food catalog provider is unavailable.", innerException: exception);
        }
        catch (JsonException exception)
        {
            throw Temporary("invalid_provider_response", "The food catalog provider returned invalid data.", innerException: exception);
        }
    }

    private static FoodCatalogProduct ParseProductEnvelope(JsonElement root, string requestedBarcode, DateTime retrievedAtUtc)
    {
        if (!root.TryGetProperty("product", out JsonElement product) || product.ValueKind != JsonValueKind.Object)
            throw new FoodCatalogException("product_not_found", "The product was not found.", false, 404);
        return ParseProduct(product, requestedBarcode, retrievedAtUtc);
    }

    private static FoodCatalogSearchResult ParseSearch(JsonElement root, int page, int pageSize, DateTime retrievedAtUtc)
    {
        if (!root.TryGetProperty("products", out JsonElement products) || products.ValueKind != JsonValueKind.Array)
            throw Temporary("invalid_provider_response", "The food catalog search response is invalid.");
        var normalized = new List<FoodCatalogProduct>(pageSize);
        foreach (JsonElement item in products.EnumerateArray())
        {
            if (normalized.Count == pageSize) break;
            try
            {
                string fallbackCode = String(item, "code") ?? string.Empty;
                normalized.Add(ParseProduct(item, fallbackCode, retrievedAtUtc));
            }
            catch (FoodCatalogException exception) when (exception.Code is ProductIncompleteCode or "product_not_found")
            {
                // A malformed search hit is skipped; the bounded result remains explicit.
            }
        }
        int count = Integer(root, "count") ?? normalized.Count;
        return new FoodCatalogSearchResult(normalized, page, page * pageSize < count);
    }

    private static FoodCatalogProduct ParseProduct(JsonElement product, string fallbackBarcode, DateTime retrievedAtUtc)
    {
        string barcode = String(product, "code") ?? fallbackBarcode;
        string? name = CleanText(String(product, "product_name"));
        if (string.IsNullOrWhiteSpace(barcode) || string.IsNullOrWhiteSpace(name))
            throw new FoodCatalogException(ProductIncompleteCode, "The product has no usable name or barcode.", false);
        if (!product.TryGetProperty("nutriments", out JsonElement nutrients) || nutrients.ValueKind != JsonValueKind.Object)
            throw new FoodCatalogException(ProductIncompleteCode, "The product has no usable nutrition data.", false);
        decimal? kcal = Decimal(nutrients, "energy-kcal_100g");
        if (kcal is null)
        {
            decimal? kj = Decimal(nutrients, "energy-kj_100g");
            if (kj is not null) kcal = decimal.Round(kj.Value / 4.184m, 2, MidpointRounding.AwayFromZero);
        }
        // Explicit 0 kcal is valid (salt, water); a missing value is not.
        if (kcal is null or < 0m)
            throw new FoodCatalogException(ProductIncompleteCode, "The product has no usable energy value.", false);
        decimal? protein = NonNegative(Decimal(nutrients, "proteins_100g"));
        decimal? carbohydrates = NonNegative(Decimal(nutrients, "carbohydrates_100g"));
        decimal? fat = NonNegative(Decimal(nutrients, "fat_100g"));
        decimal? salt = Salt(nutrients);
        decimal? fiber = NonNegative(Decimal(nutrients, "fiber_100g"));
        if (fiber > NutritionLimits.MaxFiberGramsPer100Grams) fiber = null;
        var quality = new List<string>();
        if (protein is null) quality.Add("protein_missing");
        if (carbohydrates is null) quality.Add("carbohydrates_missing");
        if (fat is null) quality.Add("fat_missing");
        if (!string.Equals(String(product, "nutrition_data_per"), "100g", StringComparison.OrdinalIgnoreCase))
            quality.Add("basis_unconfirmed");
        return new FoodCatalogProduct(
            barcode,
            name,
            CleanText(String(product, "brands")),
            100m,
            new NutritionPer100Grams(kcal.Value, protein, carbohydrates, fat, salt, fiber),
            quality,
            retrievedAtUtc,
            false,
            ServingGrams: ServingGrams(product));
    }

    /// <summary>Serving size in grams (or millilitres, taken as grams), e.g. one egg; null when unknown.</summary>
    private static decimal? ServingGrams(JsonElement product)
    {
        string? unit = String(product, "serving_quantity_unit");
        if (unit is not null && unit.Trim().ToLowerInvariant() is not ("g" or "ml")) return null;
        decimal? value = Decimal(product, "serving_quantity");
        return value is >= NutritionLimits.MinAmountGrams and <= NutritionPortion.MaxPieceGrams ? value : null;
    }

    /// <summary>Salt per 100 g; derived from sodium (× 2.5) when only sodium is listed.</summary>
    private static decimal? Salt(JsonElement nutrients)
    {
        decimal? salt = NonNegative(Decimal(nutrients, "salt_100g"));
        if (salt is null && NonNegative(Decimal(nutrients, "sodium_100g")) is { } sodium)
            salt = decimal.Round(sodium * SaltPerSodium, 2, MidpointRounding.AwayFromZero);
        return salt <= NutritionLimits.MaxSaltGramsPer100Grams ? salt : null;
    }

    private const decimal SaltPerSodium = 2.5m;

    private static string ValidateBarcode(string barcode)
    {
        if (string.IsNullOrWhiteSpace(barcode) || barcode.Length is < 4 or > 32 || barcode.Any(character => !char.IsAsciiDigit(character)))
            throw new ArgumentException("Barcode must contain 4 to 32 digits.", nameof(barcode));
        return barcode;
    }

    private static string ValidateSearch(string query, int page, int pageSize)
    {
        string normalized = query?.Trim() ?? string.Empty;
        if (normalized.Length is < 2 or > 100) throw new ArgumentException("Search query must contain 2 to 100 characters.", nameof(query));
        if (page is < 1 or > 100) throw new ArgumentOutOfRangeException(nameof(page));
        if (pageSize is < 1 or > 20) throw new ArgumentOutOfRangeException(nameof(pageSize));
        return normalized;
    }

    private static OpenFoodFactsOptions Validate(OpenFoodFactsOptions value)
    {
        if (!Uri.TryCreate(value.BaseUrl, UriKind.Absolute, out Uri? uri) || uri.Scheme != Uri.UriSchemeHttps)
            throw new InvalidOperationException("OpenFoodFacts:BaseUrl must be an absolute HTTPS URL.");
        if (string.IsNullOrWhiteSpace(value.ApplicationName) || string.IsNullOrWhiteSpace(value.ApplicationVersion) || string.IsNullOrWhiteSpace(value.ContactEmail))
            throw new InvalidOperationException("OpenFoodFacts application name, version, and contact email are required.");
        if (value.TimeoutSeconds is < 1 or > 30) throw new InvalidOperationException("OpenFoodFacts timeout is invalid.");
        if (value.MaximumResponseBytes is < 1_024 or > 5_000_000) throw new InvalidOperationException("OpenFoodFacts response limit is invalid.");
        if (value.BarcodeRequestsPerMinute is < 1 or > 14 || value.SearchRequestsPerMinute is < 1 or > 9)
            throw new InvalidOperationException("OpenFoodFacts request budgets must stay below provider limits.");
        return value;
    }

    /// <summary>
    /// Decodes HTML entities that Open Food Facts sometimes keeps in names, including numeric ones without the
    /// closing semicolon (&amp;#40 for "("), and collapses whitespace.
    /// </summary>
    internal static string? CleanText(string? value)
    {
        if (value is null) return null;
        string withSemicolons = NumericEntityWithoutSemicolon().Replace(value, match => match.Value + ";");
        string decoded = WebUtility.HtmlDecode(withSemicolons);
        string collapsed = Whitespace().Replace(decoded, " ").Trim();
        return collapsed.Length == 0 ? null : collapsed;
    }

    [System.Text.RegularExpressions.GeneratedRegex(@"&#(?:\d{1,7}|[xX][0-9a-fA-F]{1,6})(?![0-9a-fA-F;])")]
    private static partial System.Text.RegularExpressions.Regex NumericEntityWithoutSemicolon();

    [System.Text.RegularExpressions.GeneratedRegex(@"\s+")]
    private static partial System.Text.RegularExpressions.Regex Whitespace();

    private static string? String(JsonElement element, string name) =>
        element.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static int? Integer(JsonElement element, string name) =>
        element.TryGetProperty(name, out JsonElement value) && value.TryGetInt32(out int result) ? result : null;

    private static decimal? Decimal(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out JsonElement value)) return null;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out decimal number)) return number;
        if (value.ValueKind == JsonValueKind.String && decimal.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out number)) return number;
        return null;
    }

    private static decimal? NonNegative(decimal? value) => value is >= 0m ? value : null;
    private static FoodCatalogException Temporary(string code, string message, int? status = null, Exception? innerException = null) =>
        new(code, message, true, status, innerException);
}
