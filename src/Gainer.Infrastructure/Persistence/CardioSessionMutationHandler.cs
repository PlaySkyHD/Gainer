using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class CardioSessionMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : ICardioSessionMutationHandler
{
    public async Task<CardioSessionSnapshot> SaveAsync(
        SaveCardioSessionMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        CardioSessionValues values = CardioSessionValidation.Normalize(mutation.Session);
        CardioSession? session = await context.CardioSessions
            .SingleOrDefaultAsync(item => item.Id == values.SessionId, cancellationToken);
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        if (session is null)
        {
            if (mutation.BaseVersion != 0)
            {
                throw new CardioSessionNotFoundException();
            }
            session = new CardioSession
            {
                Id = values.SessionId,
                CreatedAtUtc = utcNow,
                UpdatedAtUtc = utcNow,
                Version = 1,
            };
            Apply(session, values);
            context.CardioSessions.Add(session);
        }
        else
        {
            if (session.Version != mutation.BaseVersion)
            {
                throw new CardioSessionConflictException("The cardio session changed since the supplied base version.");
            }
            Apply(session, values);
            session.UpdatedAtUtc = utcNow;
            session.Version++;
        }

        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new CardioSessionConflictException("The cardio session changed concurrently.");
        }
        catch (DbUpdateException exception) when (context.IsKeyViolation<CardioSession>(exception))
        {
            throw new CardioSessionConflictException("A cardio session already exists for this identifier.");
        }

        CardioSessionSnapshot snapshot = ToSnapshot(session);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<long> DeleteAsync(
        DeleteCardioSessionMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        CardioSession session = await context.CardioSessions
            .SingleOrDefaultAsync(item => item.Id == mutation.SessionId, cancellationToken)
            ?? throw new CardioSessionNotFoundException();
        if (session.Version != mutation.BaseVersion)
        {
            throw new CardioSessionConflictException("The cardio session changed since the supplied base version.");
        }

        long deletedVersion = session.Version + 1;
        context.CardioSessions.Remove(session);
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new CardioSessionConflictException("The cardio session changed concurrently.");
        }
        changeCollector?.CaptureDeletion(ResourceKey.Create(ResourceKind.CardioSession, session.Id), deletedVersion);
        return deletedVersion;
    }

    private Guid CurrentUserId() =>
        userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private static void Apply(CardioSession session, CardioSessionValues values)
    {
        session.ActivityType = values.ActivityType;
        session.StartedAtUtc = values.StartedAtUtc;
        session.EndedAtUtc = values.EndedAtUtc;
        session.TargetZoneLowBpm = values.TargetZone?.LowBpm;
        session.TargetZoneHighBpm = values.TargetZone?.HighBpm;
        session.SampleIntervalSeconds = values.SampleIntervalSeconds;
        session.HeartRateBpm = values.HeartRateBpm.ToArray();
        session.RrIntervalsMs = values.RrIntervalsMs.ToArray();
        session.SensorName = values.SensorName;
        session.DistanceKm = values.DistanceKm;
        session.AveragePowerWatts = values.AveragePowerWatts;
        session.EnergyKcal = values.EnergyKcal;
        session.Notes = values.Notes;
        session.RecoveryStartBpm = values.RecoveryStartBpm;
        session.RecoveryEndBpm = values.RecoveryEndBpm;
        session.TemplateName = values.TemplateName;
        session.Phases = values.Phases is { Count: > 0 } ? values.Phases.ToArray() : null;
    }

    private static CardioSessionSnapshot ToSnapshot(CardioSession session) => new(
        session.Id,
        session.ActivityType,
        session.StartedAtUtc,
        session.EndedAtUtc,
        session.TargetZoneLowBpm is { } low && session.TargetZoneHighBpm is { } high
            ? new CardioTargetZone(low, high)
            : null,
        session.SampleIntervalSeconds,
        session.HeartRateBpm.ToArray(),
        session.RrIntervalsMs.ToArray(),
        session.SensorName,
        session.DistanceKm,
        session.AveragePowerWatts,
        session.EnergyKcal,
        session.Notes,
        session.CreatedAtUtc,
        session.UpdatedAtUtc,
        session.Version,
        session.RecoveryStartBpm,
        session.RecoveryEndBpm,
        session.TemplateName,
        session.Phases?.ToArray());
}
