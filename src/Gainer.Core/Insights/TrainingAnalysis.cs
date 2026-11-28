using System.Globalization;
using Gainer.Core.Training;

namespace Gainer.Core.Insights;

/// <summary>Development of an exercise over the period, from the estimated one-rep max.</summary>
public enum ExerciseProgressStatus
{
    Progressing,
    Stagnating,
    Regressing,
    InsufficientData,
}

public enum FatigueSignalKind
{
    /// <summary>Repetitions of the top sets fell twice in a row at the same or a lower load.</summary>
    DecliningRepetitions,

    /// <summary>In each of the last two sessions more than half of the rated working sets had RIR 0.</summary>
    FailureOnMostSets,

    /// <summary>The last session lost at least 20 % volume and 5 % estimated one-rep max against the sessions before.</summary>
    VolumeAndStrengthDrop,
}

public enum RecommendationKind
{
    IncreaseWeight,
    IncreaseReps,
    KeepWeight,
    Deload,
    ChangeStimulus,
    NoRecommendation,
}

/// <summary>One workout of an exercise in the period with its recorded working sets (no warm-ups).</summary>
public sealed record AnalysisSession(
    Guid WorkoutId,
    DateOnly Day,
    int WorkingSets,
    decimal VolumeKg,
    decimal EstimatedOneRepMaxKg,
    decimal TopWeightKg,
    int TopSetMinRepetitions,
    int TopSetMaxRepetitions,
    decimal? TopLoggedWeightKg,
    int RatedSets,
    int ZeroRirSets);

/// <summary>A fatigue signal with its evidence; fields that do not belong to the kind are null.</summary>
public sealed record FatigueSignal(
    FatigueSignalKind Kind,
    int Sessions,
    int? FromRepetitions = null,
    int? ToRepetitions = null,
    decimal? WeightKg = null,
    int? ZeroRirSets = null,
    int? RatedSets = null,
    decimal? VolumeChangePercent = null,
    decimal? EstimatedOneRepMaxChangePercent = null);

/// <summary>Rule-based suggestion for the next session; weights are the logged weights (added or assistance weight).</summary>
public sealed record TrainingRecommendation(
    RecommendationKind Kind,
    decimal? SuggestedWeightKg = null,
    int? SuggestedRepetitions = null,
    int? RepetitionRangeLow = null,
    int? RepetitionRangeHigh = null,
    decimal? WeightStepKg = null,
    int SessionsSinceBest = 0)
{
    /// <summary>Short German reason with the numbers, worded as in the app.</summary>
    public string Text => TrainingAnalysis.RecommendationText(this);
}

public sealed record ExerciseAnalysis(
    Guid ExerciseId,
    string Name,
    ExerciseType ExerciseType,
    IReadOnlyList<AnalysisSession> Sessions,
    decimal? BestEstimatedOneRepMaxKg,
    int SessionsSinceBest,
    decimal? EstimatedOneRepMaxFirstKg,
    decimal? EstimatedOneRepMaxLastKg,
    decimal? EstimatedOneRepMaxChangePercent,
    decimal? TopWeightChangePercent,
    decimal? TopRepetitionsChange,
    decimal? VolumeChangePercent,
    decimal VolumePerWeekKg,
    decimal WorkingSetsPerWeek,
    ExerciseProgressStatus Status,
    IReadOnlyList<FatigueSignal> FatigueSignals,
    TrainingRecommendation Recommendation);

/// <summary>Volume and working sets of all exercises in a 7-day bucket from the period start.</summary>
public sealed record AnalysisWeek(DateOnly Start, bool Complete, decimal VolumeKg, int WorkingSets);

public sealed record TrainingAnalysisOverall(
    IReadOnlyList<AnalysisWeek> Weeks,
    decimal? WeeklyVolumeChangePercent,
    int ExercisesWithFatigue,
    int EligibleExercises,
    bool Fatigued);

public sealed record TrainingAnalysisSnapshot(
    TrendPeriod Period,
    DateOnly Start,
    DateOnly Today,
    IReadOnlyList<ExerciseAnalysis> Exercises,
    TrainingAnalysisOverall Overall);

/// <summary>
/// Port of the app's training analysis (<c>TrainingAnalysis.compute</c> in training_analysis.dart); the rules are
/// in contracts/fixtures/training-analysis.json. Sets, effective weights and the estimated one-rep max follow
/// <see cref="TrainingStatistics"/>.
/// </summary>
public static class TrainingAnalysis
{
    private const int MinimumSessions = 3;
    private const int SessionsForChangeStimulus = 4;
    private const long DefaultStepCents = 250;

    private static readonly NumberFormatInfo GermanNumbers = new()
    {
        NumberDecimalSeparator = ",",
        NumberGroupSeparator = ".",
        NumberGroupSizes = [3],
    };

    /// <summary>Analysis of the counted workouts whose local start day lies in the period ending <paramref name="today"/>.</summary>
    public static TrainingAnalysisSnapshot Compute(
        IEnumerable<TrainingWorkoutInput> workouts,
        IReadOnlyCollection<CheckInWeight> checkIns,
        IReadOnlyDictionary<Guid, ExerciseFactorInput> exercises,
        TimeZoneInfo timeZone,
        TrendPeriod period,
        DateOnly today)
    {
        DateOnly start = TrainingTrends.FixedStart(period, today)
            ?? throw new ArgumentOutOfRangeException(nameof(period), period, "The analysis needs a bounded period.");
        var collectors = new Dictionary<Guid, ExerciseCollector>();
        foreach (TrainingWorkoutInput workout in workouts.Where(TrainingStatistics.IsCounted)
                     .OrderBy(item => item.StartedAtUtc).ThenBy(item => item.WorkoutId))
        {
            DateOnly day = LocalDays.DateOf(workout.StartedAtUtc, timeZone);
            if (day < start || day > today) continue;
            decimal? bodyweightKg = TrainingStatistics.BodyweightFor(workout.StartedAtUtc, checkIns, timeZone);
            Collect(workout, day, bodyweightKg, exercises, collectors);
        }

        int days = today.DayNumber - start.DayNumber + 1;
        ExerciseAnalysis[] analyses = collectors.Values
            .Select(collector => collector.Analyze(days))
            .OrderByDescending(LastDay)
            .ThenBy(item => item.Name, StringComparer.Ordinal)
            .ThenBy(item => item.ExerciseId)
            .ToArray();
        return new TrainingAnalysisSnapshot(period, start, today, analyses, Overall.Of(analyses, start, today));
    }

    /// <summary>Adds the blocks of one workout to the collectors of their exercises.</summary>
    private static void Collect(
        TrainingWorkoutInput workout,
        DateOnly day,
        decimal? bodyweightKg,
        IReadOnlyDictionary<Guid, ExerciseFactorInput> exercises,
        Dictionary<Guid, ExerciseCollector> collectors)
    {
        var inWorkout = new List<ExerciseCollector>();
        foreach (TrainingBlockInput block in workout.Exercises)
        {
            if (!collectors.TryGetValue(block.SourceExerciseId, out ExerciseCollector? collector))
            {
                collector = new ExerciseCollector(block.SourceExerciseId);
                collectors[block.SourceExerciseId] = collector;
            }
            exercises.TryGetValue(block.SourceExerciseId, out ExerciseFactorInput? factor);
            collector.AddBlock(block, factor, bodyweightKg);
            if (!inWorkout.Contains(collector)) inWorkout.Add(collector);
        }
        foreach (ExerciseCollector collector in inWorkout) collector.EndWorkout(workout.WorkoutId, day);
    }

    /// <summary>Day of the last session; exercises without a session sort last.</summary>
    private static DateOnly LastDay(ExerciseAnalysis analysis) =>
        analysis.Sessions.Count == 0 ? DateOnly.MinValue : analysis.Sessions[^1].Day;

    /// <summary>German reason text of a recommendation; the app words it identically.</summary>
    public static string RecommendationText(TrainingRecommendation recommendation)
    {
        ArgumentNullException.ThrowIfNull(recommendation);
        string range = $"{recommendation.RepetitionRangeLow}–{recommendation.RepetitionRangeHigh} Wdh.";
        string? weight = recommendation.SuggestedWeightKg is { } kg ? Kg(kg) : null;
        return recommendation.Kind switch
        {
            RecommendationKind.IncreaseWeight =>
                $"Oberes Ende von {range} in allen Sätzen erreicht: nächstes Mal {weight} mit {recommendation.SuggestedRepetitions} Wdh.",
            RecommendationKind.IncreaseReps => weight is null
                ? $"Im Bereich {range}: auf {recommendation.SuggestedRepetitions} Wdh. je Satz steigern."
                : $"Im Bereich {range}: {weight} halten und auf {recommendation.SuggestedRepetitions} Wdh. je Satz steigern.",
            RecommendationKind.KeepWeight =>
                $"Unter {recommendation.RepetitionRangeLow} Wdh. im Bereich {range}: {weight ?? "Belastung"} halten, " +
                $"bis alle Sätze {recommendation.SuggestedRepetitions} Wdh. schaffen.",
            RecommendationKind.Deload => weight is null
                ? "Ermüdung oder Leistungsabfall: nächstes Mal leichter trainieren oder einen Ruhetag mehr einplanen."
                : $"Ermüdung oder Leistungsabfall: nächstes Mal {weight} (−10 %) und nicht bis zum Muskelversagen.",
            RecommendationKind.ChangeStimulus => recommendation.RepetitionRangeHigh is null
                ? $"Seit {recommendation.SessionsSinceBest} Trainings kein neuer Bestwert: Wiederholungsbereich oder Übungsvariante wechseln."
                : $"Oberes Ende von {range} erreicht: schwerere Variante wählen oder Unterstützung verringern.",
            _ => "Noch keine Arbeitssätze im Zeitraum: keine Empfehlung.",
        };
    }

    /// <summary>Up to two decimals with German comma and thousands dot, e.g. "1.002,5".</summary>
    public static string FormatNumber(decimal value) =>
        decimal.Round(value, 2, MidpointRounding.AwayFromZero).ToString("#,##0.##", GermanNumbers);

    private static string Kg(decimal value) => $"{FormatNumber(value)} kg";

    private static long Cents(decimal value) => (long)decimal.Round(value * 100m, 0, MidpointRounding.AwayFromZero);

    private static decimal? Percent(decimal? from, decimal? to) =>
        from is { } first && to is { } last && first != 0m ? (last - first) / first * 100m : null;

    /// <summary>Collects the sessions of one exercise and analyzes them.</summary>
    private sealed class ExerciseCollector(Guid exerciseId)
    {
        private readonly List<AnalysisSession> sessions = [];
        private readonly SortedSet<long> loggedCents = [];
        private readonly List<WorkingSet> current = [];

        public string Name { get; private set; } = string.Empty;

        public ExerciseType Type { get; private set; }

        public void AddBlock(TrainingBlockInput block, ExerciseFactorInput? factor, decimal? bodyweightKg)
        {
            Name = block.Name ?? Name;
            Type = block.ExerciseType;
            decimal bodyweightFactor = factor?.BodyweightFactor ?? ExerciseFactors.DefaultBodyweightFactor(block.ExerciseType);
            decimal weightFactor = factor?.WeightFactor ?? 1m;
            foreach (TrainingSetInput set in block.Sets)
            {
                if (set.SetType == WorkoutSetType.Warmup || !TrainingStatistics.IsRecorded(set, block.ExerciseType)) continue;
                decimal effective = TrainingStatistics.EffectiveWeightKg(
                    block.ExerciseType, set.WeightKg, bodyweightFactor, weightFactor, bodyweightKg);
                current.Add(new WorkingSet(effective, set.Repetitions!.Value, set.WeightKg, set.Rir));
                if (set.WeightKg is { } logged) loggedCents.Add(Cents(logged));
            }
        }

        public void EndWorkout(Guid workoutId, DateOnly day)
        {
            if (current.Count == 0) return;
            long topCents = current.Max(set => Cents(set.EffectiveWeightKg));
            WorkingSet[] top = current.Where(set => Cents(set.EffectiveWeightKg) == topCents).ToArray();
            sessions.Add(new AnalysisSession(
                workoutId,
                day,
                current.Count,
                current.Sum(set => new RecordedSet(set.EffectiveWeightKg, set.Repetitions).VolumeKg),
                current.Max(set => new RecordedSet(set.EffectiveWeightKg, set.Repetitions).EstimatedOneRepMaxKg),
                current.Max(set => set.EffectiveWeightKg),
                top.Min(set => set.Repetitions),
                top.Max(set => set.Repetitions),
                TrainingStatistics.MaxOrNull(top.Select(set => set.LoggedWeightKg)),
                current.Count(set => set.Rir is not null),
                current.Count(set => set.Rir is <= 0m)));
            current.Clear();
        }

        public ExerciseAnalysis Analyze(int days)
        {
            decimal weeks = days / 7m;
            int count = sessions.Count;
            Thirds e1rm = Thirds.Of(sessions.Select(item => item.EstimatedOneRepMaxKg).ToArray());
            Thirds topWeight = Thirds.Of(sessions.Select(item => item.TopWeightKg).ToArray());
            Thirds reps = Thirds.Of(sessions.Select(item => (decimal)item.TopSetMaxRepetitions).ToArray());
            Thirds volume = Thirds.Of(sessions.Select(item => item.VolumeKg).ToArray());
            int sinceBest = SessionsSinceBest();
            decimal? e1rmChange = Percent(e1rm.First, e1rm.Last);
            ExerciseProgressStatus status = StatusOf(count, e1rmChange, sinceBest);
            List<FatigueSignal> fatigue = Fatigue.Of(sessions);
            TrainingRecommendation recommendation = Recommendations.Of(
                sessions, Type, status, fatigue.Count > 0, sinceBest, StepCents());
            return new ExerciseAnalysis(
                exerciseId,
                Name,
                Type,
                sessions,
                count == 0 ? null : sessions.Max(item => item.EstimatedOneRepMaxKg),
                sinceBest,
                e1rm.First,
                e1rm.Last,
                e1rmChange,
                Percent(topWeight.First, topWeight.Last),
                reps.First is { } firstReps && reps.Last is { } lastReps ? lastReps - firstReps : null,
                Percent(volume.First, volume.Last),
                sessions.Sum(item => item.VolumeKg) / weeks,
                sessions.Sum(item => item.WorkingSets) / weeks,
                status,
                fatigue,
                recommendation);
        }

        /// <summary>Sessions after the first one that reached the period's best estimated one-rep max.</summary>
        private int SessionsSinceBest()
        {
            if (sessions.Count == 0) return 0;
            decimal best = sessions.Max(item => item.EstimatedOneRepMaxKg);
            return sessions.Count - 1 - sessions.FindIndex(item => item.EstimatedOneRepMaxKg == best);
        }

        private static ExerciseProgressStatus StatusOf(int count, decimal? e1rmChange, int sinceBest)
        {
            const decimal threshold = 2.5m;
            if (count < MinimumSessions || e1rmChange is not { } change) return ExerciseProgressStatus.InsufficientData;
            if (change <= -threshold) return ExerciseProgressStatus.Regressing;
            return change >= threshold && sinceBest < MinimumSessions
                ? ExerciseProgressStatus.Progressing
                : ExerciseProgressStatus.Stagnating;
        }

        /// <summary>Smallest positive difference of the logged weights in the period, at most 2.5 kg; 2.5 kg without one.</summary>
        private long StepCents()
        {
            long step = DefaultStepCents;
            long? previous = null;
            foreach (long cents in loggedCents)
            {
                if (previous is { } before && cents - before < step) step = cents - before;
                previous = cents;
            }
            return step;
        }
    }

    private sealed record WorkingSet(decimal EffectiveWeightKg, int Repetitions, decimal? LoggedWeightKg, decimal? Rir);

    /// <summary>Mean of the first and of the last third (at least one session each); null for fewer than two values.</summary>
    private sealed record Thirds(decimal? First, decimal? Last)
    {
        public static Thirds Of(decimal[] values)
        {
            if (values.Length < 2) return new Thirds(null, null);
            int size = Math.Max(1, values.Length / 3);
            return new Thirds(values.Take(size).Average(), values.Skip(values.Length - size).Average());
        }
    }

    private static class Fatigue
    {
        public static List<FatigueSignal> Of(List<AnalysisSession> sessions)
        {
            var signals = new List<FatigueSignal>();
            if (DecliningRepetitions(sessions) is { } declining) signals.Add(declining);
            if (FailureOnMostSets(sessions) is { } failure) signals.Add(failure);
            if (VolumeAndStrengthDrop(sessions) is { } drop) signals.Add(drop);
            return signals;
        }

        private static FatigueSignal? DecliningRepetitions(List<AnalysisSession> sessions)
        {
            if (sessions.Count < MinimumSessions) return null;
            AnalysisSession first = sessions[^3];
            AnalysisSession second = sessions[^2];
            AnalysisSession last = sessions[^1];
            bool sameOrLower = Cents(second.TopWeightKg) <= Cents(first.TopWeightKg)
                && Cents(last.TopWeightKg) <= Cents(second.TopWeightKg);
            bool falling = second.TopSetMaxRepetitions < first.TopSetMaxRepetitions
                && last.TopSetMaxRepetitions < second.TopSetMaxRepetitions;
            return sameOrLower && falling
                ? new FatigueSignal(FatigueSignalKind.DecliningRepetitions, MinimumSessions,
                    FromRepetitions: first.TopSetMaxRepetitions, ToRepetitions: last.TopSetMaxRepetitions,
                    WeightKg: last.TopWeightKg)
                : null;
        }

        private static FatigueSignal? FailureOnMostSets(List<AnalysisSession> sessions)
        {
            const int sessionCount = 2;
            if (sessions.Count < sessionCount) return null;
            bool failing = sessions.Skip(sessions.Count - sessionCount)
                .All(item => item.RatedSets >= 2 && item.ZeroRirSets * 2 > item.RatedSets);
            AnalysisSession last = sessions[^1];
            return failing
                ? new FatigueSignal(FatigueSignalKind.FailureOnMostSets, sessionCount,
                    ZeroRirSets: last.ZeroRirSets, RatedSets: last.RatedSets)
                : null;
        }

        /// <summary>Last session against the mean of up to three sessions before it.</summary>
        private static FatigueSignal? VolumeAndStrengthDrop(List<AnalysisSession> sessions)
        {
            const decimal volumeDrop = -20m;
            const decimal strengthDrop = -5m;
            if (sessions.Count < MinimumSessions) return null;
            AnalysisSession last = sessions[^1];
            AnalysisSession[] before = sessions.Take(sessions.Count - 1).TakeLast(MinimumSessions).ToArray();
            decimal? volume = Percent(before.Average(item => item.VolumeKg), last.VolumeKg);
            decimal? e1rm = Percent(before.Average(item => item.EstimatedOneRepMaxKg), last.EstimatedOneRepMaxKg);
            return volume <= volumeDrop && e1rm <= strengthDrop
                ? new FatigueSignal(FatigueSignalKind.VolumeAndStrengthDrop, before.Length + 1,
                    VolumeChangePercent: volume, EstimatedOneRepMaxChangePercent: e1rm)
                : null;
        }
    }

    private static class Recommendations
    {
        public static TrainingRecommendation Of(
            List<AnalysisSession> sessions,
            ExerciseType type,
            ExerciseProgressStatus status,
            bool fatigued,
            int sinceBest,
            long stepCents)
        {
            if (sessions.Count == 0) return new TrainingRecommendation(RecommendationKind.NoRecommendation);
            AnalysisSession last = sessions[^1];
            bool weighted = type is ExerciseType.Strength or ExerciseType.BodyweightLoaded;
            decimal? step = weighted ? stepCents / 100m : null;
            decimal? logged = weighted ? last.TopLoggedWeightKg : null;
            if (fatigued || status == ExerciseProgressStatus.Regressing)
            {
                return new TrainingRecommendation(RecommendationKind.Deload, DeloadWeight(logged, stepCents),
                    WeightStepKg: step, SessionsSinceBest: sinceBest);
            }
            if (status == ExerciseProgressStatus.Stagnating && sinceBest >= SessionsForChangeStimulus)
            {
                return new TrainingRecommendation(RecommendationKind.ChangeStimulus, WeightStepKg: step,
                    SessionsSinceBest: sinceBest);
            }
            return DoubleProgression(last, weighted, logged, step, sinceBest);
        }

        /// <summary>Double progression in the range of the last session's best top set.</summary>
        private static TrainingRecommendation DoubleProgression(
            AnalysisSession last,
            bool weighted,
            decimal? logged,
            decimal? step,
            int sinceBest)
        {
            (int low, int high) = last.TopSetMaxRepetitions switch
            {
                <= 5 => (3, 5),
                <= 12 => (6, 12),
                _ => (13, 20),
            };
            int reps = last.TopSetMinRepetitions;
            RecommendationKind kind;
            decimal? weight = logged;
            int? target;
            if (reps >= high && weighted)
            {
                (kind, weight, target) = (RecommendationKind.IncreaseWeight, (logged ?? 0m) + step, low);
            }
            else if (reps >= high)
            {
                (kind, target) = (RecommendationKind.ChangeStimulus, null);
            }
            else if (reps < low)
            {
                (kind, target) = (RecommendationKind.KeepWeight, low);
            }
            else
            {
                (kind, target) = (RecommendationKind.IncreaseReps, reps + 1);
            }
            return new TrainingRecommendation(kind, weight, target, low, high, step, sinceBest);
        }

        /// <summary>90 % of the logged weight, rounded down to the step; null without a positive result.</summary>
        private static decimal? DeloadWeight(decimal? logged, long stepCents)
        {
            if (logged is not { } weight) return null;
            long target = Cents(weight) * 9 / (10 * stepCents) * stepCents;
            return target > 0 ? target / 100m : null;
        }
    }

    private static class Overall
    {
        public static TrainingAnalysisOverall Of(ExerciseAnalysis[] analyses, DateOnly start, DateOnly today)
        {
            int days = today.DayNumber - start.DayNumber + 1;
            int count = (days + 6) / 7;
            var volume = new decimal[count];
            var sets = new int[count];
            foreach (AnalysisSession session in analyses.SelectMany(item => item.Sessions))
            {
                int index = (session.Day.DayNumber - start.DayNumber) / 7;
                volume[index] += session.VolumeKg;
                sets[index] += session.WorkingSets;
            }
            AnalysisWeek[] weeks = Enumerable.Range(0, count)
                .Select(index => new AnalysisWeek(
                    start.AddDays(7 * index), start.AddDays(7 * index + 6) <= today, volume[index], sets[index]))
                .ToArray();
            decimal[] complete = weeks.Where(item => item.Complete).Select(item => item.VolumeKg).ToArray();
            Thirds thirds = Thirds.Of(complete);
            int eligible = analyses.Count(item => item.Sessions.Count >= MinimumSessions);
            int fatigued = analyses.Count(item => item.FatigueSignals.Count > 0);
            return new TrainingAnalysisOverall(
                weeks,
                Percent(thirds.First, thirds.Last),
                fatigued,
                eligible,
                fatigued > 0 && fatigued * 3 >= eligible);
        }
    }
}
