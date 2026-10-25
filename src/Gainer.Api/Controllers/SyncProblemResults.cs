using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

/// <summary>ProblemDetails with a stable <c>code</c> extension, shared by the sync controllers.</summary>
internal static class SyncProblemResults
{
    internal static ObjectResult Create(int status, string code, string title)
    {
        var problem = new ProblemDetails
        {
            Status = status,
            Title = title,
            Type = $"https://gainer.local/problems/{code}",
        };
        problem.Extensions["code"] = code;
        return new ObjectResult(problem) { StatusCode = status };
    }
}
