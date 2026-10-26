using Gainer.Api.Errors;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

/// <summary>
/// ProblemDetails with a stable <c>code</c> extension, shared by the sync and operator controllers.
/// Carries <c>traceId</c> and <c>correlationId</c> like every other problem response.
/// </summary>
internal static class SyncProblemResults
{
    internal static ObjectResult Create(HttpContext httpContext, int status, string code, string title)
    {
        var problem = new ProblemDetails
        {
            Status = status,
            Title = title,
            Type = $"https://gainer.local/problems/{code}",
        };
        ProblemDetailsConfiguration.AddStableExtensions(httpContext, problem);
        problem.Extensions["code"] = code;
        return new ObjectResult(problem)
        {
            StatusCode = status,
            ContentTypes = { "application/problem+json" },
        };
    }
}
