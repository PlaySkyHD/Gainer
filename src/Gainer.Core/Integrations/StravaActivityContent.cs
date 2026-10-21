using System.Globalization;
using System.Text;
using System.Xml;
using Gainer.Core.Training;

namespace Gainer.Core.Integrations;

/// <summary>A file upload for Strava: TCX with UTC times, so Strava applies the athlete's own time zone.</summary>
public sealed record StravaUpload(
    string ExternalId,
    string Name,
    string? Description,
    bool Trainer,
    byte[] TcxFile,
    string? SportTypeAfterUpload);

public sealed record StravaStrengthExercise(string Name, IReadOnlyList<StravaStrengthSet> Sets);

public sealed record StravaStrengthSet(WorkoutSetType SetType, decimal? WeightKg, int? Repetitions);

/// <summary>Builds what Gainer sends to Strava. Pure functions; no I/O.</summary>
public static class StravaActivityContent
{
    public const int MaximumDescriptionLength = 2_000;
    private const string TcxNamespace = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2";
    private static readonly CultureInfo German = CultureInfo.GetCultureInfo("de-DE");

    public static string ExternalId(StravaExportKind kind, Guid resourceId) =>
        $"gainer-{StravaExportNames.ToWire(kind)}-{resourceId:N}";

    public static StravaUpload ForCardio(CardioSession session)
    {
        ArgumentNullException.ThrowIfNull(session);
        DateTime start = DateTime.SpecifyKind(session.StartedAtUtc, DateTimeKind.Utc);
        DateTime end = DateTime.SpecifyKind(session.EndedAtUtc, DateTimeKind.Utc);
        double totalSeconds = Math.Max(1, (end - start).TotalSeconds);
        double? totalMeters = session.DistanceKm is { } km ? (double)km * 1_000 : null;
        int[] beats = session.HeartRateBpm.Where(value => value > 0).ToArray();

        var points = new List<TrackPoint>();
        for (int index = 0; index < session.HeartRateBpm.Length; index++)
        {
            double offset = (double)index * session.SampleIntervalSeconds;
            if (offset >= totalSeconds) break;
            int bpm = session.HeartRateBpm[index];
            points.Add(new TrackPoint(start.AddSeconds(offset), Distance(offset), bpm > 0 ? bpm : null));
        }
        points.Add(new TrackPoint(end, totalMeters, null));

        byte[] file = Tcx(
            "Biking",
            start,
            totalSeconds,
            totalMeters,
            session.EnergyKcal,
            beats.Length == 0 ? null : (int)Math.Round(beats.Average()),
            beats.Length == 0 ? null : beats.Max(),
            points);

        var description = new List<string>();
        if (!string.IsNullOrWhiteSpace(session.Notes)) description.Add(session.Notes.Trim());
        if (session.TargetZoneLowBpm is { } low && session.TargetZoneHighBpm is { } high)
        {
            description.Add($"Zielbereich {low}–{high} bpm");
        }
        if (session.AveragePowerWatts is { } watts)
        {
            description.Add($"Ø {Number(watts)} W");
        }

        return new StravaUpload(
            ExternalId(StravaExportKind.Cardio, session.Id),
            string.IsNullOrWhiteSpace(session.TemplateName) ? ActivityName(session.ActivityType) : session.TemplateName.Trim(),
            Description(description),
            Trainer: true,
            file,
            SportTypeAfterUpload: null);

        double? Distance(double offset) => totalMeters is { } meters ? meters * offset / totalSeconds : null;
    }

    public static StravaUpload ForStrength(Workout workout, IReadOnlyList<StravaStrengthExercise> exercises)
    {
        ArgumentNullException.ThrowIfNull(workout);
        ArgumentNullException.ThrowIfNull(exercises);
        DateTime start = DateTime.SpecifyKind(workout.StartedAtUtc, DateTimeKind.Utc);
        DateTime end = DateTime.SpecifyKind(
            workout.EndedAtUtc ?? throw new ArgumentException("The workout has not ended.", nameof(workout)),
            DateTimeKind.Utc);
        double totalSeconds = Math.Max(1, (end - start).TotalSeconds);
        byte[] file = Tcx(
            "Other",
            start,
            totalSeconds,
            null,
            null,
            null,
            null,
            [new TrackPoint(start, null, null), new TrackPoint(start.AddSeconds(totalSeconds), null, null)]);

        var description = new List<string>();
        foreach (StravaStrengthExercise exercise in exercises)
        {
            string? summary = SetSummary(exercise.Sets);
            if (summary is not null) description.Add($"{exercise.Name}: {summary}");
        }
        if (!string.IsNullOrWhiteSpace(workout.Notes)) description.Add(workout.Notes.Trim());

        return new StravaUpload(
            ExternalId(StravaExportKind.Strength, workout.Id),
            string.IsNullOrWhiteSpace(workout.Title) ? "Krafttraining" : workout.Title.Trim(),
            Description(description),
            Trainer: false,
            file,
            SportTypeAfterUpload: "WeightTraining");
    }

    /// <summary>
    /// Working sets in order, equal neighbours merged: „3 × 8 · 80 kg, 1 × 6 · 85 kg“. Warm-up sets are left out.
    /// </summary>
    public static string? SetSummary(IReadOnlyList<StravaStrengthSet> sets)
    {
        var groups = new List<(decimal? Weight, int? Reps, int Count)>();
        foreach (StravaStrengthSet set in sets.Where(item => item.SetType != WorkoutSetType.Warmup))
        {
            if (groups.Count > 0 && groups[^1].Weight == set.WeightKg && groups[^1].Reps == set.Repetitions)
            {
                groups[^1] = groups[^1] with { Count = groups[^1].Count + 1 };
            }
            else
            {
                groups.Add((set.WeightKg, set.Repetitions, 1));
            }
        }
        if (groups.Count == 0) return null;
        return string.Join(", ", groups.Select(group =>
        {
            string count = group.Reps is { } reps
                ? $"{group.Count} × {reps}"
                : group.Count == 1 ? "1 Satz" : $"{group.Count} Sätze";
            return group.Weight is { } weight ? $"{count} · {Number(weight)} kg" : count;
        }));
    }

    private static string ActivityName(string activityType) => activityType switch
    {
        CardioActivityTypes.IndoorCycling => "Rad-Ergometer",
        _ => "Cardio",
    };

    private static string? Description(List<string> lines)
    {
        if (lines.Count == 0) return null;
        string text = string.Join("\n", lines);
        return text.Length <= MaximumDescriptionLength ? text : text[..(MaximumDescriptionLength - 1)] + "…";
    }

    private static string Number(decimal value) => value.ToString("0.##", German);

    private static string Time(DateTime value) => value.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    private static string Invariant(double value) => value.ToString("0.##", CultureInfo.InvariantCulture);

    private static byte[] Tcx(
        string sport,
        DateTime start,
        double totalSeconds,
        double? totalMeters,
        decimal? energyKcal,
        int? averageBpm,
        int? maximumBpm,
        IReadOnlyList<TrackPoint> points)
    {
        var settings = new XmlWriterSettings { Encoding = new UTF8Encoding(false), Indent = false };
        using var stream = new MemoryStream();
        using (var writer = XmlWriter.Create(stream, settings))
        {
            writer.WriteStartDocument();
            writer.WriteStartElement("TrainingCenterDatabase", TcxNamespace);
            writer.WriteStartElement("Activities", TcxNamespace);
            writer.WriteStartElement("Activity", TcxNamespace);
            writer.WriteAttributeString("Sport", sport);
            writer.WriteElementString("Id", TcxNamespace, Time(start));
            writer.WriteStartElement("Lap", TcxNamespace);
            writer.WriteAttributeString("StartTime", Time(start));
            writer.WriteElementString("TotalTimeSeconds", TcxNamespace, Invariant(totalSeconds));
            writer.WriteElementString("DistanceMeters", TcxNamespace, Invariant(totalMeters ?? 0));
            int calories = energyKcal is { } kcal ? (int)Math.Clamp(Math.Round(kcal), 0, ushort.MaxValue) : 0;
            writer.WriteElementString("Calories", TcxNamespace, calories.ToString(CultureInfo.InvariantCulture));
            if (averageBpm is { } average) WriteBpm(writer, "AverageHeartRateBpm", average);
            if (maximumBpm is { } maximum) WriteBpm(writer, "MaximumHeartRateBpm", maximum);
            writer.WriteElementString("Intensity", TcxNamespace, "Active");
            writer.WriteElementString("TriggerMethod", TcxNamespace, "Manual");
            writer.WriteStartElement("Track", TcxNamespace);
            foreach (TrackPoint point in points)
            {
                writer.WriteStartElement("Trackpoint", TcxNamespace);
                writer.WriteElementString("Time", TcxNamespace, Time(point.Time));
                if (point.DistanceMeters is { } meters)
                {
                    writer.WriteElementString("DistanceMeters", TcxNamespace, Invariant(meters));
                }
                if (point.Bpm is { } bpm) WriteBpm(writer, "HeartRateBpm", bpm);
                writer.WriteEndElement();
            }
            writer.WriteEndElement();
            writer.WriteEndElement();
            writer.WriteEndElement();
            writer.WriteEndElement();
            writer.WriteEndElement();
            writer.WriteEndDocument();
        }
        return stream.ToArray();
    }

    private static void WriteBpm(XmlWriter writer, string element, int bpm)
    {
        writer.WriteStartElement(element, TcxNamespace);
        writer.WriteElementString("Value", TcxNamespace, Math.Clamp(bpm, 1, 255).ToString(CultureInfo.InvariantCulture));
        writer.WriteEndElement();
    }

    private sealed record TrackPoint(DateTime Time, double? DistanceMeters, int? Bpm);
}
