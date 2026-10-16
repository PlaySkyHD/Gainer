using System.Net;
using System.Text;
using Gainer.Core.Nutrition;
using Gainer.Infrastructure.Catalog;
using Microsoft.Extensions.Options;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class OpenFoodFactsCatalogTests
{
    private static readonly string[] ExpectedProductNames = ["Valid", "Also valid"];

    [TestMethod]
    public async Task ProductLookupNormalizesNutrientsAndSendsIdentifyingUserAgent()
    {
        var handler = new QueueHandler(Response(HttpStatusCode.OK, Product(kcal: 250.5m, protein: 20m, carbohydrates: null, fat: 5m)));
        OpenFoodFactsCatalog catalog = Create(handler);

        FoodCatalogProduct product = await catalog.GetByBarcodeAsync("12345678");

        Assert.AreEqual("12345678", product.Barcode);
        Assert.AreEqual("Test product", product.ProductName);
        Assert.AreEqual(250.5m, product.NutrientsPer100Grams.Kilocalories);
        Assert.IsNull(product.NutrientsPer100Grams.CarbohydrateGrams);
        CollectionAssert.Contains(product.QualityIndicators.ToArray(), "carbohydrates_missing");
        Assert.Contains("GainerTests/1.0", handler.UserAgent!);
        Assert.Contains("/api/v3/product/12345678.json", handler.RequestUri!.AbsolutePath);
    }

    [TestMethod]
    public async Task KilojoulesAreConvertedAndMissingEnergyIsRejected()
    {
        OpenFoodFactsCatalog converted = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(kcal: null, energyKj: 418.4m))));
        Assert.AreEqual(100m, (await converted.GetByBarcodeAsync("12345678")).NutrientsPer100Grams.Kilocalories);

        OpenFoodFactsCatalog missing = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(kcal: null, energyKj: null))));
        FoodCatalogException exception = await Assert.ThrowsAsync<FoodCatalogException>(() => missing.GetByBarcodeAsync("12345678"));
        Assert.AreEqual("product_incomplete", exception.Code);
        Assert.IsFalse(exception.IsTemporary);
    }

    [TestMethod]
    public async Task FreshCacheAndConcurrentDeduplicationAvoidDuplicateProviderRequests()
    {
        var handler = new QueueHandler(Response(HttpStatusCode.OK, Product()), delay: TimeSpan.FromMilliseconds(50));
        OpenFoodFactsCatalog catalog = Create(handler);

        FoodCatalogProduct[] products = await Task.WhenAll(
            catalog.GetByBarcodeAsync("12345678"),
            catalog.GetByBarcodeAsync("12345678"));
        _ = await catalog.GetByBarcodeAsync("12345678");

        Assert.AreEqual(1, handler.RequestCount);
        Assert.IsTrue(products.All(item => !item.IsStale));
    }

    [TestMethod]
    public async Task ExpiredFreshProductCanBeReturnedAsExplicitlyStaleDuringOutage()
    {
        var time = new MutableTimeProvider(new DateTimeOffset(2026, 8, 19, 10, 0, 0, TimeSpan.Zero));
        var handler = new QueueHandler(
            Response(HttpStatusCode.OK, Product()),
            Response(HttpStatusCode.ServiceUnavailable, "{}"));
        OpenFoodFactsCatalog catalog = Create(handler, time, options => options.BarcodeCacheMinutes = 1);
        _ = await catalog.GetByBarcodeAsync("12345678");
        time.UtcNow = time.UtcNow.AddMinutes(2);

        FoodCatalogProduct stale = await catalog.GetByBarcodeAsync("12345678");

        Assert.IsTrue(stale.IsStale);
        Assert.AreEqual(2, handler.RequestCount);
    }

    [TestMethod]
    public async Task SearchIsBoundedEscapedAndSkipsMalformedHits()
    {
        string body = """
        {"count":3,"products":[
          {"code":"1","product_name":"Valid","nutrition_data_per":"100g","nutriments":{"energy-kcal_100g":100}},
          {"code":"2","product_name":"No energy","nutriments":{}},
          {"code":"3","product_name":"Also valid","nutrition_data_per":"100g","nutriments":{"energy-kcal_100g":200}}
        ]}
        """;
        var handler = new QueueHandler(Response(HttpStatusCode.OK, body));
        OpenFoodFactsCatalog catalog = Create(handler);

        FoodCatalogSearchResult result = await catalog.SearchAsync("Hafer & Milch", 1, 2);

        CollectionAssert.AreEqual(ExpectedProductNames, result.Products.Select(item => item.ProductName).ToArray());
        Assert.IsTrue(result.HasMore);
        Assert.Contains("search_terms=Hafer%20%26%20Milch", handler.RequestUri!.Query);
        Assert.Contains("page_size=2", handler.RequestUri.Query);
    }

    [TestMethod]
    public async Task RateLimitTimeoutInvalidJsonAndOversizedResponseMapToStableCodes()
    {
        var limitedHandler = new QueueHandler(
            Response(HttpStatusCode.OK, Product()),
            Response(HttpStatusCode.OK, Product(barcode: "87654321")));
        OpenFoodFactsCatalog limited = Create(limitedHandler, configure: options => options.BarcodeRequestsPerMinute = 1);
        _ = await limited.GetByBarcodeAsync("12345678");
        FoodCatalogException rate = await Assert.ThrowsAsync<FoodCatalogException>(() => limited.GetByBarcodeAsync("87654321"));
        Assert.AreEqual("provider_rate_limited", rate.Code);

        FoodCatalogException invalid = await Assert.ThrowsAsync<FoodCatalogException>(() =>
            Create(new QueueHandler(Response(HttpStatusCode.OK, "not-json"))).GetByBarcodeAsync("12345678"));
        Assert.AreEqual("invalid_provider_response", invalid.Code);

        FoodCatalogException oversized = await Assert.ThrowsAsync<FoodCatalogException>(() =>
            Create(new QueueHandler(Response(HttpStatusCode.OK, new string('x', 2_000))), configure: options => options.MaximumResponseBytes = 1_024)
                .GetByBarcodeAsync("12345678"));
        Assert.AreEqual("provider_response_too_large", oversized.Code);

        FoodCatalogException timeout = await Assert.ThrowsAsync<FoodCatalogException>(() =>
            Create(new QueueHandler(Response(HttpStatusCode.OK, Product()), delay: TimeSpan.FromSeconds(2)), configure: options => options.TimeoutSeconds = 1)
                .GetByBarcodeAsync("12345678"));
        Assert.AreEqual("provider_timeout", timeout.Code);
    }

    private static OpenFoodFactsCatalog Create(
        HttpMessageHandler handler,
        TimeProvider? time = null,
        Action<OpenFoodFactsOptions>? configure = null)
    {
        var options = new OpenFoodFactsOptions
        {
            BaseUrl = "https://openfoodfacts.test/",
            ApplicationName = "GainerTests",
            ApplicationVersion = "1.0",
            ContactEmail = "tests@example.test",
        };
        configure?.Invoke(options);
        return new OpenFoodFactsCatalog(new HttpClient(handler), Options.Create(options), time ?? TimeProvider.System);
    }

    private static HttpResponseMessage Response(HttpStatusCode status, string body) => new(status)
    {
        Content = new StringContent(body, Encoding.UTF8, "application/json"),
    };

    private static string Product(
        string barcode = "12345678",
        decimal? kcal = 250m,
        decimal? energyKj = null,
        decimal? protein = 20m,
        decimal? carbohydrates = 30m,
        decimal? fat = 5m)
    {
        var nutrientParts = new List<string>();
        if (kcal is not null) nutrientParts.Add($"\"energy-kcal_100g\":{kcal.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (energyKj is not null) nutrientParts.Add($"\"energy-kj_100g\":{energyKj.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (protein is not null) nutrientParts.Add($"\"proteins_100g\":{protein.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (carbohydrates is not null) nutrientParts.Add($"\"carbohydrates_100g\":{carbohydrates.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (fat is not null) nutrientParts.Add($"\"fat_100g\":{fat.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        return "{\"product\":{\"code\":\"" + barcode +
            "\",\"product_name\":\"Test product\",\"brands\":\"Test brand\",\"nutrition_data_per\":\"100g\",\"nutriments\":{" +
            string.Join(',', nutrientParts) + "}}}";
    }

    private sealed class QueueHandler : HttpMessageHandler
    {
        private readonly Queue<HttpResponseMessage> responses;
        private readonly TimeSpan delay;
        public QueueHandler(params HttpResponseMessage[] responses) : this(responses, TimeSpan.Zero) { }
        public QueueHandler(HttpResponseMessage response, TimeSpan delay) : this([response], delay) { }
        private QueueHandler(IEnumerable<HttpResponseMessage> responses, TimeSpan delay)
        {
            this.responses = new Queue<HttpResponseMessage>(responses);
            this.delay = delay;
        }
        public int RequestCount { get; private set; }
        public Uri? RequestUri { get; private set; }
        public string? UserAgent { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            RequestCount++;
            RequestUri = request.RequestUri;
            UserAgent = request.Headers.UserAgent.ToString();
            if (delay > TimeSpan.Zero) await Task.Delay(delay, cancellationToken);
            return responses.Dequeue();
        }
    }

    private sealed class MutableTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public DateTimeOffset UtcNow { get; set; } = utcNow;
        public override DateTimeOffset GetUtcNow() => UtcNow;
    }
}
