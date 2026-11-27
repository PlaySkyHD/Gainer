using Gainer.Core.Insights;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Loads the inputs of <see cref="TrainingStatistics"/> for the insight and analysis queries.</summary>
internal static class TrainingInputQueries
{
    /// <summary>Beendete, nicht gelöschte Trainings mit Blöcken; Blöcke optional auf Übungen begrenzt.</summary>
    public static async Task<List<TrainingWorkoutInput>> FinishedWorkoutsAsync(
        this AppDbContext context,
        DateTime? fromUtc,
        DateTime? toUtc,
        IReadOnlyCollection<Guid>? exerciseIds,
        CancellationToken cancellationToken)
    {
        IQueryable<Workout> query = context.Workouts.AsNoTracking()
            .Where(item => item.EndedAtUtc != null && item.DeletedAtUtc == null);
        if (toUtc is { } to) query = query.Where(item => item.EndedAtUtc < to);
        if (fromUtc is { } from) query = query.Where(item => item.EndedAtUtc >= from);
        var workouts = await query
            .Select(item => new { item.Id, item.StartedAtUtc, item.EndedAtUtc })
            .ToListAsync(cancellationToken);

        Guid[] workoutIds = workouts.Select(item => item.Id).ToArray();
        IQueryable<WorkoutExercise> blockQuery = context.WorkoutExercises.AsNoTracking()
            .Where(item => workoutIds.Contains(item.WorkoutId));
        if (exerciseIds is not null) blockQuery = blockQuery.Where(item => exerciseIds.Contains(item.SourceExerciseId));
        var blocks = await blockQuery
            .OrderBy(item => item.Position)
            .Select(item => new { item.Id, item.WorkoutId, item.SourceExerciseId, item.ExerciseTypeSnapshot })
            .ToListAsync(cancellationToken);

        Guid[] blockIds = blocks.Select(item => item.Id).ToArray();
        var sets = await context.WorkoutSets.AsNoTracking()
            .Where(item => blockIds.Contains(item.WorkoutExerciseId))
            .OrderBy(item => item.Position)
            .Select(item => new { item.WorkoutExerciseId, item.SetType, item.WeightKg, item.Repetitions })
            .ToListAsync(cancellationToken);

        ILookup<Guid, TrainingSetInput> setsByBlock = sets.ToLookup(
            item => item.WorkoutExerciseId,
            item => new TrainingSetInput(item.SetType, item.WeightKg, item.Repetitions));
        ILookup<Guid, TrainingBlockInput> blocksByWorkout = blocks.ToLookup(
            item => item.WorkoutId,
            item => new TrainingBlockInput(item.Id, item.SourceExerciseId, item.ExerciseTypeSnapshot,
                setsByBlock[item.Id].ToArray()));
        return workouts.Select(item => new TrainingWorkoutInput(
            item.Id,
            item.StartedAtUtc,
            item.EndedAtUtc,
            DeletedAtUtc: null,
            blocksByWorkout[item.Id].ToArray())).ToList();
    }

    /// <summary>Katalogfaktoren der Übungen: Basiskatalog oder eigene Übungen des Nutzers.</summary>
    public static async Task<Dictionary<Guid, ExerciseFactorInput>> ExerciseFactorsAsync(
        this AppDbContext context,
        IEnumerable<TrainingWorkoutInput> workouts,
        Guid userId,
        CancellationToken cancellationToken)
    {
        Guid[] exerciseIds = workouts
            .SelectMany(workout => workout.Exercises)
            .Select(block => block.SourceExerciseId)
            .Distinct()
            .ToArray();
        if (exerciseIds.Length == 0) return new Dictionary<Guid, ExerciseFactorInput>();
        List<ExerciseFactorInput> rows = await context.Exercises.AsNoTracking()
            .Where(item => exerciseIds.Contains(item.Id) && (item.OwnerUserId == null || item.OwnerUserId == userId))
            .Select(item => new ExerciseFactorInput(item.Id, item.BodyweightFactor, item.WeightFactor))
            .ToListAsync(cancellationToken);
        return rows.ToDictionary(item => item.ExerciseId);
    }
}
