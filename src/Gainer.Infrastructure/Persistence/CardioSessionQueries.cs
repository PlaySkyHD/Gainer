using Gainer.Core.Insights;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class CardioSessionQueries(AppDbContext context) : ICardioSessionQueries
{
    public async Task<IReadOnlyList<CardioSessionSummary>> ListAsync(
        DateOnly from,
        DateOnly through,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(through, from);
        ArgumentNullException.ThrowIfNull(timeZone);
        DateTime fromUtc = LocalDays.StartOfDayUtc(from, timeZone);
        DateTime beforeUtc = LocalDays.StartOfDayUtc(through.AddDays(1), timeZone);
        // The RR intervals stay in the database; the list only needs the heart rate series.
        var sessions = await context.CardioSessions.AsNoTracking()
            .Where(item => item.StartedAtUtc >= fromUtc && item.StartedAtUtc < beforeUtc)
            .OrderByDescending(item => item.StartedAtUtc)
            .ThenByDescending(item => item.Id)
            .Select(item => new
            {
                item.Id,
                item.ActivityType,
                item.TemplateName,
                item.StartedAtUtc,
                item.EndedAtUtc,
                item.HeartRateBpm,
                item.DistanceKm,
                item.AveragePowerWatts,
                item.EnergyKcal,
                item.Notes,
            })
            .ToListAsync(cancellationToken);
        return sessions
            .Select(item => new CardioSessionSummary(
                item.Id,
                item.ActivityType,
                item.TemplateName,
                item.StartedAtUtc,
                item.EndedAtUtc,
                CardioHeartRate.Average(item.HeartRateBpm),
                CardioHeartRate.Maximum(item.HeartRateBpm),
                item.DistanceKm,
                item.AveragePowerWatts,
                item.EnergyKcal,
                item.Notes))
            .ToList();
    }

    public async Task<CardioSessionSnapshot?> GetAsync(Guid sessionId, CancellationToken cancellationToken = default)
    {
        CardioSession? session = await context.CardioSessions.AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == sessionId, cancellationToken);
        return session is null ? null : TrainingSnapshots.Cardio(session);
    }
}
