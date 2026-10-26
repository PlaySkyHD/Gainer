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
    private readonly Dictionary<string, SharedCall> inFlight = new(StringComparer.Ordinal);
    private readonly object gate = new();

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
    /// Runs <paramref name="factory"/> once for concurrent callers with the same key. The shared call gets its own
    /// token: a caller whose token is cancelled only stops waiting, and the call is cancelled once every waiter is gone.
    /// The key is freed when the call ends or is abandoned, so a later caller never joins a cancelled call.
    /// </summary>
    internal async Task<T> DeduplicateAsync<T>(string key, Func<CancellationToken, Task<T>> factory, CancellationToken cancellationToken) where T : class
    {
        SharedCall call;
        lock (gate)
        {
            if (!inFlight.TryGetValue(key, out call!))
            {
                call = new SharedCall();
                inFlight[key] = call;
                call.Task = RunAsync(key, call, factory);
            }
            call.Waiters++;
        }
        try
        {
            return (T)await call.Task.WaitAsync(cancellationToken);
        }
        finally
        {
            bool abandoned;
            lock (gate)
            {
                abandoned = --call.Waiters == 0 && !call.Task.IsCompleted;
                if (abandoned) Release(key, call);
            }
            if (abandoned)
            {
                // Outside the lock: cancellation callbacks run synchronously.
                try { call.Cancellation.Cancel(); }
                catch (ObjectDisposedException) { } // the call finished in the meantime
                _ = call.Task.ContinueWith(static task => task.Exception, TaskScheduler.Default); // nobody awaits it any more
            }
        }
    }

    private async Task<object> RunAsync<T>(string key, SharedCall call, Func<CancellationToken, Task<T>> factory) where T : class
    {
        try
        {
            return await factory(call.Cancellation.Token);
        }
        finally
        {
            lock (gate) Release(key, call);
            call.Cancellation.Dispose();
        }
    }

    private void Release(string key, SharedCall call)
    {
        if (inFlight.TryGetValue(key, out SharedCall? current) && ReferenceEquals(current, call)) inFlight.Remove(key);
    }

    private sealed class SharedCall
    {
        public CancellationTokenSource Cancellation { get; } = new();
        public Task<object> Task { get; set; } = null!;
        public int Waiters { get; set; }
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
