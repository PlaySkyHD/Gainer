using System.Collections.Concurrent;

namespace Gainer.Infrastructure.Coach;

/// <summary>Per-user daily request budget plus a shared concurrency limit for AI calls.</summary>
internal sealed class DailyRequestQuota(int dailyRequestsPerUser, int maximumConcurrentRequests, TimeProvider timeProvider)
    : IDisposable
{
    private readonly ConcurrentDictionary<Guid, DailyUsage> usage = new();
    private readonly SemaphoreSlim concurrency = new(maximumConcurrentRequests);

    public async ValueTask<IAsyncDisposable> AcquireAsync(
        Guid userId,
        Func<Exception> exhausted,
        CancellationToken cancellationToken = default)
    {
        if (userId == Guid.Empty) throw new UnauthorizedAccessException("An authenticated user is required.");
        DateOnly today = DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime);
        DailyUsage current = usage.AddOrUpdate(
            userId,
            _ => new DailyUsage(today, 1),
            (_, existing) => existing.Date == today
                ? existing with { Requests = checked(existing.Requests + 1) }
                : new DailyUsage(today, 1));
        if (current.Requests > dailyRequestsPerUser) throw exhausted();

        await concurrency.WaitAsync(cancellationToken);
        return new Lease(concurrency);
    }

    public void Dispose() => concurrency.Dispose();

    private sealed record DailyUsage(DateOnly Date, int Requests);

    private sealed class Lease(SemaphoreSlim semaphore) : IAsyncDisposable
    {
        private int disposed;
        public ValueTask DisposeAsync()
        {
            if (Interlocked.Exchange(ref disposed, 1) == 0) semaphore.Release();
            return ValueTask.CompletedTask;
        }
    }
}
