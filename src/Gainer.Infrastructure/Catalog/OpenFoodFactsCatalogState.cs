using System.Collections.Concurrent;
using System.Diagnostics.CodeAnalysis;
using Microsoft.Extensions.Options;

namespace Gainer.Infrastructure.Catalog;

/// <summary>
/// Process-wide state of the Open Food Facts adapter: response cache, in-flight requests and request budgets.
/// The catalog is a transient typed client, so this state lives in a singleton that every instance shares.
/// </summary>
public sealed class OpenFoodFactsCatalogState(IOptions<OpenFoodFactsOptions> options, TimeProvider timeProvider)
{
    private readonly ConcurrentDictionary<string, CacheEntry> cache = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, Lazy<Task<object>>> inFlight = new(StringComparer.Ordinal);

    internal RequestBudget BarcodeBudget { get; } = new(options.Value.BarcodeRequestsPerMinute, timeProvider);

    internal RequestBudget SearchBudget { get; } = new(options.Value.SearchRequestsPerMinute, timeProvider);

    internal void Store(string key, object value, DateTimeOffset freshUntil, DateTimeOffset staleUntil) =>
        cache[key] = new CacheEntry(value, freshUntil, staleUntil);

    internal bool TryFresh<T>(string key, DateTimeOffset now, [NotNullWhen(true)] out T? value) where T : class
    {
        if (cache.TryGetValue(key, out CacheEntry? entry) && entry.FreshUntil > now && entry.Value is T typed)
        {
            value = typed;
            return true;
        }
        value = null;
        return false;
    }

    internal bool TryStale<T>(string key, DateTimeOffset now, [NotNullWhen(true)] out T? value) where T : class
    {
        if (cache.TryGetValue(key, out CacheEntry? entry) && entry.StaleUntil > now && entry.Value is T typed)
        {
            value = typed;
            return true;
        }
        value = null;
        return false;
    }

    /// <summary>
    /// Runs <paramref name="factory"/> once for concurrent callers with the same key. The shared call must not
    /// depend on one caller's token; each caller only stops waiting when its own token is cancelled.
    /// </summary>
    internal async Task<T> DeduplicateAsync<T>(string key, Func<Task<T>> factory, CancellationToken cancellationToken) where T : class
    {
        Lazy<Task<object>> lazy = inFlight.GetOrAdd(key, _ => new Lazy<Task<object>>(async () => await factory(), LazyThreadSafetyMode.ExecutionAndPublication));
        Task<object> shared = lazy.Value;
        // Free the key when the shared call ends, not when one waiter gives up; otherwise the next caller starts a duplicate request.
        _ = shared.ContinueWith(
            task =>
            {
                _ = task.Exception; // observed by the waiters; marked here so a call nobody waits for raises no unobserved exception
                ((ICollection<KeyValuePair<string, Lazy<Task<object>>>>)inFlight).Remove(new(key, lazy));
            },
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
        return (T)await shared.WaitAsync(cancellationToken);
    }

    private sealed record CacheEntry(object Value, DateTimeOffset FreshUntil, DateTimeOffset StaleUntil);

    internal sealed class RequestBudget(int capacity, TimeProvider timeProvider)
    {
        private readonly Queue<DateTimeOffset> requests = new();
        private readonly object gate = new();

        public bool TryAcquire()
        {
            DateTimeOffset now = timeProvider.GetUtcNow();
            lock (gate)
            {
                while (requests.TryPeek(out DateTimeOffset timestamp) && now - timestamp >= TimeSpan.FromMinutes(1)) requests.Dequeue();
                if (requests.Count >= capacity) return false;
                requests.Enqueue(now);
                return true;
            }
        }
    }
}
