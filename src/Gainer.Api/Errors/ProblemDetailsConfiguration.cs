using Gainer.Api.Composition;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Errors;

internal static class ProblemDetailsConfiguration
{
    private const string CorrelationIdItem = "Gainer.CorrelationId";

    public static void Customize(ProblemDetailsContext context)
    {
        ProblemDetails problemDetails = context.ProblemDetails;
        int statusCode = problemDetails.Status ?? context.HttpContext.Response.StatusCode;
        problemDetails.Status = statusCode;
        problemDetails.Title ??= GetTitle(statusCode);
        problemDetails.Type ??= GetTypeUri(statusCode);
        problemDetails.Detail = null;
        AddStableExtensions(context.HttpContext, problemDetails);
    }

    public static void AddStableExtensions(HttpContext httpContext, ProblemDetails problemDetails)
    {
        int statusCode = problemDetails.Status ?? httpContext.Response.StatusCode;
        problemDetails.Extensions["code"] = GetCode(statusCode);
        problemDetails.Extensions["traceId"] = GetTraceId(httpContext);
        problemDetails.Extensions["correlationId"] = GetCorrelationId(httpContext);
    }

    public static string GetTitle(int statusCode) => statusCode switch
    {
        StatusCodes.Status400BadRequest => "The request is invalid.",
        StatusCodes.Status401Unauthorized => "Authentication is required.",
        StatusCodes.Status403Forbidden => "Access is forbidden.",
        StatusCodes.Status404NotFound => "The requested resource was not found.",
        StatusCodes.Status409Conflict => "The request conflicts with the current state.",
        StatusCodes.Status413PayloadTooLarge => "The request body is too large.",
        StatusCodes.Status422UnprocessableEntity => "The request cannot be processed.",
        StatusCodes.Status429TooManyRequests => "Too many requests.",
        _ when statusCode >= StatusCodes.Status500InternalServerError => "An unexpected error occurred.",
        _ => "The request could not be completed.",
    };

    public static string GetTypeUri(int statusCode) => $"https://httpstatuses.com/{statusCode}";

    public static string GetCorrelationId(HttpContext httpContext) =>
        httpContext.Items.TryGetValue(CorrelationIdItem, out object? value) && value is string correlationId
            ? correlationId
            : httpContext.TraceIdentifier;

    public static void SetCorrelationId(HttpContext httpContext, string correlationId) =>
        httpContext.Items[CorrelationIdItem] = correlationId;

    private static string GetCode(int statusCode) => statusCode switch
    {
        StatusCodes.Status400BadRequest => "validation_failed",
        StatusCodes.Status401Unauthorized => "authentication_required",
        StatusCodes.Status403Forbidden => "forbidden",
        StatusCodes.Status404NotFound => "resource_not_found",
        StatusCodes.Status409Conflict => "conflict",
        StatusCodes.Status413PayloadTooLarge => "request_too_large",
        StatusCodes.Status422UnprocessableEntity => "validation_failed",
        StatusCodes.Status429TooManyRequests => "rate_limited",
        _ when statusCode >= StatusCodes.Status500InternalServerError => "unexpected_error",
        _ => "request_failed",
    };

    private static string GetTraceId(HttpContext httpContext) =>
        System.Diagnostics.Activity.Current?.TraceId.ToString() ?? httpContext.TraceIdentifier;
}
