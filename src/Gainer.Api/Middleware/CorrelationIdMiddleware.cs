using System.Diagnostics;
using Gainer.Api.Composition;
using Gainer.Api.Errors;
using Gainer.ServiceDefaults;
using Microsoft.Extensions.Primitives;

namespace Gainer.Api.Middleware;

internal sealed class CorrelationIdMiddleware(RequestDelegate next, ILogger<CorrelationIdMiddleware> logger)
{
    private const int MaximumCorrelationIdLength = 64;

    public async Task InvokeAsync(HttpContext context)
    {
        string correlationId = GetCorrelationId(context.Request.Headers[ApiConstants.CorrelationIdHeader]);
        string traceId = Activity.Current?.TraceId.ToString() ?? context.TraceIdentifier;

        ProblemDetailsConfiguration.SetCorrelationId(context, correlationId);
        Activity.Current?.SetTag("correlation.id", correlationId);
        context.Response.Headers[ApiConstants.CorrelationIdHeader] = correlationId;
        context.Response.Headers[ApiConstants.TraceIdHeader] = traceId;

        long startedAt = Stopwatch.GetTimestamp();
        try
        {
            await next(context);
        }
        finally
        {
            if (logger.IsEnabled(LogLevel.Information))
            {
                logger.RequestCompleted(
                    context.Request.Method,
                    // Route template, not the path: barcodes and dates in the path are private.
                    RequestRouteTemplate.Get(context),
                    context.Response.StatusCode,
                    Stopwatch.GetElapsedTime(startedAt).TotalMilliseconds,
                    correlationId,
                    traceId);
            }
        }
    }

    private static string GetCorrelationId(StringValues suppliedValues)
    {
        string? supplied = suppliedValues.Count == 1 ? suppliedValues[0] : null;
        if (supplied is not null && IsValid(supplied))
        {
            return supplied;
        }

        return Guid.NewGuid().ToString("N");
    }

    private static bool IsValid(string value) =>
        value is { Length: > 0 and <= MaximumCorrelationIdLength }
        && value.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.');
}

internal static partial class RequestLog
{
    [LoggerMessage(
        EventId = 1000,
        Level = LogLevel.Information,
        Message = "HTTP {Method} {Route} completed {StatusCode} in {ElapsedMilliseconds} ms; correlation {CorrelationId}; trace {TraceId}")]
    public static partial void RequestCompleted(
        this ILogger logger,
        string method,
        string route,
        int statusCode,
        double elapsedMilliseconds,
        string correlationId,
        string traceId);
}
