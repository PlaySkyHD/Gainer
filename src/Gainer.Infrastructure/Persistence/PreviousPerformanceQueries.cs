using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class PreviousPerformanceQueries(AppDbContext context) : IPreviousPerformanceQueries
{
    public async Task<PreviousExercisePerformance?> GetAsync(
        Guid sourceExerciseId,
        DateTime beforeUtc,
        CancellationToken cancellationToken = default)
    {
        if (sourceExerciseId == Guid.Empty) throw new ArgumentException("Exercise identifier cannot be empty.", nameof(sourceExerciseId));
        if (beforeUtc.Kind != DateTimeKind.Utc) throw new ArgumentException("The cutoff must be UTC.", nameof(beforeUtc));

        var latest = await (
            from exercise in context.WorkoutExercises.AsNoTracking()
            join workout in context.Workouts.AsNoTracking() on exercise.WorkoutId equals workout.Id
            where exercise.SourceExerciseId == sourceExerciseId
                  && workout.EndedAtUtc != null && workout.DeletedAtUtc == null
                  && workout.EndedAtUtc < beforeUtc
                  && context.WorkoutSets.Any(set => set.WorkoutExerciseId == exercise.Id
                      && set.SetType != WorkoutSetType.Warmup
                      && set.WeightKg != null
                      && set.Repetitions > 0)
            orderby workout.EndedAtUtc descending, workout.Id descending
            select new { Workout = workout, Exercise = exercise })
            .FirstOrDefaultAsync(cancellationToken);
        if (latest?.Workout.EndedAtUtc is not { } endedAt) return null;

        List<PreviousSetPerformance> sets = await context.WorkoutSets.AsNoTracking()
            .Where(item => item.WorkoutExerciseId == latest.Exercise.Id
                && item.SetType != WorkoutSetType.Warmup
                && item.WeightKg != null
                && item.Repetitions > 0)
            .OrderBy(item => item.Position)
            .Select(item => new PreviousSetPerformance(
                item.WeightKg!.Value,
                item.Repetitions!.Value,
                item.Rir,
                item.Position))
            .ToListAsync(cancellationToken);
        return new PreviousExercisePerformance(sourceExerciseId, latest.Workout.Id, endedAt, sets);
    }
}
