using Gainer.Core.Integrations;
using Gainer.Core.Training;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Npgsql;

namespace Gainer.Infrastructure.Integrations;

/// <summary>
/// One export pass for the user of the current scope: queue new records of the switched-on kinds,
/// send due entries and check uploads Strava is still processing.
/// </summary>
public sealed class StravaExportProcessor(
    AppDbContext context,
    IStravaApiClient strava,
    StravaTokenVault tokens,
    IOptions<StravaOptions> options,
    TimeProvider timeProvider,
    ILogger<StravaExportProcessor> logger)
{
    public const int MaximumAttempts = 6;
    public const int MaximumProcessingChecks = 30;
    public const int EntriesPerPass = 5;
    private const int QueuedPerPass = 20;
    private static readonly TimeSpan RateLimitPause = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan ProcessingCheckDelay = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan[] RetryDelays =
        [TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(15), TimeSpan.FromMinutes(60)];

    private readonly StravaOptions settings = options.Value;

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        StravaConnection? connection = await context.StravaConnections.SingleOrDefaultAsync(cancellationToken);
        DateTime utcNow = Now();
        if (connection is null || connection.NeedsReconnect || connection.PausedUntilUtc > utcNow)
        {
            return;
        }

        await QueueAsync(connection, utcNow, cancellationToken);
        StravaExport[] due = await context.StravaExports
            .Where(item => item.AthleteId == connection.AthleteId &&
                (item.Status == StravaExportStatus.Pending || item.Status == StravaExportStatus.Processing) &&
                item.NextAttemptAtUtc <= utcNow)
            .OrderBy(item => item.NextAttemptAtUtc)
            .Take(EntriesPerPass)
            .ToArrayAsync(cancellationToken);
        if (due.Length == 0) return;

        string accessToken;
        try
        {
            accessToken = await tokens.AccessTokenAsync(connection, cancellationToken);
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (StravaApiException exception)
        {
            HandleConnectionFailure(connection, exception);
            await context.SaveChangesAsync(cancellationToken);
            return;
        }

        foreach (StravaExport export in due)
        {
            try
            {
                await ProcessAsync(export, accessToken, cancellationToken);
            }
            catch (StravaApiException exception) when (exception.Failure is StravaFailure.Unauthorized or StravaFailure.RateLimited)
            {
                HandleConnectionFailure(connection, exception);
                await context.SaveChangesAsync(cancellationToken);
                return;
            }
            catch (StravaApiException exception) when (exception.Failure == StravaFailure.Transient)
            {
                Retry(export, "strava_unavailable");
            }
            catch (StravaApiException exception)
            {
                logger.LogWarning(exception, "Strava rejected export {ExportId} with status {Status}.", export.Id, exception.StatusCode);
                Fail(export, "strava_rejected");
            }
            await context.SaveChangesAsync(cancellationToken);
        }
    }

    private async Task QueueAsync(StravaConnection connection, DateTime utcNow, CancellationToken cancellationToken)
    {
        DateTime settledBefore = utcNow - TimeSpan.FromSeconds(settings.SettleSeconds);
        long athleteId = connection.AthleteId;
        var queued = new List<(StravaExportKind Kind, Guid Id)>();
        if (connection.CardioExportSinceUtc is { } cardioSince)
        {
            Guid[] ids = await context.CardioSessions
                .Where(item => item.EndedAtUtc >= cardioSince && item.UpdatedAtUtc <= settledBefore)
                .Where(item => !context.StravaExports.Any(export =>
                    export.Kind == StravaExportKind.Cardio && export.ResourceId == item.Id && export.AthleteId == athleteId))
                .OrderBy(item => item.EndedAtUtc)
                .Select(item => item.Id)
                .Take(QueuedPerPass)
                .ToArrayAsync(cancellationToken);
            queued.AddRange(ids.Select(id => (StravaExportKind.Cardio, id)));
        }
        if (connection.StrengthExportSinceUtc is { } strengthSince)
        {
            Guid[] ids = await context.Workouts
                .Where(item => item.DeletedAtUtc == null && item.EndedAtUtc != null &&
                    item.EndedAtUtc >= strengthSince && item.UpdatedAtUtc <= settledBefore)
                .Where(item => !context.StravaExports.Any(export =>
                    export.Kind == StravaExportKind.Strength && export.ResourceId == item.Id && export.AthleteId == athleteId))
                .OrderBy(item => item.EndedAtUtc)
                .Select(item => item.Id)
                .Take(QueuedPerPass)
                .ToArrayAsync(cancellationToken);
            queued.AddRange(ids.Select(id => (StravaExportKind.Strength, id)));
        }
        if (queued.Count == 0) return;

        foreach ((StravaExportKind kind, Guid id) in queued)
        {
            context.StravaExports.Add(new StravaExport
            {
                Id = Guid.NewGuid(),
                Kind = kind,
                ResourceId = id,
                AthleteId = athleteId,
                Status = StravaExportStatus.Pending,
                NextAttemptAtUtc = utcNow,
                CreatedAtUtc = utcNow,
                UpdatedAtUtc = utcNow,
            });
        }
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            // A manual request queued one of them meanwhile; the next pass picks up the rest.
            foreach (var entry in context.ChangeTracker.Entries<StravaExport>().Where(entry => entry.State == EntityState.Added).ToArray())
            {
                entry.State = EntityState.Detached;
            }
        }
    }

    private async Task ProcessAsync(StravaExport export, string accessToken, CancellationToken cancellationToken)
    {
        if (export.Status == StravaExportStatus.Processing)
        {
            if (export.ActivityId is { } activityId)
            {
                // Uploaded; only the activity type is still missing.
                await FinishAsync(export, activityId, accessToken, cancellationToken);
                return;
            }
            if (export.UploadId is not { } uploadId)
            {
                export.Status = StravaExportStatus.Pending;
                return;
            }
            StravaUploadState state = await strava.GetUploadAsync(accessToken, uploadId, cancellationToken);
            await ApplyAsync(export, state, accessToken, cancellationToken);
            return;
        }

        StravaUpload? upload = await BuildAsync(export, cancellationToken);
        if (upload is null)
        {
            // Deleted before it was sent.
            context.StravaExports.Remove(export);
            return;
        }
        StravaUploadState uploaded = await strava.UploadAsync(accessToken, upload, cancellationToken);
        export.Attempts = 0;
        await ApplyAsync(export, uploaded, accessToken, cancellationToken);
    }

    private async Task ApplyAsync(StravaExport export, StravaUploadState state, string accessToken, CancellationToken cancellationToken)
    {
        export.UploadId = state.UploadId;
        export.UpdatedAtUtc = Now();
        if (state.DuplicateOfActivityId is { } duplicate)
        {
            Complete(export, duplicate);
            return;
        }
        if (state.Error is not null)
        {
            logger.LogWarning("Strava could not process upload {UploadId} of export {ExportId}.", state.UploadId, export.Id);
            Fail(export, "strava_upload_error");
            return;
        }
        if (state.ActivityId is { } activityId)
        {
            export.ActivityId = activityId;
            await FinishAsync(export, activityId, accessToken, cancellationToken);
            return;
        }
        export.Status = StravaExportStatus.Processing;
        export.Attempts++;
        if (export.Attempts > MaximumProcessingChecks)
        {
            Fail(export, "strava_processing_timeout");
            return;
        }
        export.NextAttemptAtUtc = Now() + ProcessingCheckDelay;
    }

    private async Task FinishAsync(StravaExport export, long activityId, string accessToken, CancellationToken cancellationToken)
    {
        if (export.Kind == StravaExportKind.Strength)
        {
            try
            {
                await strava.SetSportTypeAsync(accessToken, activityId, "WeightTraining", cancellationToken);
            }
            catch (StravaApiException exception) when (exception.Failure == StravaFailure.Transient)
            {
                export.Status = StravaExportStatus.Processing;
                Retry(export, "strava_unavailable");
                return;
            }
            catch (StravaApiException exception) when (exception.Failure == StravaFailure.Rejected)
            {
                // The activity exists; a wrong type is not worth a duplicate.
                logger.LogWarning(exception, "Strava refused the activity type of export {ExportId}.", export.Id);
            }
        }
        Complete(export, activityId);
    }

    private async Task<StravaUpload?> BuildAsync(StravaExport export, CancellationToken cancellationToken)
    {
        if (export.Kind == StravaExportKind.Cardio)
        {
            CardioSession? session = await context.CardioSessions.AsNoTracking()
                .SingleOrDefaultAsync(item => item.Id == export.ResourceId, cancellationToken);
            return session is null ? null : StravaActivityContent.ForCardio(session);
        }

        Workout? workout = await context.Workouts.AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == export.ResourceId && item.DeletedAtUtc == null && item.EndedAtUtc != null, cancellationToken);
        if (workout is null) return null;
        WorkoutExercise[] exercises = await context.WorkoutExercises.AsNoTracking()
            .Where(item => item.WorkoutId == workout.Id)
            .OrderBy(item => item.Position)
            .ToArrayAsync(cancellationToken);
        ILookup<Guid, WorkoutSet> sets = (await context.WorkoutSets.AsNoTracking()
                .Where(item => item.WorkoutId == workout.Id)
                .OrderBy(item => item.Position)
                .ToArrayAsync(cancellationToken))
            .ToLookup(item => item.WorkoutExerciseId);
        return StravaActivityContent.ForStrength(
            workout,
            exercises.Select(exercise => new StravaStrengthExercise(
                exercise.ExerciseNameSnapshot,
                sets[exercise.Id].Select(set => new StravaStrengthSet(set.SetType, set.WeightKg, set.Repetitions)).ToArray()))
            .ToArray());
    }

    private void HandleConnectionFailure(StravaConnection connection, StravaApiException exception)
    {
        DateTime utcNow = Now();
        switch (exception.Failure)
        {
            case StravaFailure.Unauthorized:
                logger.LogInformation("Strava rejected the tokens; the user has to connect again.");
                connection.NeedsReconnect = true;
                break;
            case StravaFailure.RateLimited:
                connection.PausedUntilUtc = utcNow + RateLimitPause;
                break;
            default:
                connection.PausedUntilUtc = utcNow + RetryDelays[0];
                break;
        }
        connection.UpdatedAtUtc = utcNow;
    }

    private void Retry(StravaExport export, string code)
    {
        export.Attempts++;
        export.LastErrorCode = code;
        export.UpdatedAtUtc = Now();
        if (export.Attempts >= MaximumAttempts)
        {
            Fail(export, code);
            return;
        }
        export.NextAttemptAtUtc = Now() + RetryDelays[Math.Min(export.Attempts - 1, RetryDelays.Length - 1)];
    }

    private void Complete(StravaExport export, long activityId)
    {
        export.Status = StravaExportStatus.Completed;
        export.ActivityId = activityId;
        export.LastErrorCode = null;
        export.UpdatedAtUtc = Now();
    }

    private void Fail(StravaExport export, string code)
    {
        export.Status = StravaExportStatus.Failed;
        export.LastErrorCode = code;
        export.UpdatedAtUtc = Now();
    }

    private DateTime Now() => timeProvider.GetUtcNow().UtcDateTime;
}
