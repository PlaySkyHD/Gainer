namespace Gainer.Core.Training;

/// <summary>A cardio session without its time series, for lists.</summary>
public sealed record CardioSessionSummary(
    Guid SessionId,
    string ActivityType,
    string? TemplateName,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    int? AverageHeartRateBpm,
    int? MaxHeartRateBpm,
    decimal? DistanceKm,
    decimal? AveragePowerWatts,
    decimal? EnergyKcal,
    string? Notes);

/// <summary>Heart rate figures derived from a stored series; samples of 0 mean no signal and are skipped.</summary>
public static class CardioHeartRate
{
    public static int? Average(IEnumerable<int> series)
    {
        int[] signal = series.Where(value => value > 0).ToArray();
        return signal.Length == 0
            ? null
            : (int)Math.Round(signal.Average(), MidpointRounding.AwayFromZero);
    }

    public static int? Maximum(IEnumerable<int> series)
    {
        int[] signal = series.Where(value => value > 0).ToArray();
        return signal.Length == 0 ? null : signal.Max();
    }
}

public interface ICardioSessionQueries
{
    /// <summary>
    /// Sessions that started on the local days <paramref name="from"/> through <paramref name="through"/>, newest first.
    /// </summary>
    Task<IReadOnlyList<CardioSessionSummary>> ListAsync(
        DateOnly from,
        DateOnly through,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default);

    /// <summary>One of the user's sessions with its full series; null for unknown or foreign IDs.</summary>
    Task<CardioSessionSnapshot?> GetAsync(Guid sessionId, CancellationToken cancellationToken = default);
}
