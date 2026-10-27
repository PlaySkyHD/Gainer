using System.Net;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Infrastructure.Persistence;
using Gainer.ServiceDefaults;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authorization.Infrastructure;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class FallbackAuthorizationTests
{
    private const string UnmarkedProbePath = "/unmarked-probe";
    private const string AnonymousProbePath = "/anonymous-probe";

    private static readonly string[] AnonymousRoutes =
    [
        "/health/live",
        "/health/ready",
        "/api/v1/auth/login",
        "/api/v1/auth/refresh",
        "/api/v1/auth/passkeys/request-options",
        "/api/v1/auth/passkeys/login",
        "/api/v1/integrations/strava/callback",
        "/api/v1/auth/invitations/accept",
        "/api/v1/system/status",
    ];

    [TestMethod]
    public async Task FallbackPolicyRequiresAnAuthenticatedUser()
    {
        string keyRingPath = NewKeyRingPath();
        try
        {
            await using WebApplication app = await CreateApplicationAsync(keyRingPath);

            AuthorizationPolicy? fallback = await app.Services
                .GetRequiredService<IAuthorizationPolicyProvider>()
                .GetFallbackPolicyAsync();

            Assert.IsNotNull(fallback);
            Assert.IsNotEmpty(fallback.Requirements.OfType<DenyAnonymousAuthorizationRequirement>());
        }
        finally
        {
            DeleteKeyRing(keyRingPath);
        }
    }

    [TestMethod]
    public async Task HealthStaysReachableWithoutLoginAndUnmarkedEndpointsAreProtected()
    {
        string keyRingPath = NewKeyRingPath();
        try
        {
            await using WebApplication app = await CreateApplicationAsync(keyRingPath);
            using HttpClient client = app.GetTestClient();

            using HttpResponseMessage live = await client.GetAsync("/health/live", TestContext.CancellationToken);
            using HttpResponseMessage ready = await client.GetAsync("/health/ready", TestContext.CancellationToken);
            using HttpResponseMessage status = await client.GetAsync("/api/v1/system/status", TestContext.CancellationToken);
            using HttpResponseMessage session = await client.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
            using HttpResponseMessage unmarked = await client.GetAsync(UnmarkedProbePath, TestContext.CancellationToken);
            using HttpResponseMessage open = await client.GetAsync(AnonymousProbePath, TestContext.CancellationToken);

            Assert.AreEqual(HttpStatusCode.OK, live.StatusCode);
            Assert.AreEqual(HttpStatusCode.OK, ready.StatusCode);
            Assert.AreEqual(HttpStatusCode.OK, status.StatusCode);
            Assert.AreEqual(HttpStatusCode.Unauthorized, session.StatusCode);
            Assert.AreEqual(HttpStatusCode.Unauthorized, unmarked.StatusCode);
            Assert.AreEqual(HttpStatusCode.OK, open.StatusCode);
        }
        finally
        {
            DeleteKeyRing(keyRingPath);
        }
    }

    // Counterpart of the controller check in the architecture tests: it sees every mapped endpoint,
    // also those from Map* calls. A new anonymous endpoint has to be listed here on purpose.
    [TestMethod]
    public async Task OnlyTheListedEndpointsAreAnonymous()
    {
        string keyRingPath = NewKeyRingPath();
        try
        {
            await using WebApplication app = await CreateApplicationAsync(keyRingPath);

            string[] anonymous = app.Services.GetRequiredService<EndpointDataSource>().Endpoints
                .OfType<RouteEndpoint>()
                .Where(endpoint => endpoint.Metadata.GetMetadata<IAllowAnonymous>() is not null)
                .Select(endpoint => "/" + endpoint.RoutePattern.RawText!.TrimStart('/'))
                .Where(route => route != AnonymousProbePath)
                .Order(StringComparer.Ordinal)
                .ToArray();

            Assert.AreSequenceEqual(AnonymousRoutes.Order(StringComparer.Ordinal).ToArray(), anonymous);
        }
        finally
        {
            DeleteKeyRing(keyRingPath);
        }
    }

    private static string NewKeyRingPath() =>
        Path.Combine(Path.GetTempPath(), $"gainer-fallback-{Guid.NewGuid():N}");

    private static void DeleteKeyRing(string path)
    {
        if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }
    }

    private static async Task<WebApplication> CreateApplicationAsync(string keyRingPath)
    {
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration["ConnectionStrings:gainer-db"] =
            "Host=127.0.0.1;Port=1;Database=unused;Username=unused;Password=unused";
        builder.AddGainerServiceDefaults();
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();

        var app = builder.Build();
        app.MapGainerApi();
        app.MapGainerHealthEndpoints();
        app.MapGet(UnmarkedProbePath, () => Results.Ok());
        app.MapGet(AnonymousProbePath, () => Results.Ok()).AllowAnonymous();
        await app.StartAsync();

        return app;
    }

    public TestContext TestContext { get; set; } = null!;
}
