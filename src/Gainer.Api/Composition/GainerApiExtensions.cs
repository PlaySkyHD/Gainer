using Gainer.Api.Errors;
using Gainer.Api.Middleware;
using Gainer.Api.Controllers;
using Gainer.Api.Security;
using Gainer.Core.Security;
using Gainer.Infrastructure.Integrations;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection.Extensions;
using System.Threading.RateLimiting;
using System.Security.Claims;

namespace Gainer.Api.Composition;

/// <summary>Registers and maps the versioned Gainer HTTP API.</summary>
public static class GainerApiExtensions
{
    private const string ReadinessPath = "/health/ready";

    private static readonly string[] TrustedProxyNetworks =
        ["127.0.0.0/8", "::1/128", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7"];

    /// <summary>Adds the API composition-root services.</summary>
    public static WebApplicationBuilder AddGainerApi(this WebApplicationBuilder builder)
    {
        builder.WebHost.ConfigureKestrel(options =>
            options.Limits.MaxRequestBodySize = ApiConstants.MaximumRequestBodyBytes);
        builder.Services.Configure<FormOptions>(options =>
            options.MultipartBodyLengthLimit = ApiConstants.MaximumRequestBodyBytes);
        builder.Services.Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders = ForwardedHeaders.XForwardedFor |
                ForwardedHeaders.XForwardedHost |
                ForwardedHeaders.XForwardedProto;
            options.ForwardLimit = 2;
            // Only the private Compose networks and loopback may forward. The first public
            // address in X-Forwarded-For is the client that host Caddy saw.
            options.KnownIPNetworks.Clear();
            options.KnownProxies.Clear();
            foreach (string network in TrustedProxyNetworks)
            {
                options.KnownIPNetworks.Add(System.Net.IPNetwork.Parse(network));
            }
            options.AllowedHosts.Add("gainer.markfort.xyz");
        });
        builder.Services.AddExceptionHandler<UnexpectedExceptionHandler>();
        builder.Services.AddProblemDetails(options =>
            options.CustomizeProblemDetails = ProblemDetailsConfiguration.Customize);
        builder.Services.AddOpenApi("v1", options => options.AddGainerTransformers());
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
                context.Request.Path.StartsWithSegments(ReadinessPath)
                    ? PerClientWindow(context, "readiness", permitLimit: 30)
                    : RateLimitPartition.GetNoLimiter(string.Empty));
            options.AddPolicy("coach", context => RateLimitPartition.GetFixedWindowLimiter(
                $"{context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "anonymous"}:{context.Connection.RemoteIpAddress}",
                _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 10,
                    Window = TimeSpan.FromMinutes(1),
                    QueueLimit = 0,
                    AutoReplenishment = true,
                }));
            options.AddPolicy(
                ApiConstants.AuthenticationRateLimitPolicy,
                context => PerClientWindow(context, ApiConstants.AuthenticationRateLimitPolicy, permitLimit: 30));
            options.AddPolicy(
                ApiConstants.SystemStatusRateLimitPolicy,
                context => PerClientWindow(context, ApiConstants.SystemStatusRateLimitPolicy, permitLimit: 60));
            options.AddPolicy(ApiConstants.AccountExportRateLimitPolicy, context => RateLimitPartition.GetFixedWindowLimiter(
                $"{ApiConstants.AccountExportRateLimitPolicy}:{context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? context.Connection.RemoteIpAddress?.ToString() ?? "unknown"}",
                _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 5,
                    Window = TimeSpan.FromMinutes(15),
                    QueueLimit = 0,
                    AutoReplenishment = true,
                }));
            options.AddPolicy(
                ApiConstants.TokenRefreshRateLimitPolicy,
                context => PerClientWindow(context, ApiConstants.TokenRefreshRateLimitPolicy, permitLimit: 60));
        });
        builder.Services.AddScoped<IUserContext, HttpUserContext>();
        // Also registered by the persistence module; the API needs them for the user context and the worker.
        builder.Services.TryAddScoped<BackgroundUserScope>();
        builder.Services.TryAddSingleton<StravaExportSignal>();
        builder.Services.AddOptions<StravaOptions>();
        builder.Services.AddHostedService<StravaExportWorker>();
        builder.Services.TryAddSingleton(TimeProvider.System);
        builder.Services
            .AddControllers()
            .AddApplicationPart(typeof(SystemController).Assembly)
            .ConfigureApiBehaviorOptions(ConfigureApiBehavior);

        return builder;
    }

    /// <summary>Maps middleware and controllers for the versioned API.</summary>
    public static WebApplication MapGainerApi(this WebApplication app)
    {
        // The API is reachable only from the private Compose network. The two trusted hops are
        // the loopback-bound Gainer edge and the VPS host Caddy that owns public HTTPS; the edge
        // keeps the client address host Caddy appended (trusted_proxies in deploy/Caddyfile).
        app.UseForwardedHeaders();
        app.UseMiddleware<CorrelationIdMiddleware>();
        app.UseExceptionHandler();
        // Before authentication, the rate limiter and authorization: they end the request with a bare
        // 401, 403 or 429, and only status code pages wrap them into ProblemDetails with a stable code.
        app.UseStatusCodePages(async statusCodeContext =>
        {
            HttpContext httpContext = statusCodeContext.HttpContext;
            await Results.Problem(
                    statusCode: httpContext.Response.StatusCode,
                    title: ProblemDetailsConfiguration.GetTitle(httpContext.Response.StatusCode))
                .ExecuteAsync(httpContext);
        });
        app.UseMiddleware<RequestSizeLimitMiddleware>();
        app.UseAuthentication();
        app.UseMiddleware<DeviceSessionValidationMiddleware>();
        app.UseRateLimiter();
        app.UseAuthorization();
        app.MapControllers();

        return app;
    }

    private static RateLimitPartition<string> PerClientWindow(HttpContext context, string scope, int permitLimit) =>
        RateLimitPartition.GetFixedWindowLimiter(
            $"{scope}:{context.Connection.RemoteIpAddress?.ToString() ?? "unknown"}",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = permitLimit,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true,
            });

    private static void ConfigureApiBehavior(ApiBehaviorOptions options)
    {
        options.InvalidModelStateResponseFactory = context =>
        {
            ValidationProblemDetails problemDetails = new(context.ModelState)
            {
                Status = StatusCodes.Status400BadRequest,
                Title = ProblemDetailsConfiguration.GetTitle(StatusCodes.Status400BadRequest),
                Type = ProblemDetailsConfiguration.GetTypeUri(StatusCodes.Status400BadRequest),
            };
            ProblemDetailsConfiguration.AddStableExtensions(context.HttpContext, problemDetails);

            return new BadRequestObjectResult(problemDetails)
            {
                ContentTypes = { "application/problem+json" },
            };
        };
    }
}
