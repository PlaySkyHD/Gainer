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

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class ApiCompositionRootTests
{
    [TestMethod]
    public async Task VersionedStatusReturnsContractAndTracingHeaders()
    {
        await using var app = await CreateApplicationAsync();
        using var client = app.GetTestClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/system/status");
        request.Headers.Add(ApiConstants.CorrelationIdHeader, "test-correlation-42");

        using HttpResponseMessage response = await client.SendAsync(request);
        string responseBody = await response.Content.ReadAsStringAsync();

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, responseBody);
        SystemStatusResponse? payload = JsonSerializer.Deserialize<SystemStatusResponse>(
            responseBody,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
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

        using HttpResponseMessage response = await client.GetAsync("/api/v1/does-not-exist?private=value");
        using JsonDocument payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.AreEqual(HttpStatusCode.NotFound, response.StatusCode);
        Assert.AreEqual("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        Assert.AreEqual("resource_not_found", payload.RootElement.GetProperty("code").GetString());
        Assert.IsFalse(string.IsNullOrWhiteSpace(payload.RootElement.GetProperty("traceId").GetString()));
        Assert.IsFalse(string.IsNullOrWhiteSpace(payload.RootElement.GetProperty("correlationId").GetString()));
        Assert.IsFalse(payload.RootElement.TryGetProperty("detail", out _));
        Assert.IsFalse(logProvider.Messages.Any(message => message.Contains("private=value", StringComparison.Ordinal)));
    }

    [TestMethod]
    public async Task OversizedRequestReturnsStableProblemWithoutReadingBody()
    {
        await using var app = await CreateApplicationAsync();
        using var client = app.GetTestClient();
        using var content = new ByteArrayContent(new byte[ApiConstants.MaximumRequestBodyBytes + 1]);

        using HttpResponseMessage response = await client.PostAsync("/api/v1/system/status", content);
        using JsonDocument payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

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

        using HttpResponseMessage response = await client.SendAsync(request);
        using JsonDocument payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        Assert.AreEqual("https", payload.RootElement.GetProperty("scheme").GetString());
        Assert.AreEqual("gainer.markfort.xyz", payload.RootElement.GetProperty("host").GetString());
        Assert.AreEqual("203.0.113.10", payload.RootElement.GetProperty("remoteIp").GetString());
    }

    private static async Task<WebApplication> CreateApplicationAsync(ILoggerProvider? loggerProvider = null)
    {
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        if (loggerProvider is not null)
        {
            builder.Logging.AddProvider(loggerProvider);
        }

        builder.WebHost.UseTestServer();
        builder.AddGainerApi();

        var app = builder.Build();
        app.MapGainerApi();
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

    private sealed class CollectingLogger(List<string> messages) : ILogger
    {
        public IDisposable BeginScope<TState>(TState state)
            where TState : notnull
        {
            return EmptyScope.Instance;
        }

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
        }
    }

    private sealed class EmptyScope : IDisposable
    {
        public static EmptyScope Instance { get; } = new();

        public void Dispose()
        {
        }
    }
}
