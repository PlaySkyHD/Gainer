namespace Gainer.Core.Insights;

/// <summary>Period of the trend tiles in the app's statistics: 4 W, 3 M, 1 J or Alle.</summary>
public enum TrendPeriod
{
    FourWeeks,
    ThreeMonths,
    Year,
    All,
}

/// <summary>Totals of one counted workout for the trends.</summary>
public sealed record WorkoutTrendEntry(DateOnly Day, TimeSpan Duration, int SetCount, int Repetitions, decimal VolumeKg);

/// <summary>Figures of one week or month of the period; null means no data in it, not zero.</summary>
public sealed record TrendBucket(
    DateOnly Start,
    int Workouts,
    decimal TotalMinutes,
    decimal? AverageMinutes,
    decimal VolumeKg,
    int Sets,
    int Repetitions,
    decimal? RepetitionsPerSet,
    decimal? BodyweightKg);

public sealed record TrainingTrendsSnapshot(
    TrendPeriod Period,
    DateOnly Start,
    DateOnly Today,
    int WorkoutCount,
    decimal WorkoutsPerWeek,
    TimeSpan? AverageDuration,
    TimeSpan TotalDuration,
    decimal VolumeKg,
    int SetCount,
    int Repetitions,
    decimal? RepetitionsPerSet,
    decimal? LatestBodyweightKg,
    IReadOnlyList<TrendBucket> Buckets);

/// <summary>
/// Port of the app's trend tiles (<c>workoutTrendEntries</c> and <c>TrainingTrends.compute</c> in
/// training_trends.dart); the rules are in contracts/fixtures/training-trends.json.
/// </summary>
public static class TrainingTrends
{
    /// <summary>Totals per counted workout with the formulas of <see cref="TrainingStatistics"/>.</summary>
    public static IReadOnlyList<WorkoutTrendEntry> Entries(
        IEnumerable<TrainingWorkoutInput> workouts,
        IReadOnlyCollection<CheckInWeight> checkIns,
        IReadOnlyDictionary<Guid, ExerciseFactorInput> exercises,
        TimeZoneInfo timeZone,
        bool includeWarmups)
    {
        var entries = new List<WorkoutTrendEntry>();
        foreach (TrainingWorkoutInput workout in workouts.Where(TrainingStatistics.IsCounted))
        {
            IReadOnlyList<BlockStatistics> blocks =
                TrainingStatistics.WorkoutBlocks(workout, checkIns, exercises, timeZone, includeWarmups);
            TimeSpan duration = workout.EndedAtUtc!.Value - workout.StartedAtUtc;
            entries.Add(new WorkoutTrendEntry(
                LocalDays.DateOf(workout.StartedAtUtc, timeZone),
                duration < TimeSpan.Zero ? TimeSpan.Zero : duration,
                blocks.Sum(block => block.SetCount),
                blocks.Sum(block => block.TotalRepetitions),
                blocks.Sum(block => block.VolumeKg)));
        }
        return entries;
    }

    public static TrainingTrendsSnapshot Compute(
        IReadOnlyCollection<WorkoutTrendEntry> entries,
        IReadOnlyCollection<CheckInWeight> checkIns,
        TrendPeriod period,
        DateOnly today)
    {
        DateOnly start = PeriodStart(period, today, entries, checkIns);
        DateOnly[] starts = BucketStarts(period, start, today);
        var buckets = new Accumulator[starts.Length];
        for (int i = 0; i < buckets.Length; i++) buckets[i] = new Accumulator();

        long totalTicks = 0;
        int count = 0;
        foreach (WorkoutTrendEntry entry in entries.Where(item => item.Day >= start && item.Day <= today))
        {
            buckets[IndexOf(starts, entry.Day)].Add(entry);
            totalTicks += entry.Duration.Ticks;
            count++;
        }

        DateOnly? latestDay = null;
        decimal? latestKg = null;
        foreach (CheckInWeight checkIn in checkIns.Where(item => item.LocalDate >= start && item.LocalDate <= today))
        {
            buckets[IndexOf(starts, checkIn.LocalDate)].AddWeight(checkIn.WeightKg);
            if (latestDay is null || checkIn.LocalDate >= latestDay)
            {
                latestDay = checkIn.LocalDate;
                latestKg = checkIn.WeightKg;
            }
        }

        int days = today.DayNumber - start.DayNumber + 1;
        long totalSeconds = totalTicks / TimeSpan.TicksPerSecond;
        int sets = buckets.Sum(item => item.Sets);
        int repetitions = buckets.Sum(item => item.Repetitions);
        return new TrainingTrendsSnapshot(
            period,
            start,
            today,
            count,
            count * 7m / days,
            count == 0 ? null : TimeSpan.FromSeconds(totalSeconds / count),
            new TimeSpan(totalTicks),
            buckets.Sum(item => item.VolumeKg),
            sets,
            repetitions,
            Ratio(repetitions, sets),
            latestKg,
            starts.Select((bucketStart, index) => buckets[index].ToBucket(bucketStart)).ToList());
    }

    private static decimal? Ratio(decimal value, decimal count) => count == 0 ? null : value / count;

    private static DateOnly Monday(DateOnly day) => day.AddDays(-(((int)day.DayOfWeek + 6) % 7));

    /// <summary>First day of a period that does not depend on the data; null for <see cref="TrendPeriod.All"/>.</summary>
    public static DateOnly? FixedStart(TrendPeriod period, DateOnly today) => period switch
    {
        TrendPeriod.FourWeeks => Monday(today).AddDays(-7 * 3),
        TrendPeriod.ThreeMonths => Monday(today).AddDays(-7 * 12),
        TrendPeriod.Year => new DateOnly(today.Year, today.Month, 1).AddMonths(-11),
        _ => null,
    };

    /// <summary>All starts on the first of the month of the earliest workout or check-in, or of today without data.</summary>
    private static DateOnly PeriodStart(
        TrendPeriod period,
        DateOnly today,
        IEnumerable<WorkoutTrendEntry> entries,
        IEnumerable<CheckInWeight> checkIns)
    {
        if (FixedStart(period, today) is { } start) return start;
        DateOnly first = entries.Select(item => item.Day)
            .Concat(checkIns.Select(item => item.LocalDate))
            .Append(today)
            .Min();
        return new DateOnly(first.Year, first.Month, 1);
    }

    private static DateOnly[] BucketStarts(TrendPeriod period, DateOnly start, DateOnly today)
    {
        bool weekly = period is TrendPeriod.FourWeeks or TrendPeriod.ThreeMonths;
        var starts = new List<DateOnly>();
        for (DateOnly day = start; day <= today; day = weekly ? day.AddDays(7) : day.AddMonths(1))
        {
            starts.Add(day);
        }
        return starts.ToArray();
    }

    /// <summary>The last bucket that starts on or before the day; the first for earlier days.</summary>
    private static int IndexOf(DateOnly[] starts, DateOnly day)
    {
        int index = starts.Length - 1;
        while (index > 0 && day < starts[index]) index--;
        return index;
    }

    private sealed class Accumulator
    {
        private decimal weightSum;
        private int weightCount;

        public int Workouts { get; private set; }

        public decimal Minutes { get; private set; }

        public decimal VolumeKg { get; private set; }

        public int Sets { get; private set; }

        public int Repetitions { get; private set; }

        public void Add(WorkoutTrendEntry entry)
        {
            Workouts++;
            Minutes += entry.Duration.Ticks / TimeSpan.TicksPerSecond / 60m;
            VolumeKg += entry.VolumeKg;
            Sets += entry.SetCount;
            Repetitions += entry.Repetitions;
        }

        public void AddWeight(decimal weightKg)
        {
            weightSum += weightKg;
            weightCount++;
        }

        public TrendBucket ToBucket(DateOnly start) => new(
            start,
            Workouts,
            Minutes,
            Ratio(Minutes, Workouts),
            VolumeKg,
            Sets,
            Repetitions,
            Ratio(Repetitions, Sets),
            Ratio(weightSum, weightCount));
    }
}
