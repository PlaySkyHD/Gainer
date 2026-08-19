using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class WorkoutHistoryQueries(AppDbContext context) : IWorkoutHistoryQueries
{
    public async Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(
        int offset,
        int limit,
        CancellationToken cancellationToken = default)
    {
        if (offset < 0 || limit is < 1 or > 100) throw new ArgumentOutOfRangeException(nameof(limit));
        return await context.Workouts.AsNoTracking()
            .Where(item => item.Status == WorkoutStatus.Completed)
            .OrderByDescending(item => item.CompletedAtUtc)
            .ThenByDescending(item => item.Id)
            .Skip(offset).Take(limit)
            .Select(item => new WorkoutHistorySummary(
                item.Id,
                item.TemplateNameSnapshot,
                item.StartedAtUtc,
                item.CompletedAtUtc!.Value,
                context.WorkoutSets.Count(set => set.WorkoutId == item.Id && set.IsCompleted),
                item.Version))
            .ToListAsync(cancellationToken);
    }

    public async Task<WorkoutSnapshot?> GetAsync(Guid workoutId, CancellationToken cancellationToken = default)
    {
        Workout? workout = await context.Workouts.AsNoTracking().SingleOrDefaultAsync(
            item => item.Id == workoutId && item.Status == WorkoutStatus.Completed,
            cancellationToken);
        if (workout is null) return null;
        List<WorkoutExercise> exercises = await context.WorkoutExercises.AsNoTracking()
            .Where(item => item.WorkoutId == workoutId).OrderBy(item => item.Position).ToListAsync(cancellationToken);
        List<WorkoutSet> sets = await context.WorkoutSets.AsNoTracking()
            .Where(item => item.WorkoutId == workoutId).OrderBy(item => item.Position).ToListAsync(cancellationToken);
        return new WorkoutSnapshot(
            workout.Id,
            workout.SourceTemplateId,
            workout.TemplateNameSnapshot,
            workout.Status,
            exercises.Select(exercise => new WorkoutExerciseSnapshotValues(
                exercise.Id,
                exercise.SourceExerciseId,
                exercise.ExerciseNameSnapshot,
                exercise.PlannedSets,
                exercise.MinimumRepetitions,
                exercise.MaximumRepetitions,
                exercise.TargetRir,
                exercise.RestSeconds,
                exercise.Notes,
                sets.Where(set => set.WorkoutExerciseId == exercise.Id).OrderBy(set => set.Position)
                    .Select(set => new WorkoutSetSnapshotValues(
                        set.Id, set.WeightKg, set.Repetitions, set.Rir, set.Notes, set.IsCompleted, set.CompletedAtUtc))
                    .ToList())).ToList(),
            workout.StartedAtUtc,
            workout.CompletedAtUtc,
            workout.DiscardedAtUtc,
            workout.UpdatedAtUtc,
            workout.Version);
    }
}
