using Microsoft.AspNetCore.Diagnostics;

namespace Gainer.Api.Errors;

internal sealed class UnexpectedExceptionHandler(ILogger<UnexpectedExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        logger.UnexpectedRequestFailure(
            exception.GetType().Name,
            ProblemDetailsConfiguration.GetCorrelationId(httpContext),
            System.Diagnostics.Activity.Current?.TraceId.ToString() ?? httpContext.TraceIdentifier,
            exception);

        httpContext.Response.StatusCode = StatusCodes.Status500InternalServerError;
        await Results.Problem(
                statusCode: StatusCodes.Status500InternalServerError,
                title: ProblemDetailsConfiguration.GetTitle(StatusCodes.Status500InternalServerError))
            .ExecuteAsync(httpContext);

        return true;
    }
}

internal static partial class UnexpectedExceptionLog
{
    [LoggerMessage(
        EventId = 1001,
        Level = LogLevel.Error,
        Message = "Unhandled request failure of type {ExceptionType}; correlation {CorrelationId}; trace {TraceId}")]
    public static partial void UnexpectedRequestFailure(
        this ILogger logger,
        string exceptionType,
        string correlationId,
        string traceId,
        Exception exception);
}
