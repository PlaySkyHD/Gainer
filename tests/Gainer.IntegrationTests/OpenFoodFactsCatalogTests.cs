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

        FoodCatalogProduct product = await catalog.GetByBarcodeAsync("12345678", TestContext.CancellationToken);

        Assert.AreEqual("12345678", product.Barcode);
        Assert.AreEqual("Test product", product.ProductName);
        Assert.AreEqual(250.5m, product.NutrientsPer100Grams.Kilocalories);
        Assert.IsNull(product.NutrientsPer100Grams.CarbohydrateGrams);
        Assert.Contains("carbohydrates_missing", product.QualityIndicators.ToArray());
        Assert.Contains("GainerTests/1.0", handler.UserAgent!);
        Assert.Contains("/api/v3/product/12345678.json", handler.RequestUri!.AbsolutePath);
    }

    [TestMethod]
    public async Task KilojoulesAreConvertedAndMissingEnergyIsRejected()
    {
        OpenFoodFactsCatalog converted = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(kcal: null, energyKj: 418.4m))));
        Assert.AreEqual(100m, (await converted.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).NutrientsPer100Grams.Kilocalories);

        OpenFoodFactsCatalog missing = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(kcal: null, energyKj: null))));
        FoodCatalogException exception = await Assert.ThrowsAsync<FoodCatalogException>(() => missing.GetByBarcodeAsync("12345678", TestContext.CancellationToken));
        Assert.AreEqual("product_incomplete", exception.Code);
        Assert.IsFalse(exception.IsTemporary);
    }

    [TestMethod]
    public async Task ServingSizeInGramsBecomesThePieceWeight()
    {
        OpenFoodFactsCatalog egg = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(servingQuantity: "50", servingUnit: "g"))));
        Assert.AreEqual(50m, (await egg.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).ServingGrams);

        OpenFoodFactsCatalog text = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(servingQuantity: "\"30\""))));
        Assert.AreEqual(30m, (await text.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).ServingGrams);

        OpenFoodFactsCatalog pieces = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(servingQuantity: "2", servingUnit: "piece"))));
        Assert.IsNull((await pieces.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).ServingGrams);

        OpenFoodFactsCatalog none = Create(new QueueHandler(Response(HttpStatusCode.OK, Product())));
        Assert.IsNull((await none.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).ServingGrams);
    }

    [TestMethod]
    public async Task HtmlEntitiesInNamesAreDecoded()
    {
        const string json = "{\"product\":{\"code\":\"12345678\"," +
            "\"product_name\":\"Ironmaxx Maltodextrin Neutral, 1er Pack &#40;1 x 2 KG&#41\"," +
            "\"brands\":\"Ben &amp; Jerry&#39;s\",\"nutrition_data_per\":\"100g\"," +
            "\"nutriments\":{\"energy-kcal_100g\":385}}}";
        OpenFoodFactsCatalog catalog = Create(new QueueHandler(Response(HttpStatusCode.OK, json)));
        FoodCatalogProduct product = await catalog.GetByBarcodeAsync("12345678", TestContext.CancellationToken);
        Assert.AreEqual("Ironmaxx Maltodextrin Neutral, 1er Pack (1 x 2 KG)", product.ProductName);
        Assert.AreEqual("Ben & Jerry's", product.Brand);
    }

    [TestMethod]
    public async Task SaltIsReadDirectlyOrDerivedFromSodium()
    {
        OpenFoodFactsCatalog direct = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(salt: 1.2m, sodium: 0.48m))));
        Assert.AreEqual(1.2m, (await direct.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).NutrientsPer100Grams.SaltGrams);

        OpenFoodFactsCatalog sodiumOnly = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(sodium: 0.4m))));
        Assert.AreEqual(1m, (await sodiumOnly.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).NutrientsPer100Grams.SaltGrams);

        OpenFoodFactsCatalog none = Create(new QueueHandler(Response(HttpStatusCode.OK, Product())));
        Assert.IsNull((await none.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).NutrientsPer100Grams.SaltGrams);

        OpenFoodFactsCatalog tableSalt = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(kcal: 0m, protein: 0m, carbohydrates: 0m, fat: 0m, salt: 99.8m))));
        FoodCatalogProduct saltProduct = await tableSalt.GetByBarcodeAsync("12345678", TestContext.CancellationToken);
        Assert.AreEqual(0m, saltProduct.NutrientsPer100Grams.Kilocalories);
        Assert.AreEqual(99.8m, saltProduct.NutrientsPer100Grams.SaltGrams);

        OpenFoodFactsCatalog implausible = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(salt: 250m))));
        Assert.IsNull((await implausible.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).NutrientsPer100Grams.SaltGrams);
    }

    [TestMethod]
    public async Task FiberIsReadAndImplausibleValuesAreDropped()
    {
        OpenFoodFactsCatalog withFiber = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(fiber: 6.5m))));
        Assert.AreEqual(6.5m, (await withFiber.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).NutrientsPer100Grams.FiberGrams);

        OpenFoodFactsCatalog none = Create(new QueueHandler(Response(HttpStatusCode.OK, Product())));
        Assert.IsNull((await none.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).NutrientsPer100Grams.FiberGrams);

        OpenFoodFactsCatalog implausible = Create(new QueueHandler(Response(HttpStatusCode.OK, Product(fiber: 120m))));
        Assert.IsNull((await implausible.GetByBarcodeAsync("12345678", TestContext.CancellationToken)).NutrientsPer100Grams.FiberGrams);
    }

    [TestMethod]
    public async Task FreshCacheAndConcurrentDeduplicationAvoidDuplicateProviderRequests()
    {
        var handler = new QueueHandler(Response(HttpStatusCode.OK, Product()), delay: TimeSpan.FromMilliseconds(50));
        OpenFoodFactsCatalog catalog = Create(handler);

        FoodCatalogProduct[] products = await Task.WhenAll(
            catalog.GetByBarcodeAsync("12345678", TestContext.CancellationToken),
            catalog.GetByBarcodeAsync("12345678", TestContext.CancellationToken));
        _ = await catalog.GetByBarcodeAsync("12345678", TestContext.CancellationToken);

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
        _ = await catalog.GetByBarcodeAsync("12345678", TestContext.CancellationToken);
        time.UtcNow = time.UtcNow.AddMinutes(2);

        FoodCatalogProduct stale = await catalog.GetByBarcodeAsync("12345678", TestContext.CancellationToken);

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

        FoodCatalogSearchResult result = await catalog.SearchAsync("Hafer & Milch", 1, 2, TestContext.CancellationToken);

        Assert.AreSequenceEqual(ExpectedProductNames, result.Products.Select(item => item.ProductName).ToArray());
        Assert.IsTrue(result.HasMore);
        Assert.Contains("search_terms=Hafer%20%26%20Milch", handler.RequestUri!.Query);
        Assert.Contains("page_size=2", handler.RequestUri.Query);
    }

    [TestMethod]
    [Timeout(30_000, CooperativeCancellation = true)]
    public async Task RateLimitTimeoutInvalidJsonAndOversizedResponseMapToStableCodes()
    {
        var limitedHandler = new QueueHandler(
            Response(HttpStatusCode.OK, Product()),
            Response(HttpStatusCode.OK, Product(barcode: "87654321")));
        OpenFoodFactsCatalog limited = Create(limitedHandler, configure: options => options.BarcodeRequestsPerMinute = 1);
        _ = await limited.GetByBarcodeAsync("12345678", TestContext.CancellationToken);
        FoodCatalogException rate = await Assert.ThrowsAsync<FoodCatalogException>(() => limited.GetByBarcodeAsync("87654321", TestContext.CancellationToken));
        Assert.AreEqual("provider_rate_limited", rate.Code);

        FoodCatalogException invalid = await Assert.ThrowsAsync<FoodCatalogException>(() =>
            Create(new QueueHandler(Response(HttpStatusCode.OK, "not-json"))).GetByBarcodeAsync("12345678", TestContext.CancellationToken));
        Assert.AreEqual("invalid_provider_response", invalid.Code);

        FoodCatalogException oversized = await Assert.ThrowsAsync<FoodCatalogException>(() =>
            Create(new QueueHandler(Response(HttpStatusCode.OK, new string('x', 2_000))), configure: options => options.MaximumResponseBytes = 1_024)
                .GetByBarcodeAsync("12345678", TestContext.CancellationToken));
        Assert.AreEqual("provider_response_too_large", oversized.Code);

        FoodCatalogException timeout = await Assert.ThrowsAsync<FoodCatalogException>(() =>
            Create(new QueueHandler(Response(HttpStatusCode.OK, Product()), delay: Timeout.InfiniteTimeSpan), configure: options => options.TimeoutSeconds = 1)
                .GetByBarcodeAsync("12345678", TestContext.CancellationToken));
        Assert.AreEqual("provider_timeout", timeout.Code);
    }

    [TestMethod]
    public async Task SharedLookupSurvivesOneWaiterLeavingAndFreesTheKeyAtTheEnd()
    {
        var handler = new GateHandler(Response(HttpStatusCode.OK, Product()));
        OpenFoodFactsCatalog catalog = Create(handler);
        using var leaver = new CancellationTokenSource();

        Task<FoodCatalogProduct> leaving = catalog.GetByBarcodeAsync("12345678", leaver.Token);
        await handler.Started.Task.WaitAsync(TimeSpan.FromSeconds(10), TestContext.CancellationToken);
        Task<FoodCatalogProduct> staying = catalog.GetByBarcodeAsync("12345678", TestContext.CancellationToken);
        await leaver.CancelAsync();
        await Assert.ThrowsAsync<OperationCanceledException>(() => leaving);

        Task<FoodCatalogProduct> joining = catalog.GetByBarcodeAsync("12345678", TestContext.CancellationToken);
        Assert.IsFalse(handler.UpstreamCancelled.Task.IsCompleted, "One remaining waiter keeps the shared call alive.");
        handler.Release();

        Assert.AreEqual("Test product", (await staying).ProductName);
        Assert.AreEqual("Test product", (await joining).ProductName);
        Assert.AreEqual(1, handler.Calls, "Waiters share one upstream request.");
    }

    [TestMethod]
    public async Task SharedLookupIsCancelledWhenEveryWaiterLeaves()
    {
        var handler = new GateHandler(Response(HttpStatusCode.OK, Product()));
        OpenFoodFactsCatalog catalog = Create(handler);
        using var first = new CancellationTokenSource();
        using var second = new CancellationTokenSource();

        Task<FoodCatalogProduct> a = catalog.GetByBarcodeAsync("12345678", first.Token);
        await handler.Started.Task.WaitAsync(TimeSpan.FromSeconds(10), TestContext.CancellationToken);
        Task<FoodCatalogProduct> b = catalog.GetByBarcodeAsync("12345678", second.Token);
        await first.CancelAsync();
        await Assert.ThrowsAsync<OperationCanceledException>(() => a);
        Assert.IsFalse(handler.UpstreamCancelled.Task.IsCompleted);
        await second.CancelAsync();
        await Assert.ThrowsAsync<OperationCanceledException>(() => b);

        await handler.UpstreamCancelled.Task.WaitAsync(TimeSpan.FromSeconds(10), TestContext.CancellationToken);
    }

    private sealed class GateHandler(HttpResponseMessage response) : HttpMessageHandler
    {
        private readonly TaskCompletionSource released = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private int calls;
        public int Calls => Volatile.Read(ref calls);
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource UpstreamCancelled { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public void Release() => released.TrySetResult();

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref calls);
            Started.TrySetResult();
            try
            {
                await released.Task.WaitAsync(cancellationToken);
            }
            catch (OperationCanceledException)
            {
                UpstreamCancelled.TrySetResult();
                throw;
            }
            return response;
        }
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
        IOptions<OpenFoodFactsOptions> wrapped = Options.Create(options);
        TimeProvider clock = time ?? TimeProvider.System;
        return new OpenFoodFactsCatalog(new HttpClient(handler), wrapped, clock, new OpenFoodFactsCatalogState(wrapped, clock));
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
        decimal? fat = 5m,
        decimal? salt = null,
        decimal? sodium = null,
        string? servingQuantity = null,
        string? servingUnit = null,
        decimal? fiber = null)
    {
        var nutrientParts = new List<string>();
        if (kcal is not null) nutrientParts.Add($"\"energy-kcal_100g\":{kcal.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (energyKj is not null) nutrientParts.Add($"\"energy-kj_100g\":{energyKj.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (protein is not null) nutrientParts.Add($"\"proteins_100g\":{protein.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (carbohydrates is not null) nutrientParts.Add($"\"carbohydrates_100g\":{carbohydrates.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (fat is not null) nutrientParts.Add($"\"fat_100g\":{fat.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (salt is not null) nutrientParts.Add($"\"salt_100g\":{salt.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (sodium is not null) nutrientParts.Add($"\"sodium_100g\":{sodium.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        if (fiber is not null) nutrientParts.Add($"\"fiber_100g\":{fiber.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
        return "{\"product\":{\"code\":\"" + barcode +
            "\",\"product_name\":\"Test product\",\"brands\":\"Test brand\",\"nutrition_data_per\":\"100g\"," +
            (servingQuantity is null ? "" : $"\"serving_quantity\":{servingQuantity},") +
            (servingUnit is null ? "" : $"\"serving_quantity_unit\":\"{servingUnit}\",") +
            "\"nutriments\":{" +
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
            if (delay != TimeSpan.Zero) await Task.Delay(delay, cancellationToken);
            return responses.Dequeue();
        }
    }

    private sealed class MutableTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public DateTimeOffset UtcNow { get; set; } = utcNow;
        public override DateTimeOffset GetUtcNow() => UtcNow;
    }

    public TestContext TestContext { get; set; } = null!;
}
