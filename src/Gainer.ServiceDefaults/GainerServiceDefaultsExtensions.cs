using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;

namespace Gainer.ServiceDefaults;

/// <summary>
/// Configures the shared operational defaults used by Gainer services.
/// </summary>
public static class GainerServiceDefaultsExtensions
{
    /// <summary>
    /// Adds service discovery, resilient HTTP defaults, OpenTelemetry and liveness checks.
    /// </summary>
    /// <typeparam name="TBuilder">The host builder type.</typeparam>
    /// <param name="builder">The service host builder.</param>
    /// <returns>The supplied builder.</returns>
    public static TBuilder AddGainerServiceDefaults<TBuilder>(this TBuilder builder)
        where TBuilder : IHostApplicationBuilder
    {
        builder.Services.AddServiceDiscovery();
        builder.Services.ConfigureHttpClientDefaults(static httpClient =>
        {
            httpClient.AddStandardResilienceHandler();
            httpClient.AddServiceDiscovery();
        });

        builder.Services
            .AddHealthChecks()
            .AddCheck(
                "self",
                static () => HealthCheckResult.Healthy(),
                tags: [GainerHealthCheckTags.Live]);

        builder.ConfigureGainerOpenTelemetry();

        return builder;
    }

    /// <summary>
    /// Maps the stable liveness and readiness endpoints.
    /// </summary>
    /// <param name="app">The web application.</param>
    /// <returns>The supplied application.</returns>
    public static WebApplication MapGainerHealthEndpoints(this WebApplication app)
    {
        app.MapHealthChecks("/health/live", new HealthCheckOptions
        {
            Predicate = static registration => registration.Tags.Contains(GainerHealthCheckTags.Live),
        }).AllowAnonymous();

        app.MapHealthChecks("/health/ready", new HealthCheckOptions
        {
            Predicate = static registration => registration.Tags.Contains(GainerHealthCheckTags.Ready),
        }).AllowAnonymous();

        return app;
    }

    private static void ConfigureGainerOpenTelemetry<TBuilder>(this TBuilder builder)
        where TBuilder : IHostApplicationBuilder
    {
        builder.Logging.AddOpenTelemetry(static logging =>
        {
            logging.IncludeFormattedMessage = true;
            // Scopes would export whatever a framework puts into them (RequestPath, for one), and
            // no Gainer code opens a scope. Trace and span ids come from the activity, not from scopes.
            logging.IncludeScopes = false;
        });

        var openTelemetry = builder.Services
            .AddOpenTelemetry()
            .WithMetrics(static metrics =>
            {
                metrics
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation();
            })
            .WithTracing(tracing =>
            {
                tracing
                    .AddSource(builder.Environment.ApplicationName)
                    .AddAspNetCoreInstrumentation(options =>
                    {
                        // Paths such as /foods/barcode/{barcode} or /nutrition/days/{date} are private.
                        // The route is known only after routing, so the request path is dropped at the
                        // start and the response enrichment sets the route template.
                        options.EnrichWithHttpRequest = static (activity, _) =>
                        {
                            activity.SetTag("url.query", null);
                            activity.SetTag("url.path", RequestRouteTemplate.Unmatched);
                            activity.SetTag("http.target", RequestRouteTemplate.Unmatched);
                        };
                        options.EnrichWithHttpResponse = static (activity, response) =>
                        {
                            string route = RequestRouteTemplate.Get(response.HttpContext);
                            activity.SetTag("url.path", route);
                            activity.SetTag("http.target", route);
                        };
                    })
                    .AddHttpClientInstrumentation(options =>
                    {
                        // Product searches and barcodes can occur in outbound URL paths or query strings.
                        // Keep only the remote authority in exported spans; request-level content is private.
                        options.EnrichWithHttpRequestMessage = static (activity, request) =>
                        {
                            Uri? uri = request.RequestUri;
                            if (uri is null) return;
                            string authority = uri.GetLeftPart(UriPartial.Authority) + "/";
                            activity.SetTag("url.full", authority);
                            activity.SetTag("http.url", authority);
                            activity.SetTag("url.path", "/");
                            activity.SetTag("url.query", null);
                            activity.SetTag("http.target", "/");
                        };
                    });
            });

        if (!string.IsNullOrWhiteSpace(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]))
        {
            openTelemetry.UseOtlpExporter();
        }
    }
}
