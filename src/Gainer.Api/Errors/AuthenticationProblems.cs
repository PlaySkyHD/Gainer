using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Errors;

/// <summary>Problem responses with a stable <c>code</c> for sign-in and passkey endpoints.</summary>
internal static class AuthenticationProblems
{
    /// <summary>A failed sign-in; the title never reveals why.</summary>
    public static ObjectResult Unauthorized(HttpContext httpContext, string code) =>
        Create(httpContext, StatusCodes.Status401Unauthorized, "Authentication failed.", code);

    /// <summary>A rejected passkey registration.</summary>
    public static ObjectResult BadRequest(HttpContext httpContext, string title, string code) =>
        Create(httpContext, StatusCodes.Status400BadRequest, title, code);

    /// <summary>The signed-in account must confirm itself again.</summary>
    public static ObjectResult Forbidden(HttpContext httpContext, string title, string code) =>
        Create(httpContext, StatusCodes.Status403Forbidden, title, code);

    private static ObjectResult Create(HttpContext httpContext, int status, string title, string code)
    {
        var problemDetails = new ProblemDetails
        {
            Status = status,
            Title = title,
            Type = ProblemDetailsConfiguration.GetTypeUri(status),
        };
        ProblemDetailsConfiguration.AddStableExtensions(httpContext, problemDetails);
        problemDetails.Extensions["code"] = code;

        return new ObjectResult(problemDetails)
        {
            StatusCode = status,
            ContentTypes = { "application/problem+json" },
        };
    }
}
