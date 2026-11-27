namespace Gainer.Core.Insights;

/// <summary>One strength workout or cardio session with start and end in UTC.</summary>
public sealed record TrainingInterval(DateTime StartedAtUtc, DateTime EndedAtUtc);

/// <summary>A day with at least one session: minutes trained and intensity level 1 to 4.</summary>
public sealed record TrainingHeatmapDay(DateOnly Date, int Minutes, int Level);

/// <summary>
/// The twelve months up to <see cref="Today"/> in Monday-to-Sunday columns. <see cref="Days"/> lists only
/// days with training; all other days of the range have level 0.
/// </summary>
public sealed record TrainingHeatmapSnapshot(
    DateOnly Start,
    DateOnly Today,
    int WeekCount,
    IReadOnlyList<double> Bounds,
    IReadOnlyList<TrainingHeatmapDay> Days);

/// <summary>
/// Port of the app's training heatmap (<c>buildTrainingHeatmap</c>, <c>heatmapBounds</c> and <c>heatmapLevel</c> in
/// training_heatmap.dart); the rules are in contracts/fixtures/training-heatmap.json.
/// </summary>
public static class TrainingHeatmap
{
    /// <summary>First day: the day after today one year ago, overflowing like a calendar date (2027-02-30 is 2027-03-02).</summary>
    public static DateOnly StartFor(DateOnly today) => new DateOnly(today.Year - 1, today.Month, 1).AddDays(today.Day);

    public static TrainingHeatmapSnapshot Build(IEnumerable<TrainingInterval> sessions, DateOnly today, TimeZoneInfo timeZone)
    {
        DateOnly start = StartFor(today);
        var seconds = new SortedDictionary<DateOnly, long>();
        foreach (TrainingInterval session in sessions)
        {
            DateOnly day = LocalDays.DateOf(session.StartedAtUtc, timeZone);
            if (day < start || day > today) continue;
            TimeSpan duration = session.EndedAtUtc - session.StartedAtUtc;
            long whole = duration < TimeSpan.Zero ? 0 : duration.Ticks / TimeSpan.TicksPerSecond;
            seconds[day] = seconds.GetValueOrDefault(day) + whole;
        }

        Dictionary<DateOnly, int> minutes = seconds.ToDictionary(
            item => item.Key,
            item => (int)Math.Round(item.Value / 60m, MidpointRounding.AwayFromZero));
        IReadOnlyList<double> bounds = Bounds(minutes.Values);
        DateOnly firstMonday = start.AddDays(-(((int)start.DayOfWeek + 6) % 7));
        return new TrainingHeatmapSnapshot(
            start,
            today,
            (today.DayNumber - firstMonday.DayNumber) / 7 + 1,
            bounds,
            minutes.OrderBy(item => item.Key)
                .Select(item => new TrainingHeatmapDay(item.Key, item.Value, Level(item.Value, bounds)))
                .ToList());
    }

    /// <summary>First to third quartile with linear interpolation; empty without values.</summary>
    public static IReadOnlyList<double> Quartiles(IEnumerable<int> values)
    {
        double[] sorted = values.Select(value => (double)value).Order().ToArray();
        if (sorted.Length == 0) return [];
        double At(double p)
        {
            double position = p * (sorted.Length - 1);
            int lower = (int)Math.Floor(position);
            int upper = (int)Math.Ceiling(position);
            return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
        }
        return [At(0.25), At(0.5), At(0.75)];
    }

    /// <summary>Quartiles of the minutes of all training days; empty when all days are equally long.</summary>
    public static IReadOnlyList<double> Bounds(IReadOnlyCollection<int> minutes) =>
        minutes.Distinct().Count() <= 1 ? [] : Quartiles(minutes);

    /// <summary>1 plus the number of bounds the minutes exceed; 4 without bounds.</summary>
    public static int Level(int minutes, IReadOnlyList<double> bounds) =>
        bounds.Count == 0 ? 4 : 1 + bounds.Count(bound => minutes > bound);
}
