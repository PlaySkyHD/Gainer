using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Http.Resilience;

namespace Gainer.Infrastructure.Http;

/// <summary>
/// Resilience for slow, billed or rate-limited providers (OpenAI, Strava, Open Food Facts). The shared defaults
/// abort after 10 s and repeat requests on 429 and 5xx, which would cancel long model calls, send paid POSTs several
/// times and spend one rate-limit slot on up to four HTTP requests.
/// </summary>
internal static class ExternalProviderHttpResilience
{
    /// <summary>Extra time on top of the client's own timeout, so the client's own timeout fires first and maps its error.</summary>
    private static readonly TimeSpan Margin = TimeSpan.FromSeconds(5);

    /// <summary>
    /// Replaces the default resilience handler with one that never retries and allows each request as long as the
    /// client's configured timeout. The callers own their budgets, stale fallbacks or retry loops, so a hidden retry
    /// would only multiply cost and quota use.
    /// </summary>
    public static IHttpClientBuilder AddProviderResilience(
        this IHttpClientBuilder builder,
        Func<IServiceProvider, int> timeoutSeconds)
    {
        // The pipeline and the client's own timeout bound each request; HttpClient's 100 s default would cut longer ones.
        builder.ConfigureHttpClient(static client => client.Timeout = Timeout.InfiniteTimeSpan);
#pragma warning disable EXTEXP0001 // Experimental, but the only way to replace the handler from ConfigureHttpClientDefaults.
        builder.RemoveAllResilienceHandlers();
#pragma warning restore EXTEXP0001
        builder.AddStandardResilienceHandler().Configure((options, services) =>
        {
            TimeSpan attempt = TimeSpan.FromSeconds(Math.Max(1, timeoutSeconds(services))) + Margin;
            options.Retry.ShouldHandle = static _ => ValueTask.FromResult(false);
            options.AttemptTimeout.Timeout = attempt;
            options.TotalRequestTimeout.Timeout = attempt;
            // The options validation requires the sampling window to be at least twice the attempt timeout.
            options.CircuitBreaker.SamplingDuration = attempt * 2;
        });
        return builder;
    }
}
