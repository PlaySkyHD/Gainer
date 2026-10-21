using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Gainer.Infrastructure.Integrations;

/// <summary>
/// Runs the Strava export in the API process. Each user is handled in a scope bound to that user,
/// so the isolation filters apply; only the list of connected users is read across users.
/// </summary>
public sealed class StravaExportWorker(
    IServiceScopeFactory scopes,
    StravaExportSignal signal,
    IOptions<StravaOptions> options,
    TimeProvider timeProvider,
    ILogger<StravaExportWorker> logger) : BackgroundService
{
    private readonly StravaOptions settings = options.Value;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!settings.IsConfigured)
        {
            logger.LogInformation("Strava is not configured; the export worker is idle.");
            return;
        }
        TimeSpan interval = TimeSpan.FromSeconds(Math.Max(5, settings.WorkerIntervalSeconds));
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunOnceAsync(stoppingToken);
                await signal.WaitAsync(interval, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "The Strava export pass failed.");
                await Task.Delay(interval, timeProvider, stoppingToken).ConfigureAwait(ConfigureAwaitOptions.SuppressThrowing);
            }
        }
    }

    public async Task RunOnceAsync(CancellationToken cancellationToken)
    {
        Guid[] userIds;
        await using (AsyncServiceScope scope = scopes.CreateAsyncScope())
        {
            AppDbContext context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
            userIds = await context.StravaConnections
                .IgnoreQueryFilters()
                .Where(item => !item.NeedsReconnect && (item.PausedUntilUtc == null || item.PausedUntilUtc <= utcNow))
                .Select(item => item.UserId)
                .ToArrayAsync(cancellationToken);
        }

        foreach (Guid userId in userIds)
        {
            await using AsyncServiceScope userScope = scopes.CreateAsyncScope();
            userScope.ServiceProvider.GetRequiredService<BackgroundUserScope>().Enter(userId);
            try
            {
                await userScope.ServiceProvider.GetRequiredService<StravaExportProcessor>().RunAsync(cancellationToken);
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                logger.LogError(exception, "The Strava export failed for one user.");
            }
        }
    }
}
