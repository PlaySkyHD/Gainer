using System.Net;
using Gainer.ServiceDefaults;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Logging;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class HealthEndpointTests
{
    [TestMethod]
    public async Task ReadinessIgnoresOpenAiFailures()
    {
        await using var app = await CreateApplicationAsync(
            postgresStatus: HealthStatus.Healthy,
            schemaStatus: HealthStatus.Healthy,
            openAiStatus: HealthStatus.Unhealthy);
        using var client = app.GetTestClient();

        var response = await client.GetAsync("/health/ready", TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
    }

    [TestMethod]
    public async Task ReadinessFailsWhenPostgresFailsButLivenessRemainsHealthy()
    {
        await using var app = await CreateApplicationAsync(
            postgresStatus: HealthStatus.Unhealthy,
            schemaStatus: HealthStatus.Healthy,
            openAiStatus: HealthStatus.Healthy);
        using var client = app.GetTestClient();

        var readinessResponse = await client.GetAsync("/health/ready", TestContext.CancellationToken);
        var livenessResponse = await client.GetAsync("/health/live", TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.ServiceUnavailable, readinessResponse.StatusCode);
        Assert.AreEqual(HttpStatusCode.OK, livenessResponse.StatusCode);
    }

    private static async Task<WebApplication> CreateApplicationAsync(
        HealthStatus postgresStatus,
        HealthStatus schemaStatus,
        HealthStatus openAiStatus)
    {
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.AddGainerServiceDefaults();
        builder.Services
            .AddHealthChecks()
            .AddCheck(
                "postgresql",
                new StubHealthCheck(postgresStatus),
                tags: [GainerHealthCheckTags.Ready])
            .AddCheck(
                "database-schema",
                new StubHealthCheck(schemaStatus),
                tags: [GainerHealthCheckTags.Ready])
            .AddCheck(
                "openai",
                new StubHealthCheck(openAiStatus));

        var app = builder.Build();
        app.MapGainerHealthEndpoints();
        await app.StartAsync();

        return app;
    }

    private sealed class StubHealthCheck(HealthStatus status) : IHealthCheck
    {
        public Task<HealthCheckResult> CheckHealthAsync(
            HealthCheckContext context,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new HealthCheckResult(status));
        }
    }

    public TestContext TestContext { get; set; } = null!;
}
