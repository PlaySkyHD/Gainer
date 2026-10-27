using System.Net;
using System.Text;
using System.Text.Json;
using Gainer.Core.Coach;
using Gainer.Core.Nutrition;
using Gainer.Infrastructure.Integrations;
using Gainer.Infrastructure.Persistence;
using Gainer.ServiceDefaults;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Http.Resilience;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Polly.CircuitBreaker;
using Polly.Timeout;

namespace Gainer.IntegrationTests;

/// <summary>Resolves the outbound clients through the real DI pipeline, including the shared resilience defaults.</summary>
[TestClass]
public sealed class ExternalHttpClientPipelineTests
{
    private static readonly JsonElement EmptyRequest = JsonSerializer.SerializeToElement(new { input = Array.Empty<object>() });

    [TestMethod]
    public async Task OpenAiPostIsNotRepeatedAfterServerError()
    {
        var handler = new CountingHandler(_ => new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        await using ServiceProvider services = BuildServices(handler);
        using IServiceScope scope = services.CreateScope();
        IOpenAiResponsesProvider provider = scope.ServiceProvider.GetRequiredService<IOpenAiResponsesProvider>();

        OpenAiProviderException exception = await Assert.ThrowsAsync<OpenAiProviderException>(() => provider.CreateResponseAsync(EmptyRequest, TestContext.CancellationToken));

        Assert.AreEqual("provider_error", exception.Code);
        Assert.AreEqual(1, handler.Calls, "A POST to the AI provider costs money and must not be retried.");
    }

    [TestMethod]
    [DataRow(nameof(IOpenAiResponsesProvider), "OpenAI:TimeoutSeconds", 60)]
    [DataRow(nameof(IStravaApiClient), "Strava:TimeoutSeconds", 90)]
    [DataRow(nameof(IExternalFoodCatalog), "OpenFoodFacts:TimeoutSeconds", 20)]
    public async Task ProviderClientsAllowTheirConfiguredTimeout(string clientName, string settingKey, int seconds)
    {
        await using ServiceProvider services = BuildServices(
            new CountingHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)),
            (settingKey, seconds.ToString(System.Globalization.CultureInfo.InvariantCulture)));

        HttpStandardResilienceOptions options = services
            .GetRequiredService<IOptionsMonitor<HttpStandardResilienceOptions>>()
            .Get($"{clientName}-standard");

        Assert.IsGreaterThanOrEqualTo(TimeSpan.FromSeconds(seconds), options.AttemptTimeout.Timeout);
        Assert.IsGreaterThanOrEqualTo(TimeSpan.FromSeconds(seconds), options.TotalRequestTimeout.Timeout);
        Assert.IsGreaterThanOrEqualTo(options.AttemptTimeout.Timeout * 2, options.CircuitBreaker.SamplingDuration);
        Assert.AreEqual(Timeout.InfiniteTimeSpan, services.GetRequiredService<IHttpClientFactory>().CreateClient(clientName).Timeout);
    }

    [TestMethod]
    public async Task OpenFoodFactsServerErrorIsNotRepeated()
    {
        var handler = new CountingHandler(_ => new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        await using ServiceProvider services = BuildServices(handler);
        using IServiceScope scope = services.CreateScope();

        FoodCatalogException exception = await Assert.ThrowsAsync<FoodCatalogException>(() =>
            scope.ServiceProvider.GetRequiredService<IExternalFoodCatalog>().GetByBarcodeAsync("12345678", TestContext.CancellationToken));

        Assert.AreEqual("provider_unavailable", exception.Code);
        Assert.AreEqual(1, handler.Calls, "One budget slot must cost one HTTP request.");
    }

    [TestMethod]
    public async Task OpenAiPipelineTimeoutAndOpenCircuitMapToProviderErrors()
    {
        var timeoutHandler = new CountingHandler(_ => throw new TimeoutRejectedException("pipeline timeout"));
        await using ServiceProvider timeoutServices = BuildServices(timeoutHandler);
        using IServiceScope timeoutScope = timeoutServices.CreateScope();
        OpenAiProviderException timeout = await Assert.ThrowsAsync<OpenAiProviderException>(() =>
            timeoutScope.ServiceProvider.GetRequiredService<IOpenAiResponsesProvider>().CreateResponseAsync(EmptyRequest, TestContext.CancellationToken));
        Assert.AreEqual("provider_timeout", timeout.Code);

        var circuitHandler = new CountingHandler(_ => throw new BrokenCircuitException("circuit open"));
        await using ServiceProvider circuitServices = BuildServices(circuitHandler);
        using IServiceScope circuitScope = circuitServices.CreateScope();
        OpenAiProviderException unavailable = await Assert.ThrowsAsync<OpenAiProviderException>(() =>
            circuitScope.ServiceProvider.GetRequiredService<IOpenAiResponsesProvider>().CreateResponseAsync(EmptyRequest, TestContext.CancellationToken));
        Assert.AreEqual("provider_unavailable", unavailable.Code);
    }

    [TestMethod]
    public async Task CatalogInstancesShareCacheAndBudget()
    {
        var handler = new CountingHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(
                "{\"product\":{\"code\":\"12345678\",\"product_name\":\"Test\",\"nutrition_data_per\":\"100g\"," +
                "\"nutriments\":{\"energy-kcal_100g\":250,\"proteins_100g\":20,\"carbohydrates_100g\":30,\"fat_100g\":5}}}",
                Encoding.UTF8,
                "application/json"),
        });
        await using ServiceProvider services = BuildServices(handler, ("OpenFoodFacts:BarcodeRequestsPerMinute", "1"));
        using IServiceScope first = services.CreateScope();
        using IServiceScope second = services.CreateScope();
        IExternalFoodCatalog catalogA = first.ServiceProvider.GetRequiredService<IExternalFoodCatalog>();
        IExternalFoodCatalog catalogB = second.ServiceProvider.GetRequiredService<IExternalFoodCatalog>();
        Assert.AreNotSame(catalogA, catalogB);

        await catalogA.GetByBarcodeAsync("12345678", TestContext.CancellationToken);
        FoodCatalogProduct cached = await catalogB.GetByBarcodeAsync("12345678", TestContext.CancellationToken);
        FoodCatalogException exhausted = await Assert.ThrowsAsync<FoodCatalogException>(() => catalogB.GetByBarcodeAsync("87654321", TestContext.CancellationToken));

        Assert.AreEqual("Test", cached.ProductName);
        Assert.AreEqual(1, handler.Calls, "The second instance must serve the barcode from the shared cache.");
        Assert.AreEqual("provider_rate_limited", exhausted.Code, "The request budget must be shared across instances.");
    }

    [TestMethod]
    public async Task OutboundRequestPathsAreNotLogged()
    {
        var handler = new CountingHandler(_ => new HttpResponseMessage(HttpStatusCode.NotFound));
        var logs = new CapturingLoggerProvider();
        await using ServiceProvider services = BuildServices(handler, logs);
        using IServiceScope scope = services.CreateScope();

        await Assert.ThrowsAsync<FoodCatalogException>(() =>
            scope.ServiceProvider.GetRequiredService<IExternalFoodCatalog>().GetByBarcodeAsync("40084107", TestContext.CancellationToken));

        Assert.AreEqual(1, handler.Calls);
        Assert.DoesNotContain("40084107", string.Join('\n', logs.Messages), "Barcodes in request paths must not reach the logs.");
    }

    [TestMethod]
    [DataRow("https://www.strava.com/api/v3/uploads/123456789", "/api/v3/uploads/{id}")]
    [DataRow("https://www.strava.com/api/v3/activities/987654321?include_all_efforts=false", "/api/v3/activities/{id}")]
    [DataRow("https://www.strava.com/api/v3/uploads", "/api/v3/uploads")]
    public void StravaErrorLogsCarryNoIdentifiers(string uri, string expected) =>
        Assert.AreEqual(expected, StravaApiClient.RedactedPath(new Uri(uri)));

    private static ServiceProvider BuildServices(CountingHandler handler, params (string Key, string Value)[] settings) =>
        BuildServices(handler, null, settings);

    private static ServiceProvider BuildServices(CountingHandler handler, ILoggerProvider? logs, params (string Key, string Value)[] settings)
    {
        HostApplicationBuilder builder = Host.CreateApplicationBuilder();
        builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["OpenAI:ApiKey"] = "secret-test-key",
            ["OpenFoodFacts:ContactEmail"] = "tests@example.test",
            ["ConnectionStrings:gainer-db"] = "Host=localhost;Database=unused",
        });
        builder.Configuration.AddInMemoryCollection(settings.ToDictionary(s => s.Key, s => (string?)s.Value));
        if (logs is not null)
        {
            builder.Logging.SetMinimumLevel(LogLevel.Trace);
            builder.Logging.AddProvider(logs);
        }

        builder.AddGainerServiceDefaults();
        builder.AddGainerPersistence();
        builder.Services.AddSingleton(TimeProvider.System);
        builder.Services.ConfigureHttpClientDefaults(client => client.ConfigurePrimaryHttpMessageHandler(() => handler));
        return builder.Services.BuildServiceProvider();
    }

    private sealed class CountingHandler(Func<HttpRequestMessage, HttpResponseMessage> respond, TimeSpan delay = default) : HttpMessageHandler
    {
        private int calls;

        public int Calls => Volatile.Read(ref calls);

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref calls);
            if (delay > TimeSpan.Zero) await Task.Delay(delay, cancellationToken);
            return respond(request);
        }
    }

    private sealed class CapturingLoggerProvider : ILoggerProvider
    {
        private readonly System.Collections.Concurrent.ConcurrentQueue<string> messages = new();

        public IEnumerable<string> Messages => messages;

        public ILogger CreateLogger(string categoryName) => new CapturingLogger(messages);

        public void Dispose()
        {
        }

        private sealed class CapturingLogger(System.Collections.Concurrent.ConcurrentQueue<string> messages) : ILogger
        {
            public IDisposable? BeginScope<TState>(TState state)
                where TState : notnull => null;

            public bool IsEnabled(LogLevel logLevel) => true;

            public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
                messages.Enqueue(formatter(state, exception));
        }
    }

    public TestContext TestContext { get; set; } = null!;
}
