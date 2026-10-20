using Gainer.Api.Errors;
using Gainer.Api.Middleware;
using Gainer.Api.Controllers;
using Gainer.Api.Security;
using Gainer.Core.Security;
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
            options.KnownIPNetworks.Clear();
            options.KnownProxies.Clear();
            options.AllowedHosts.Add("gainer.markfort.xyz");
        });
        builder.Services.AddExceptionHandler<UnexpectedExceptionHandler>();
        builder.Services.AddProblemDetails(options =>
            options.CustomizeProblemDetails = ProblemDetailsConfiguration.Customize);
        builder.Services.AddOpenApi("v1");
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.AddPolicy("coach", context => RateLimitPartition.GetFixedWindowLimiter(
                $"{context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "anonymous"}:{context.Connection.RemoteIpAddress}",
                _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 10,
                    Window = TimeSpan.FromMinutes(1),
                    QueueLimit = 0,
                    AutoReplenishment = true,
                }));
            options.AddPolicy(ApiConstants.AuthenticationRateLimitPolicy, context => RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 30,
                    Window = TimeSpan.FromMinutes(1),
                    QueueLimit = 0,
                    AutoReplenishment = true,
                }));
        });
        builder.Services.AddScoped<IUserContext, HttpUserContext>();
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
        // the loopback-bound Gainer edge and the VPS host Caddy that owns public HTTPS.
        app.UseForwardedHeaders();
        app.UseMiddleware<CorrelationIdMiddleware>();
        app.UseExceptionHandler();
        app.UseMiddleware<RequestSizeLimitMiddleware>();
        app.UseAuthentication();
        app.UseMiddleware<DeviceSessionValidationMiddleware>();
        app.UseRateLimiter();
        app.UseAuthorization();
        app.UseStatusCodePages(async statusCodeContext =>
        {
            HttpContext httpContext = statusCodeContext.HttpContext;
            await Results.Problem(
                    statusCode: httpContext.Response.StatusCode,
                    title: ProblemDetailsConfiguration.GetTitle(httpContext.Response.StatusCode))
                .ExecuteAsync(httpContext);
        });
        app.MapControllers();

        return app;
    }

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
