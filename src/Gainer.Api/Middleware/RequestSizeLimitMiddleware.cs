using Gainer.Api.Composition;
using Gainer.Api.Errors;

namespace Gainer.Api.Middleware;

internal sealed class RequestSizeLimitMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        if (context.Request.ContentLength > ApiConstants.MaximumRequestBodyBytes)
        {
            context.Response.StatusCode = StatusCodes.Status413PayloadTooLarge;
            await Results.Problem(
                    statusCode: StatusCodes.Status413PayloadTooLarge,
                    title: ProblemDetailsConfiguration.GetTitle(StatusCodes.Status413PayloadTooLarge))
                .ExecuteAsync(context);
            return;
        }

        await next(context);
    }
}
