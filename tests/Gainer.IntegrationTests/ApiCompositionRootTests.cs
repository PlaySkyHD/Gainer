using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Contracts.System;
using Gainer.Core.Security;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Gainer.ServiceDefaults;
using OpenTelemetry;
using OpenTelemetry.Logs;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class ApiCompositionRootTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [TestMethod]
    public async Task VersionedStatusReturnsContractAndTracingHeaders()
    {
        await using var app = await CreateApplicationAsync();
        using var client = app.GetTestClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/system/status");
        request.Headers.Add(ApiConstants.CorrelationIdHeader, "test-correlation-42");

        using HttpResponseMessage response = await client.SendAsync(request, TestContext.CancellationToken);
        string responseBody = await response.Content.ReadAsStringAsync(TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, responseBody);
        SystemStatusResponse? payload = JsonSerializer.Deserialize<SystemStatusResponse>(
            responseBody,
            JsonOptions);
        Assert.IsNotNull(payload);
        Assert.AreEqual("ok", payload.Status);
        Assert.AreEqual("v1", payload.ApiVersion);
        Assert.AreEqual("test-correlation-42", response.Headers.GetValues(ApiConstants.CorrelationIdHeader).Single());
        Assert.IsFalse(string.IsNullOrWhiteSpace(response.Headers.GetValues(ApiConstants.TraceIdHeader).Single()));
    }

    [TestMethod]
    public async Task UnknownVersionedRouteReturnsStableProblemDetails()
    {
        var logProvider = new CollectingLoggerProvider();
        await using var app = await CreateApplicationAsync(logProvider);
        using var client = app.GetTestClient();

        using HttpResponseMessage response = await client.GetAsync("/api/v1/does-not-exist?private=value", TestContext.CancellationToken);
        using JsonDocument payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.NotFound, response.StatusCode);
        Assert.AreEqual("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        Assert.AreEqual("resource_not_found", payload.RootElement.GetProperty("code").GetString());
        Assert.IsFalse(string.IsNullOrWhiteSpace(payload.RootElement.GetProperty("traceId").GetString()));
        Assert.IsFalse(string.IsNullOrWhiteSpace(payload.RootElement.GetProperty("correlationId").GetString()));
        Assert.IsFalse(payload.RootElement.TryGetProperty("detail", out _));
        Assert.DoesNotContain(message => message.Contains("private=value", StringComparison.Ordinal), logProvider.Messages);
    }

    [TestMethod]
    public async Task OversizedRequestReturnsStableProblemWithoutReadingBody()
    {
        await using var app = await CreateApplicationAsync();
        using var client = app.GetTestClient();
        using var content = new ByteArrayContent(new byte[ApiConstants.MaximumRequestBodyBytes + 1]);

        using HttpResponseMessage response = await client.PostAsync("/api/v1/system/status", content, TestContext.CancellationToken);
        using JsonDocument payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        Assert.AreEqual("request_too_large", payload.RootElement.GetProperty("code").GetString());
    }

    [TestMethod]
    public async Task UserContextUsesOnlyTheAuthenticatedNameIdentifierClaim()
    {
        await using var app = await CreateApplicationAsync();
        Guid authenticatedUserId = Guid.NewGuid();
        var accessor = app.Services.GetRequiredService<IHttpContextAccessor>();
        accessor.HttpContext = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(
                [new Claim(ClaimTypes.NameIdentifier, authenticatedUserId.ToString())],
                authenticationType: "integration-test")),
        };
        using IServiceScope scope = app.Services.CreateScope();

        IUserContext userContext = scope.ServiceProvider.GetRequiredService<IUserContext>();

        Assert.AreEqual(authenticatedUserId, userContext.UserId);
    }

    [TestMethod]
    public async Task TwoTrustedProxyHopsRestorePublicOriginAndClientAddress()
    {
        await using var app = await CreateApplicationAsync();
        using var client = app.GetTestClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/forwarded-probe");
        request.Headers.Add("X-Forwarded-For", "203.0.113.10, 172.17.0.1");
        request.Headers.Add("X-Forwarded-Proto", "https");
        request.Headers.Add("X-Forwarded-Host", "gainer.markfort.xyz");

        using HttpResponseMessage response = await client.SendAsync(request, TestContext.CancellationToken);
        using JsonDocument payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        Assert.AreEqual("https", payload.RootElement.GetProperty("scheme").GetString());
        Assert.AreEqual("gainer.markfort.xyz", payload.RootElement.GetProperty("host").GetString());
        Assert.AreEqual("203.0.113.10", payload.RootElement.GetProperty("remoteIp").GetString());
    }

    [TestMethod]
    public async Task ForwardedAddressesBeyondTheFirstPublicHopAreIgnored()
    {
        await using var app = await CreateApplicationAsync();
        using var client = app.GetTestClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/forwarded-probe");
        // A client-supplied entry in front of the address host Caddy saw must not become the client.
        request.Headers.Add("X-Forwarded-For", "198.51.100.1, 203.0.113.10");

        using HttpResponseMessage response = await client.SendAsync(request, TestContext.CancellationToken);
        using JsonDocument payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.CancellationToken));

        Assert.AreEqual("203.0.113.10", payload.RootElement.GetProperty("remoteIp").GetString());
    }

    [TestMethod]
    public async Task ReadinessIsRateLimitedPerClient()
    {
        await using var app = await CreateApplicationAsync();
        using var client = app.GetTestClient();

        for (int attempt = 0; attempt < 30; attempt++)
        {
            using HttpResponseMessage allowed = await ReadinessAsync(client, "203.0.113.20");
            Assert.AreEqual(HttpStatusCode.OK, allowed.StatusCode);
        }

        using HttpResponseMessage limited = await ReadinessAsync(client, "203.0.113.20");
        using HttpResponseMessage otherClient = await ReadinessAsync(client, "203.0.113.21");
        using HttpResponseMessage otherPath = await client.GetAsync("/forwarded-probe", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.AreEqual(HttpStatusCode.OK, otherClient.StatusCode);
        Assert.AreEqual(HttpStatusCode.OK, otherPath.StatusCode);
    }

    [TestMethod]
    public async Task RateLimitedRequestReturnsProblemDetailsWithStableCode()
    {
        await using var app = await CreateApplicationAsync();
        using var client = app.GetTestClient();

        for (int attempt = 0; attempt < 60; attempt++)
        {
            using HttpResponseMessage allowed = await SystemStatusAsync(client, "203.0.113.30");
            Assert.AreEqual(HttpStatusCode.OK, allowed.StatusCode);
            Assert.IsTrue(allowed.Headers.CacheControl?.NoStore);
        }

        using HttpResponseMessage limited = await SystemStatusAsync(client, "203.0.113.30");
        using JsonDocument payload = JsonDocument.Parse(await limited.Content.ReadAsStringAsync(TestContext.CancellationToken));
        using HttpResponseMessage otherClient = await SystemStatusAsync(client, "203.0.113.31");

        Assert.AreEqual(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.AreEqual("application/problem+json", limited.Content.Headers.ContentType?.MediaType);
        Assert.AreEqual("rate_limited", payload.RootElement.GetProperty("code").GetString());
        Assert.AreEqual(HttpStatusCode.OK, otherClient.StatusCode);
    }

    [TestMethod]
    public async Task RequestLogContainsTheRouteTemplateNotTheRequestedPath()
    {
        var logProvider = new CollectingLoggerProvider();
        var exported = new List<string>();
        var activityValues = new List<string>();
        using var listener = new ActivityListener
        {
            ShouldListenTo = _ => true,
            Sample = static (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = activity =>
            {
                lock (activityValues)
                {
                    activityValues.Add(activity.DisplayName);
                    activityValues.AddRange(activity.TagObjects.Select(tag => $"{tag.Key}={tag.Value}"));
                }
            },
        };
        ActivitySource.AddActivityListener(listener);
        await using var app = await CreateApplicationAsync(logProvider, builder =>
        {
            // The exporter pipeline of production: OpenTelemetry logging and tracing with their scope settings.
            builder.AddGainerServiceDefaults();
            builder.Logging.AddOpenTelemetry(logging => logging.AddProcessor(new CapturingLogProcessor(exported)));
        });
        using var client = app.GetTestClient();

        using HttpResponseMessage response = await client.GetAsync("/probe/4006381333931?token=query-secret", TestContext.CancellationToken);
        using HttpResponseMessage unmatched = await client.GetAsync("/nowhere/2026-10-26", TestContext.CancellationToken);
        using HttpResponseMessage attribute = await client.GetAsync("/api/v1/system/status", TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        Assert.AreEqual(HttpStatusCode.NotFound, unmatched.StatusCode);
        Assert.AreEqual(HttpStatusCode.OK, attribute.StatusCode);
        await WaitForAsync(() =>
        {
            lock (activityValues)
            {
                return activityValues.Contains("url.path=/probe/{value}");
            }
        });

        // Messages, structured state values and scopes of the ordinary logger provider.
        Assert.Contains(message => message.Contains("GET /probe/{value}", StringComparison.Ordinal), logProvider.Messages);
        // Attribute routes are stored without a leading slash; the template always has one.
        Assert.Contains(message => message.Contains("GET /api/v1/system/status", StringComparison.Ordinal), logProvider.Messages);
        Assert.Contains(message => message.Contains("GET /unmatched", StringComparison.Ordinal), logProvider.Messages);
        AssertNoRequestedPath(logProvider.Messages);
        // What the OpenTelemetry log exporter would send, attributes and scopes included.
        Assert.Contains(value => value.Contains("GET /probe/{value}", StringComparison.Ordinal), exported);
        AssertNoRequestedPath(exported);
        // Span names and tags.
        lock (activityValues)
        {
            AssertNoRequestedPath(activityValues);
        }
    }

    [TestMethod]
    public void RouteTemplatesAlwaysStartWithASlash()
    {
        Assert.AreEqual("/api/v1/system/status", RequestRouteTemplate.Normalize("api/v1/system/status"));
        Assert.AreEqual("/probe/{value}", RequestRouteTemplate.Normalize("/probe/{value}"));
        Assert.AreEqual("/unmatched", RequestRouteTemplate.Normalize(null));
        Assert.AreEqual("/unmatched", RequestRouteTemplate.Normalize(string.Empty));
    }

    [TestMethod]
    public async Task UploadOperationsAreDescribedAsMultipartInTheOpenApiDocument()
    {
        await using var app = await CreateApplicationAsync();
        using var client = app.GetTestClient();

        using JsonDocument document = JsonDocument.Parse(await client.GetStringAsync("/openapi/v1.json", TestContext.CancellationToken));
        JsonElement paths = document.RootElement.GetProperty("paths");

        // Every operation that takes an uploaded file must be multipart, not only the two known paths.
        string[] uploads = ["/api/v1/nutrition/meal-estimates", "/api/v1/nutrition/label-scans"];
        foreach (string upload in uploads)
        {
            JsonElement content = paths.GetProperty(upload).GetProperty("post").GetProperty("requestBody").GetProperty("content");
            Assert.IsTrue(content.TryGetProperty("multipart/form-data", out JsonElement multipart), upload);
            Assert.AreEqual(
                "binary",
                multipart.GetProperty("schema").GetProperty("properties").GetProperty("image").GetProperty("format").GetString(),
                upload);
        }

        foreach (JsonProperty path in paths.EnumerateObject())
        {
            foreach (JsonProperty operation in path.Value.EnumerateObject())
            {
                if (operation.Value.TryGetProperty("requestBody", out JsonElement body)
                    && body.GetProperty("content").EnumerateObject().Any(media =>
                        media.Value.GetRawText().Contains("\"binary\"", StringComparison.Ordinal))
                    && !body.GetProperty("content").TryGetProperty("multipart/form-data", out _))
                {
                    Assert.Fail($"{path.Name} takes a file but is not described as multipart/form-data.");
                }
            }
        }
    }

    private static void AssertNoRequestedPath(IEnumerable<string> values)
    {
        string[] snapshot = values.ToArray();
        foreach (string privateValue in new[] { "4006381333931", "2026-10-26", "query-secret", "/nowhere" })
        {
            Assert.DoesNotContain(
                value => value.Contains(privateValue, StringComparison.Ordinal), snapshot,
                $"'{privateValue}' leaked: " + string.Join(" | ", snapshot.Where(value => value.Contains(privateValue, StringComparison.Ordinal))));
        }
    }

    private static async Task WaitForAsync(Func<bool> condition)
    {
        DateTime deadline = DateTime.UtcNow.AddSeconds(5);
        while (!condition() && DateTime.UtcNow < deadline)
        {
            await Task.Delay(25);
        }
    }

    private static async Task<HttpResponseMessage> SystemStatusAsync(HttpClient client, string clientAddress)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/system/status");
        request.Headers.Add("X-Forwarded-For", clientAddress);
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> ReadinessAsync(HttpClient client, string clientAddress)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/health/ready");
        request.Headers.Add("X-Forwarded-For", clientAddress);
        return await client.SendAsync(request);
    }

    private static async Task<WebApplication> CreateApplicationAsync(
        ILoggerProvider? loggerProvider = null,
        Action<WebApplicationBuilder>? configure = null)
    {
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        if (loggerProvider is not null)
        {
            builder.Logging.AddProvider(loggerProvider);
        }

        builder.WebHost.UseTestServer();
        configure?.Invoke(builder);
        builder.AddGainerApi();

        var app = builder.Build();
        app.MapGainerApi();
        app.MapOpenApi();
        app.MapGet("/health/ready", () => Results.Ok());
        app.MapGet("/probe/{value}", (string value) => Results.Ok());
        app.MapGet("/forwarded-probe", (HttpContext context) => Results.Json(new
        {
            scheme = context.Request.Scheme,
            host = context.Request.Host.Value,
            remoteIp = context.Connection.RemoteIpAddress?.ToString(),
        }));
        await app.StartAsync();

        return app;
    }

    private sealed class CollectingLoggerProvider : ILoggerProvider
    {
        public List<string> Messages { get; } = [];

        public ILogger CreateLogger(string categoryName)
        {
            return new CollectingLogger(Messages);
        }

        public void Dispose()
        {
        }
    }

    private sealed class CapturingLogProcessor(List<string> records) : BaseProcessor<LogRecord>
    {
        public override void OnEnd(LogRecord data)
        {
            lock (records)
            {
                records.Add(data.FormattedMessage ?? string.Empty);
                foreach (KeyValuePair<string, object?> attribute in data.Attributes ?? [])
                {
                    records.Add($"{attribute.Key}={attribute.Value}");
                }

                data.ForEachScope(
                    static (scope, state) =>
                    {
                        state.Add(scope.Scope?.ToString() ?? string.Empty);
                        foreach (KeyValuePair<string, object?> item in scope)
                        {
                            state.Add($"{item.Key}={item.Value}");
                        }
                    },
                    records);
            }
        }
    }

    private sealed class CollectingLogger(List<string> messages) : ILogger
    {
        public IDisposable BeginScope<TState>(TState state)
            where TState : notnull
        {
            messages.Add(Describe(state));
            return EmptyScope.Instance;
        }

        // Scope and state values, not only the formatted message: structured values are exported too.
        private static string Describe<TState>(TState state) =>
            state is IEnumerable<KeyValuePair<string, object?>> values
                ? string.Join(" ", values.Select(value => $"{value.Key}={value.Value}"))
                : state?.ToString() ?? string.Empty;

        public bool IsEnabled(LogLevel logLevel)
        {
            return true;
        }

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            messages.Add(formatter(state, exception));
            messages.Add(Describe(state));
        }
    }

    private sealed class EmptyScope : IDisposable
    {
        public static EmptyScope Instance { get; } = new();

        public void Dispose()
        {
        }
    }

    public TestContext TestContext { get; set; } = null!;
}
