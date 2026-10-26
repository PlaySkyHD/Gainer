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

        OpenAiProviderException exception = await Assert.ThrowsAsync<OpenAiProviderException>(() => provider.CreateResponseAsync(EmptyRequest));

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

        Assert.IsTrue(options.AttemptTimeout.Timeout >= TimeSpan.FromSeconds(seconds));
        Assert.IsTrue(options.TotalRequestTimeout.Timeout >= TimeSpan.FromSeconds(seconds));
        Assert.IsTrue(options.CircuitBreaker.SamplingDuration >= options.AttemptTimeout.Timeout * 2);
        Assert.AreEqual(Timeout.InfiniteTimeSpan, services.GetRequiredService<IHttpClientFactory>().CreateClient(clientName).Timeout);
    }

    [TestMethod]
    public async Task OpenFoodFactsServerErrorIsNotRepeated()
    {
        var handler = new CountingHandler(_ => new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        await using ServiceProvider services = BuildServices(handler);
        using IServiceScope scope = services.CreateScope();

        FoodCatalogException exception = await Assert.ThrowsAsync<FoodCatalogException>(() =>
            scope.ServiceProvider.GetRequiredService<IExternalFoodCatalog>().GetByBarcodeAsync("12345678"));

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
            timeoutScope.ServiceProvider.GetRequiredService<IOpenAiResponsesProvider>().CreateResponseAsync(EmptyRequest));
        Assert.AreEqual("provider_timeout", timeout.Code);

        var circuitHandler = new CountingHandler(_ => throw new BrokenCircuitException("circuit open"));
        await using ServiceProvider circuitServices = BuildServices(circuitHandler);
        using IServiceScope circuitScope = circuitServices.CreateScope();
        OpenAiProviderException unavailable = await Assert.ThrowsAsync<OpenAiProviderException>(() =>
            circuitScope.ServiceProvider.GetRequiredService<IOpenAiResponsesProvider>().CreateResponseAsync(EmptyRequest));
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

        await catalogA.GetByBarcodeAsync("12345678");
        FoodCatalogProduct cached = await catalogB.GetByBarcodeAsync("12345678");
        FoodCatalogException exhausted = await Assert.ThrowsAsync<FoodCatalogException>(() => catalogB.GetByBarcodeAsync("87654321"));

        Assert.AreEqual("Test", cached.ProductName);
        Assert.AreEqual(1, handler.Calls, "The second instance must serve the barcode from the shared cache.");
        Assert.AreEqual("provider_rate_limited", exhausted.Code, "The request budget must be shared across instances.");
    }

    private static ServiceProvider BuildServices(CountingHandler handler, params (string Key, string Value)[] settings)
    {
        HostApplicationBuilder builder = Host.CreateApplicationBuilder();
        builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["OpenAI:ApiKey"] = "secret-test-key",
            ["OpenFoodFacts:ContactEmail"] = "tests@example.test",
            ["ConnectionStrings:gainer-db"] = "Host=localhost;Database=unused",
        });
        builder.Configuration.AddInMemoryCollection(settings.ToDictionary(s => s.Key, s => (string?)s.Value));
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
}
