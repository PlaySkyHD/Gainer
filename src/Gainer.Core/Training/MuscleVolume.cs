using Gainer.Core.Insights;

namespace Gainer.Core.Training;

public enum MuscleRole
{
    Primary,
    Secondary,
}

/// <summary>Color level of a set count on the app's muscle map.</summary>
public enum MuscleLevel
{
    None,
    Low,
    Medium,
    High,
    VeryHigh,
}

/// <summary>An exercise with its muscles; unknown keys and repetitions are dropped as in the app.</summary>
public sealed record MuscleExerciseInput(
    Guid ExerciseId,
    string Name,
    IReadOnlyList<string> PrimaryMuscles,
    IReadOnlyList<string> SecondaryMuscles);

public sealed record PlannedSetsInput(Guid PlanId, bool Archived, IReadOnlyList<PlannedExerciseSets> Entries);

public sealed record PlannedExerciseSets(Guid ExerciseId, int WorkingSets);

public sealed record MuscleBlockInput(
    Guid SourceExerciseId,
    string NameSnapshot,
    ExerciseType ExerciseType,
    IReadOnlyList<TrainingSetInput> Sets);

public sealed record MuscleWorkoutInput(
    DateTime StartedAtUtc,
    DateTime? EndedAtUtc,
    DateTime? DeletedAtUtc,
    IReadOnlyList<MuscleBlockInput> Blocks);

public sealed record MuscleContribution(Guid ExerciseId, string ExerciseName, MuscleRole Role, decimal WorkingSets)
{
    /// <summary>Weighted sets for the muscle: secondary muscles count half.</summary>
    public decimal Sets => Role == MuscleRole.Primary ? WorkingSets : WorkingSets * 0.5m;
}

public sealed record MuscleSets(string Muscle, decimal Sets, MuscleLevel Level, IReadOnlyList<MuscleContribution> Contributions);

public sealed record ExerciseReference(Guid ExerciseId, string Name);

/// <summary>All muscles ranked by sets, and the exercises that could not be assigned to a muscle.</summary>
public sealed record MuscleVolumeSnapshot(IReadOnlyList<MuscleSets> Muscles, IReadOnlyList<ExerciseReference> ExercisesWithoutMuscles);

/// <summary>
/// Port of the app's muscle map (<c>MuscleVolume.fromPlans/fromWorkouts</c> and <c>MuscleLevel.of</c> in
/// muscle_volume.dart); the rules are in contracts/fixtures/muscle-volume.json.
/// </summary>
public static class MuscleVolume
{
    public const string FallbackExerciseName = "Übung";

    public static MuscleLevel LevelOf(decimal sets) => sets switch
    {
        <= 0 => MuscleLevel.None,
        < 4 => MuscleLevel.Low,
        < 10 => MuscleLevel.Medium,
        <= 20 => MuscleLevel.High,
        _ => MuscleLevel.VeryHigh,
    };

    /// <summary>Working sets per plan entry; archived plans do not count.</summary>
    public static MuscleVolumeSnapshot FromPlans(
        IEnumerable<PlannedSetsInput> plans,
        IReadOnlyDictionary<Guid, MuscleExerciseInput> exercises)
    {
        var builder = new Builder(exercises);
        foreach (PlannedExerciseSets entry in plans.Where(plan => !plan.Archived).SelectMany(plan => plan.Entries))
        {
            builder.Add(entry.ExerciseId, null, entry.WorkingSets);
        }
        return builder.Build();
    }

    /// <summary>
    /// Recorded working sets of completed workouts that started in [<paramref name="fromUtc"/>,
    /// <paramref name="toUtc"/>), divided by <paramref name="weeks"/> (average per week).
    /// </summary>
    public static MuscleVolumeSnapshot FromWorkouts(
        IEnumerable<MuscleWorkoutInput> workouts,
        IReadOnlyDictionary<Guid, MuscleExerciseInput> exercises,
        DateTime fromUtc,
        DateTime toUtc,
        int weeks)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(weeks, 1);
        var builder = new Builder(exercises);
        foreach (MuscleWorkoutInput workout in workouts.Where(item => CountsInRange(item, fromUtc, toUtc)))
        {
            foreach (MuscleBlockInput block in workout.Blocks)
            {
                int sets = block.Sets.Count(set =>
                    set.SetType != WorkoutSetType.Warmup && TrainingStatistics.IsRecorded(set, block.ExerciseType));
                if (sets > 0) builder.Add(block.SourceExerciseId, block.NameSnapshot, (decimal)sets / weeks);
            }
        }
        return builder.Build();
    }

    private static bool CountsInRange(MuscleWorkoutInput workout, DateTime fromUtc, DateTime toUtc) =>
        workout.EndedAtUtc is not null && workout.DeletedAtUtc is null
            && workout.StartedAtUtc >= fromUtc && workout.StartedAtUtc < toUtc;

    private sealed class Builder(IReadOnlyDictionary<Guid, MuscleExerciseInput> exercises)
    {
        private readonly Dictionary<Guid, decimal> sets = [];
        private readonly Dictionary<Guid, string> names = [];
        private readonly List<Guid> order = [];

        private static string[] Known(IEnumerable<string> keys) =>
            keys.Where(MuscleKeys.IsKnown).Distinct(StringComparer.Ordinal).ToArray();

        public void Add(Guid exerciseId, string? fallbackName, decimal workingSets)
        {
            if (workingSets <= 0) return;
            if (!sets.TryGetValue(exerciseId, out decimal current))
            {
                order.Add(exerciseId);
                names[exerciseId] = exercises.GetValueOrDefault(exerciseId)?.Name ?? fallbackName ?? FallbackExerciseName;
            }
            sets[exerciseId] = current + workingSets;
        }

        public MuscleVolumeSnapshot Build()
        {
            var contributions = new Dictionary<string, List<MuscleContribution>>(StringComparer.Ordinal);
            var withoutMuscles = new List<ExerciseReference>();
            foreach (Guid id in order)
            {
                string name = names[id];
                string[] primary = Known(exercises.GetValueOrDefault(id)?.PrimaryMuscles ?? []);
                string[] secondary = Known(exercises.GetValueOrDefault(id)?.SecondaryMuscles ?? []);
                if (primary.Length == 0 && secondary.Length == 0)
                {
                    withoutMuscles.Add(new ExerciseReference(id, name));
                    continue;
                }
                foreach (string muscle in primary) Put(contributions, muscle, new MuscleContribution(id, name, MuscleRole.Primary, sets[id]));
                foreach (string muscle in secondary) Put(contributions, muscle, new MuscleContribution(id, name, MuscleRole.Secondary, sets[id]));
            }

            List<MuscleSets> muscles = MuscleKeys.Known
                .Select((muscle, index) =>
                {
                    IReadOnlyList<MuscleContribution> list = contributions.TryGetValue(muscle, out List<MuscleContribution>? items)
                        ? items
                            .OrderByDescending(item => item.Sets)
                            .ThenBy(item => item.ExerciseName, StringComparer.Ordinal)
                            .ToList()
                        : [];
                    decimal total = list.Sum(item => item.Sets);
                    return (Index: index, Sets: new MuscleSets(muscle, total, LevelOf(total), list));
                })
                .OrderByDescending(item => item.Sets.Sets)
                .ThenBy(item => item.Index)
                .Select(item => item.Sets)
                .ToList();
            return new MuscleVolumeSnapshot(
                muscles,
                withoutMuscles.OrderBy(item => item.Name.ToLowerInvariant(), StringComparer.Ordinal).ToList());
        }

        private static void Put(Dictionary<string, List<MuscleContribution>> map, string muscle, MuscleContribution contribution)
        {
            if (!map.TryGetValue(muscle, out List<MuscleContribution>? list))
            {
                list = [];
                map[muscle] = list;
            }
            list.Add(contribution);
        }
    }
}
