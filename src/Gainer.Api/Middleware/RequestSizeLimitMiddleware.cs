using Gainer.Api.Composition;
using Gainer.Api.Errors;
using Microsoft.AspNetCore.Http.Metadata;

namespace Gainer.Api.Middleware;

internal sealed class RequestSizeLimitMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        // Endpoints such as the meal photo upload declare a larger limit with [RequestSizeLimit].
        long limit = context.GetEndpoint()?.Metadata.GetMetadata<IRequestSizeLimitMetadata>()?.MaxRequestBodySize
            ?? ApiConstants.MaximumRequestBodyBytes;
        if (context.Request.ContentLength > limit)
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
