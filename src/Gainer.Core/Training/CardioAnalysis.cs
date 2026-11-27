namespace Gainer.Core.Training;

/// <summary>
/// Key figures of a cardio session from its series, as on the app's detail screen. Port of
/// <c>CardioAnalysis</c> in cardio_analysis.dart; the rules are in contracts/fixtures/cardio-analysis.json.
/// </summary>
public sealed record CardioAnalysis(
    TimeSpan ActiveDuration,
    decimal? AverageBpm,
    int? MaxBpm,
    TimeSpan TimeInZone,
    decimal? ZoneShare,
    int? RmssdMs,
    int? RecoveryDropBpm)
{
    private const int MinValidRrMs = 300;
    private const int MaxValidRrMs = 2000;
    private const double MaxRrJump = 0.2;
    private const int MinRmssdDifferences = 30;

    public static CardioAnalysis Of(CardioSessionSnapshot session)
    {
        ArgumentNullException.ThrowIfNull(session);
        return FromSeries(
            session.HeartRateBpm,
            session.RrIntervalsMs,
            session.SampleIntervalSeconds,
            session.TargetZone,
            session.Phases ?? [],
            session.EndedAtUtc - session.StartedAtUtc,
            session.RecoveryStartBpm,
            session.RecoveryEndBpm);
    }

    public static CardioAnalysis FromSeries(
        IReadOnlyList<int> heartRateBpm,
        IReadOnlyList<int> rrIntervalsMs,
        int sampleIntervalSeconds,
        CardioTargetZone? zone,
        IReadOnlyList<CardioPhaseValues> phases,
        TimeSpan activeDuration,
        int? recoveryStartBpm = null,
        int? recoveryEndBpm = null)
    {
        int[] withSignal = heartRateBpm.Where(bpm => bpm > 0).ToArray();
        (int inZone, int targeted) = ZoneCounts(heartRateBpm, withSignal, sampleIntervalSeconds, zone, phases);
        return new CardioAnalysis(
            activeDuration < TimeSpan.Zero ? TimeSpan.Zero : TimeSpan.FromSeconds(activeDuration.Ticks / TimeSpan.TicksPerSecond),
            withSignal.Length == 0 ? null : (decimal)withSignal.Sum() / withSignal.Length,
            withSignal.Length == 0 ? null : withSignal.Max(),
            TimeSpan.FromSeconds((long)inZone * sampleIntervalSeconds),
            targeted == 0 ? null : (decimal)inZone / targeted,
            Rmssd(rrIntervalsMs),
            recoveryStartBpm is { } startBpm && recoveryEndBpm is { } endBpm ? endBpm - startBpm : null);
    }

    /// <summary>
    /// RMSSD with artifact filter: values outside 300–2000 ms are invalid; a difference counts only when both
    /// neighbours are valid and differ by at most 20 % of the previous one. Null below 30 differences.
    /// </summary>
    public static int? Rmssd(IReadOnlyList<int> rrIntervalsMs)
    {
        static bool Valid(int rr) => rr is >= MinValidRrMs and <= MaxValidRrMs;
        int count = 0;
        double sum = 0;
        for (int i = 1; i < rrIntervalsMs.Count; i++)
        {
            int previous = rrIntervalsMs[i - 1];
            int current = rrIntervalsMs[i];
            if (!Valid(previous) || !Valid(current)) continue;
            int difference = current - previous;
            if (Math.Abs(difference) > previous * MaxRrJump) continue;
            sum += (double)difference * difference;
            count++;
        }
        return count < MinRmssdDifferences ? null : (int)Math.Round(Math.Sqrt(sum / count), MidpointRounding.AwayFromZero);
    }

    /// <summary>With phases the phase at each sample's start counts, otherwise the fixed zone; samples without target do not count.</summary>
    private static (int InZone, int Targeted) ZoneCounts(
        IReadOnlyList<int> heartRateBpm,
        int[] withSignal,
        int sampleIntervalSeconds,
        CardioTargetZone? zone,
        IReadOnlyList<CardioPhaseValues> phases)
    {
        if (phases.Count == 0)
        {
            return zone is null ? (0, 0) : (withSignal.Count(bpm => Contains(zone.LowBpm, zone.HighBpm, bpm)), withSignal.Length);
        }

        int inZone = 0;
        int targeted = 0;
        for (int i = 0; i < heartRateBpm.Count; i++)
        {
            int bpm = heartRateBpm[i];
            if (bpm <= 0) continue;
            int second = i * sampleIntervalSeconds;
            CardioPhaseValues? phase = phases.FirstOrDefault(item =>
                second >= item.StartOffsetSeconds && second < item.StartOffsetSeconds + item.DurationSeconds);
            if (phase is not { LowBpm: { } low, HighBpm: { } high }) continue;
            targeted++;
            if (Contains(low, high, bpm)) inZone++;
        }
        return (inZone, targeted);
    }

    private static bool Contains(int low, int high, int bpm) => bpm >= low && bpm <= high;
}
