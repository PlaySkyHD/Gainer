using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace Gainer.ServiceDefaults;

/// <summary>
/// Resolves the route template of a request. Logs and traces use it instead of the path,
/// because paths carry barcodes and dates that belong to the user.
/// </summary>
public static class RequestRouteTemplate
{
    /// <summary>Placeholder for requests that matched no route; the raw path is never used.</summary>
    public const string Unmatched = "unmatched";

    /// <summary>Returns the route pattern of the matched endpoint, or <see cref="Unmatched"/>.</summary>
    public static string Get(HttpContext context) =>
        (context.GetEndpoint() as RouteEndpoint)?.RoutePattern.RawText ?? Unmatched;
}
