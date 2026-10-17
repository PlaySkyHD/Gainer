using Gainer.Core.Training;

namespace Gainer.Core.Insights;

/// <summary>
/// Trainingskennzahlen nach training-volume-v2 und e1rm-epley-v2. Die Regeln entsprechen
/// contracts/fixtures/training-statistics.json. Berechnet wird ungerundet; die Ausgabe rundet
/// <see cref="RoundForOutput(decimal)"/>.
/// </summary>
public static class TrainingStatistics
{
    public const string DefaultTimeZoneId = "Europe/Berlin";

    private static readonly int[] RepetitionThresholds = [1, 3, 5, 8, 10, 12];

    public static bool IsCounted(TrainingWorkoutInput workout) => workout.EndedAtUtc is not null && workout.DeletedAtUtc is null;

    public static bool IsRecorded(TrainingSetInput set, ExerciseType type)
    {
        bool hasRepetitions = set.Repetitions is >= 1;
        return type is ExerciseType.Strength or ExerciseType.Assisted
            ? set.WeightKg is not null && hasRepetitions
            : hasRepetitions;
    }

    /// <summary>Gewicht des jüngsten Check-ins am oder vor dem lokalen Starttag des Trainings.</summary>
    public static decimal? BodyweightFor(DateTime startedAtUtc, IEnumerable<CheckInWeight> checkIns, TimeZoneInfo timeZone)
    {
        DateOnly startDay = DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(startedAtUtc, timeZone));
        return checkIns.Where(item => item.LocalDate <= startDay)
            .OrderBy(item => item.LocalDate)
            .LastOrDefault()?.WeightKg;
    }

    /// <summary>Kennzahlen je Block eines beendeten Trainings. Nur erfasste Sätze fließen ein.</summary>
    public static IReadOnlyList<BlockStatistics> WorkoutBlocks(
        TrainingWorkoutInput workout,
        IReadOnlyCollection<CheckInWeight> checkIns,
        IReadOnlyDictionary<Guid, ExerciseFactorInput> exercises,
        TimeZoneInfo timeZone,
        bool includeWarmups = false)
    {
        DateTime completedAtUtc = workout.EndedAtUtc
            ?? throw new ArgumentException("Only completed workouts have statistics.", nameof(workout));
        decimal? bodyweightKg = BodyweightFor(workout.StartedAtUtc, checkIns, timeZone);
        return workout.Exercises
            .Select(block => Block(workout.WorkoutId, completedAtUtc, block, bodyweightKg, exercises, includeWarmups))
            .ToArray();
    }

    /// <summary>Rekordgrundlage einer Übung über die übergebenen Trainings (nur beendet, nicht gelöscht).</summary>
    public static ExerciseHistory History(
        Guid sourceExerciseId,
        IEnumerable<TrainingWorkoutInput> workouts,
        IReadOnlyCollection<CheckInWeight> checkIns,
        IReadOnlyDictionary<Guid, ExerciseFactorInput> exercises,
        TimeZoneInfo timeZone,
        bool includeWarmups = false)
    {
        var totals = new List<ExerciseWorkoutTotals>();
        var sets = new List<RecordedSet>();
        foreach (TrainingWorkoutInput workout in Chronological(workouts))
        {
            BlockStatistics[] blocks = WorkoutBlocks(workout, checkIns, exercises, timeZone, includeWarmups)
                .Where(block => block.SourceExerciseId == sourceExerciseId)
                .ToArray();
            sets.AddRange(blocks.SelectMany(block => block.Sets));
            BlockStatistics[] recorded = blocks.Where(block => block.SetCount > 0).ToArray();
            if (recorded.Length > 0) totals.Add(Totals(recorded));
        }
        return new ExerciseHistory(totals, sets);
    }

    /// <summary>Zusammenfassung eines beendeten Trainings. <paramref name="history"/> darf das Training selbst enthalten.</summary>
    public static TrainingSummary Summarize(
        TrainingWorkoutInput workout,
        IEnumerable<TrainingWorkoutInput> history,
        IReadOnlyCollection<CheckInWeight> checkIns,
        IReadOnlyDictionary<Guid, ExerciseFactorInput> exercises,
        TimeZoneInfo timeZone,
        bool includeWarmups = false)
    {
        if (!IsCounted(workout))
        {
            throw new ArgumentException("Only completed, not deleted workouts can be summarized.", nameof(workout));
        }

        IReadOnlyList<BlockStatistics> blocks = WorkoutBlocks(workout, checkIns, exercises, timeZone, includeWarmups);
        List<TrainingWorkoutInput> workouts = history.Where(item => item.WorkoutId != workout.WorkoutId).Append(workout).ToList();
        var newRecords = new List<NewRecord>();
        foreach (Guid exerciseId in blocks.Select(block => block.SourceExerciseId).Distinct())
        {
            ExerciseRecords records = History(exerciseId, workouts, checkIns, exercises, timeZone, includeWarmups).Records();
            foreach (RecordKind kind in Enum.GetValues<RecordKind>())
            {
                newRecords.AddRange(records.Events(kind)
                    .Where(item => item.WorkoutId == workout.WorkoutId)
                    .Select(item => new NewRecord(exerciseId, kind, item.Value)));
            }
        }

        return new TrainingSummary(
            workout.WorkoutId,
            workout.EndedAtUtc!.Value - workout.StartedAtUtc,
            blocks.Sum(block => block.SetCount),
            blocks.Sum(block => block.TotalRepetitions),
            blocks.Sum(block => block.VolumeKg),
            blocks.Select(block => block.Best).OfType<BestSet>().ToArray(),
            newRecords);
    }

    /// <summary>Bestes Ergebnis über mehrere Kandidaten: höchstes 1RM, dann Gewicht, Wiederholungen, Zeitpunkt.</summary>
    public static BestSet? BestOf(IEnumerable<BestSet?> candidates) => candidates
        .OfType<BestSet>()
        .OrderByDescending(item => item.EstimatedOneRepMaxKg)
        .ThenByDescending(item => item.EffectiveWeightKg)
        .ThenByDescending(item => item.Repetitions)
        .ThenByDescending(item => item.CompletedAtUtc)
        .ThenBy(item => item.WorkoutId)
        .FirstOrDefault();

    /// <summary>Kaufmännische Rundung auf zwei Nachkommastellen, nur für die Ausgabe.</summary>
    public static decimal RoundForOutput(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);

    public static decimal? RoundForOutput(decimal? value) => value is null ? null : RoundForOutput(value.Value);

    private static BlockStatistics Block(
        Guid workoutId,
        DateTime completedAtUtc,
        TrainingBlockInput block,
        decimal? bodyweightKg,
        IReadOnlyDictionary<Guid, ExerciseFactorInput> exercises,
        bool includeWarmups)
    {
        exercises.TryGetValue(block.SourceExerciseId, out ExerciseFactorInput? factor);
        decimal bodyweightFactor = factor?.BodyweightFactor ?? ExerciseFactors.DefaultBodyweightFactor(block.ExerciseType);
        decimal weightFactor = factor?.WeightFactor ?? 1m;

        var sets = new List<RecordedSet>();
        foreach (TrainingSetInput set in block.Sets)
        {
            if (!includeWarmups && set.SetType == WorkoutSetType.Warmup) continue;
            if (!IsRecorded(set, block.ExerciseType)) continue;
            sets.Add(new RecordedSet(
                EffectiveWeightKg(block.ExerciseType, set.WeightKg, bodyweightFactor, weightFactor, bodyweightKg),
                set.Repetitions!.Value));
        }

        return new BlockStatistics(
            workoutId,
            completedAtUtc,
            block.WorkoutExerciseId,
            block.SourceExerciseId,
            sets,
            bodyweightKg,
            bodyweightKg is null && bodyweightFactor > 0 && sets.Count > 0);
    }

    private static decimal EffectiveWeightKg(
        ExerciseType type,
        decimal? weightKg,
        decimal bodyweightFactor,
        decimal weightFactor,
        decimal? bodyweightKg)
    {
        decimal bodyweightPart = (bodyweightKg ?? 0m) * bodyweightFactor;
        if (type == ExerciseType.Assisted)
        {
            return Math.Max(0m, bodyweightPart - (weightKg ?? 0m));
        }

        return (weightKg ?? 0m) * weightFactor + bodyweightPart;
    }

    private static ExerciseWorkoutTotals Totals(BlockStatistics[] blocks) => new(
        blocks[0].WorkoutId,
        blocks[0].CompletedAtUtc,
        blocks.Sum(block => block.SetCount),
        blocks.Max(block => block.MaxRepetitions),
        blocks.Sum(block => block.VolumeKg),
        MaxOrNull(blocks.Select(block => block.MaxWeightKg)),
        MaxOrNull(blocks.Select(block => block.EstimatedOneRepMaxKg)),
        blocks.Any(block => block.BodyweightMissing),
        BestOf(blocks.Select(block => block.Best)));

    private static TrainingWorkoutInput[] Chronological(IEnumerable<TrainingWorkoutInput> workouts) =>
        workouts.Where(IsCounted).OrderBy(item => item.StartedAtUtc).ThenBy(item => item.WorkoutId).ToArray();

    internal static decimal? MaxOrNull(IEnumerable<decimal?> values)
    {
        decimal? max = null;
        foreach (decimal? value in values)
        {
            if (value is { } number && (max is null || number > max)) max = number;
        }
        return max;
    }

    internal static IReadOnlyList<RecordEvent> StrictRecords(IEnumerable<RecordEvent> chronological)
    {
        var events = new List<RecordEvent>();
        decimal? best = null;
        foreach (RecordEvent item in chronological)
        {
            if (best is null || item.Value > best)
            {
                events.Add(item);
                best = item.Value;
            }
        }
        return events;
    }

    internal static IReadOnlyList<RepetitionRecord> RepetitionRecords(IEnumerable<RecordedSet> sets)
    {
        RecordedSet[] list = sets.ToArray();
        return RepetitionThresholds
            .Select(threshold => new RepetitionRecord(
                threshold,
                MaxOrNull(list.Where(set => set.Repetitions >= threshold).Select(set => (decimal?)set.EffectiveWeightKg))))
            .ToArray();
    }
}

public sealed record CheckInWeight(DateOnly LocalDate, decimal WeightKg);

/// <summary>Katalogfaktoren einer Übung; fehlende Werte nehmen die Typvorgabe bzw. 1 an.</summary>
public sealed record ExerciseFactorInput(Guid ExerciseId, decimal? BodyweightFactor, decimal? WeightFactor);

public sealed record TrainingSetInput(WorkoutSetType SetType, decimal? WeightKg, int? Repetitions);

public sealed record TrainingBlockInput(
    Guid WorkoutExerciseId,
    Guid SourceExerciseId,
    ExerciseType ExerciseType,
    IReadOnlyList<TrainingSetInput> Sets);

public sealed record TrainingWorkoutInput(
    Guid WorkoutId,
    DateTime StartedAtUtc,
    DateTime? EndedAtUtc,
    DateTime? DeletedAtUtc,
    IReadOnlyList<TrainingBlockInput> Exercises);

/// <summary>Ein erfasster Satz mit effektivem Gewicht.</summary>
public sealed record RecordedSet(decimal EffectiveWeightKg, int Repetitions)
{
    public decimal VolumeKg => EffectiveWeightKg * Repetitions;

    public decimal EstimatedOneRepMaxKg => Repetitions switch
    {
        <= 0 => 0m,
        1 => EffectiveWeightKg,
        _ => EffectiveWeightKg * (1m + Repetitions / 30m),
    };
}

public sealed record BestSet(
    Guid WorkoutId,
    Guid ExerciseId,
    DateTime CompletedAtUtc,
    decimal EffectiveWeightKg,
    int Repetitions,
    decimal EstimatedOneRepMaxKg);

/// <summary>Kennzahlen eines Blocks (Übung) in einem Training.</summary>
public sealed record BlockStatistics(
    Guid WorkoutId,
    DateTime CompletedAtUtc,
    Guid WorkoutExerciseId,
    Guid SourceExerciseId,
    IReadOnlyList<RecordedSet> Sets,
    decimal? BodyweightKg,
    bool BodyweightMissing)
{
    public int SetCount => Sets.Count;

    public int TotalRepetitions => Sets.Sum(set => set.Repetitions);

    public int MaxRepetitions => Sets.Count == 0 ? 0 : Sets.Max(set => set.Repetitions);

    public decimal VolumeKg => Sets.Sum(set => set.VolumeKg);

    public decimal? MaxWeightKg => TrainingStatistics.MaxOrNull(Sets.Select(set => (decimal?)set.EffectiveWeightKg));

    public decimal? AverageWeightKg
    {
        get
        {
            if (Sets.Count == 0) return null;
            if (TotalRepetitions == 0) return 0m;
            return VolumeKg / TotalRepetitions;
        }
    }

    public decimal? EstimatedOneRepMaxKg => TrainingStatistics.MaxOrNull(Sets.Select(set => (decimal?)set.EstimatedOneRepMaxKg));

    /// <summary>Satz mit dem höchsten geschätzten 1RM; bei Gleichstand der erste.</summary>
    public BestSet? Best
    {
        get
        {
            RecordedSet? best = null;
            foreach (RecordedSet set in Sets)
            {
                if (best is null || set.EstimatedOneRepMaxKg > best.EstimatedOneRepMaxKg) best = set;
            }
            return best is null
                ? null
                : new BestSet(WorkoutId, SourceExerciseId, CompletedAtUtc, best.EffectiveWeightKg, best.Repetitions,
                    best.EstimatedOneRepMaxKg);
        }
    }
}

/// <summary>Zusammenfassung einer Übung in einem Training (über alle Blöcke derselben Übung).</summary>
public sealed record ExerciseWorkoutTotals(
    Guid WorkoutId,
    DateTime CompletedAtUtc,
    int SetCount,
    int MaxRepetitions,
    decimal VolumeKg,
    decimal? MaxWeightKg,
    decimal? EstimatedOneRepMaxKg,
    bool BodyweightMissing,
    BestSet? Best);

public sealed record RecordEvent(Guid WorkoutId, decimal Value);

public sealed record RepetitionRecord(int Repetitions, decimal? MaxWeightKg);

public enum RecordKind
{
    MaxWeight,
    EstimatedOneRepMax,
    Volume,
    MaxRepetitions,
}

public sealed record ExerciseRecords(
    IReadOnlyList<RecordEvent> MaxWeight,
    IReadOnlyList<RecordEvent> EstimatedOneRepMax,
    IReadOnlyList<RecordEvent> Volume,
    IReadOnlyList<RecordEvent> MaxRepetitions,
    IReadOnlyList<RepetitionRecord> RepetitionRecords)
{
    public IReadOnlyList<RecordEvent> Events(RecordKind kind) => kind switch
    {
        RecordKind.MaxWeight => MaxWeight,
        RecordKind.EstimatedOneRepMax => EstimatedOneRepMax,
        RecordKind.Volume => Volume,
        _ => MaxRepetitions,
    };

    public RecordEvent? Current(RecordKind kind)
    {
        IReadOnlyList<RecordEvent> events = Events(kind);
        return events.Count == 0 ? null : events[^1];
    }
}

public sealed record ExerciseHistory(IReadOnlyList<ExerciseWorkoutTotals> Workouts, IReadOnlyList<RecordedSet> Sets)
{
    public ExerciseRecords Records() => new(
        TrainingStatistics.StrictRecords(Workouts
            .Where(item => item.MaxWeightKg is not null)
            .Select(item => new RecordEvent(item.WorkoutId, item.MaxWeightKg!.Value))),
        TrainingStatistics.StrictRecords(Workouts
            .Where(item => item.EstimatedOneRepMaxKg is not null)
            .Select(item => new RecordEvent(item.WorkoutId, item.EstimatedOneRepMaxKg!.Value))),
        TrainingStatistics.StrictRecords(Workouts
            .Select(item => new RecordEvent(item.WorkoutId, item.VolumeKg))),
        TrainingStatistics.StrictRecords(Workouts
            .Select(item => new RecordEvent(item.WorkoutId, item.MaxRepetitions))),
        TrainingStatistics.RepetitionRecords(Sets));
}

public sealed record NewRecord(Guid ExerciseId, RecordKind Kind, decimal Value);

public sealed record TrainingSummary(
    Guid WorkoutId,
    TimeSpan Duration,
    int SetCount,
    int TotalRepetitions,
    decimal VolumeKg,
    IReadOnlyList<BestSet> BestSets,
    IReadOnlyList<NewRecord> NewRecords);
