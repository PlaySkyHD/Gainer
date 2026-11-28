using System.Security.Claims;
using System.Threading.RateLimiting;
using Gainer.Api.Connectors;
using Gainer.Api.Mcp;
using Gainer.Api.Security;
using Microsoft.AspNetCore.RateLimiting;
using System.Text.Json;
using System.Text.Json.Serialization;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;

namespace Gainer.Api.Composition;

/// <summary>Registers the MCP endpoint and the OAuth pieces for connected assistants.</summary>
public static class GainerConnectorExtensions
{
    /// <summary>Tool results with enum names instead of numbers, so assistants read them without a key.</summary>
    private static readonly JsonSerializerOptions ToolJson = new(McpJsonUtilities.DefaultOptions)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    /// <summary>Rate limit of the MCP endpoint, per account.</summary>
    public const string McpRateLimitPolicy = "mcp";

    /// <summary>
    /// Rate limit of the OAuth token endpoint. Assistants call it from a few shared egress
    /// addresses for all their users, so the per-address window is wider than for app logins.
    /// </summary>
    public const string ConnectorTokenRateLimitPolicy = "connector-token";

    /// <summary>Adds OAuth helpers and the MCP server with its read-only tools.</summary>
    public static IServiceCollection AddGainerConnectors(this IServiceCollection services)
    {
        services.AddOptions<ConnectorOptions>().BindConfiguration(ConnectorOptions.SectionName);
        services.AddMemoryCache();
        services.AddSingleton<ConnectorEndpoints>();
        services.AddSingleton<ConnectorClientRegistry>();
        services.AddSingleton<ConnectorAuthorizationRequests>();
        services.AddSingleton<ConnectorAuthorizationCodes>();
        // Stateless: every tool call runs in the HTTP request that carries its own connector token,
        // never in the context of an earlier request.
        services
            .AddMcpServer(options => options.ServerInfo = new Implementation { Name = "gainer", Version = "1.0.0" })
            .WithHttpTransport(options => options.Stateless = true)
            .WithTools<GainerMcpTools>(ToolJson)
            .WithTools<GainerTrainingTools>(ToolJson)
            .WithTools<GainerStatisticsTools>(ToolJson)
            .WithTools<GainerAnalysisTools>(ToolJson)
            .WithTools<GainerScheduleTools>(ToolJson)
            .WithTools<GainerCardioTools>(ToolJson)
            .WithTools<GainerBodyTools>(ToolJson)
            .WithTools<GainerNutritionTools>(ToolJson)
            .WithTools<GainerAccountTools>(ToolJson);
        return services;
    }

    /// <summary>Limits MCP calls per account and token exchanges per address.</summary>
    public static void AddMcpRateLimit(RateLimiterOptions options)
    {
        options.AddPolicy(ConnectorTokenRateLimitPolicy, context => RateLimitPartition.GetFixedWindowLimiter(
            $"{ConnectorTokenRateLimitPolicy}:{context.Connection.RemoteIpAddress?.ToString() ?? "unknown"}",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 600,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true,
            }));
        options.AddPolicy(McpRateLimitPolicy, context => RateLimitPartition.GetFixedWindowLimiter(
            $"{McpRateLimitPolicy}:{context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? context.Connection.RemoteIpAddress?.ToString() ?? "unknown"}",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true,
            }));
    }

    /// <summary>Maps the MCP endpoint; only connector tokens reach it.</summary>
    public static void MapGainerMcp(this WebApplication app) =>
        app.MapMcp(ConnectorEndpoints.McpPath)
            .RequireAuthorization(ConnectorAuthorization.PolicyName)
            .RequireRateLimiting(McpRateLimitPolicy);

    /// <summary>
    /// Points a rejected MCP client to the protected-resource metadata (RFC 9728), so it can start
    /// the OAuth flow, and marks app tokens as lacking the connector scope.
    /// </summary>
    public static IApplicationBuilder UseMcpChallenge(this IApplicationBuilder app) =>
        app.Use(async (context, next) =>
        {
            if (context.Request.Path.StartsWithSegments(ConnectorEndpoints.McpPath))
            {
                ConnectorEndpoints endpoints = context.RequestServices.GetRequiredService<ConnectorEndpoints>();
                context.Response.OnStarting(() =>
                {
                    string scope = ConnectorAuthorization.OAuthScope;
                    string metadata = endpoints.ResourceMetadata;
                    switch (context.Response.StatusCode)
                    {
                        case StatusCodes.Status401Unauthorized:
                            context.Response.Headers.WWWAuthenticate =
                                $"Bearer resource_metadata=\"{metadata}\", scope=\"{scope}\"";
                            break;
                        case StatusCodes.Status403Forbidden:
                            context.Response.Headers.WWWAuthenticate =
                                $"Bearer error=\"insufficient_scope\", scope=\"{scope}\", resource_metadata=\"{metadata}\"";
                            break;
                    }

                    return Task.CompletedTask;
                });
            }

            await next(context);
        });
}
