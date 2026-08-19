using Gainer.Api.Errors;

namespace Gainer.Api.Security;

/// <summary>Rejects state-changing browser requests that do not originate from the configured frontend.</summary>
internal sealed class RequestOriginMiddleware(
    RequestDelegate next,
    IConfiguration configuration)
{
    public async Task InvokeAsync(HttpContext context)
    {
        if (IsSafeMethod(context.Request.Method) || HasTrustedSource(context.Request))
        {
            await next(context);
            return;
        }

        await Results.Problem(
                statusCode: StatusCodes.Status403Forbidden,
                title: ProblemDetailsConfiguration.GetTitle(StatusCodes.Status403Forbidden))
            .ExecuteAsync(context);
    }

    private bool HasTrustedSource(HttpRequest request)
    {
        string expectedOrigin = GetExpectedOrigin(request);
        if (request.Headers.TryGetValue("Origin", out var originValues))
        {
            return originValues.Count == 1 && OriginsMatch(originValues[0], expectedOrigin);
        }

        if (request.Headers.TryGetValue("Referer", out var refererValues) && refererValues.Count == 1)
        {
            return OriginsMatch(refererValues[0], expectedOrigin);
        }

        return false;
    }

    private string GetExpectedOrigin(HttpRequest request)
    {
        string? configuredOrigin = configuration[GainerRequestSecurityOptions.FrontendOriginConfigurationKey];
        return string.IsNullOrWhiteSpace(configuredOrigin)
            ? $"{request.Scheme}://{request.Host}"
            : configuredOrigin;
    }

    private static bool OriginsMatch(string? candidate, string expected)
    {
        return TryGetOrigin(candidate, out string? candidateOrigin)
            && TryGetOrigin(expected, out string? expectedOrigin)
            && string.Equals(candidateOrigin, expectedOrigin, StringComparison.OrdinalIgnoreCase);
    }

    private static bool TryGetOrigin(string? value, out string? origin)
    {
        origin = null;
        if (!Uri.TryCreate(value, UriKind.Absolute, out Uri? uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            return false;
        }

        origin = uri.GetComponents(UriComponents.SchemeAndServer, UriFormat.UriEscaped);
        return true;
    }

    private static bool IsSafeMethod(string method) =>
        HttpMethods.IsGet(method)
        || HttpMethods.IsHead(method)
        || HttpMethods.IsOptions(method)
        || HttpMethods.IsTrace(method);
}
