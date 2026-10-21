namespace Gainer.Infrastructure.Integrations;

/// <summary>Wakes the export worker early, e.g. after a manual export request.</summary>
public sealed class StravaExportSignal
{
    private readonly SemaphoreSlim signal = new(0, 1);

    public void Notify()
    {
        try
        {
            signal.Release();
        }
        catch (SemaphoreFullException)
        {
            // Already signalled.
        }
    }

    /// <summary>Completes after <paramref name="interval" /> or earlier when notified.</summary>
    public Task WaitAsync(TimeSpan interval, CancellationToken cancellationToken) => signal.WaitAsync(interval, cancellationToken);
}
