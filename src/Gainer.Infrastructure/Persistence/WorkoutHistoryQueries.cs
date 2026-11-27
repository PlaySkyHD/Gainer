using Gainer.Core.Insights;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class WorkoutHistoryQueries(AppDbContext context) : IWorkoutHistoryQueries
{
    public Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(
        int offset,
        int limit,
        CancellationToken cancellationToken = default) =>
        ListAsync(range: null, offset, limit, cancellationToken);

    public async Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(
        WorkoutHistoryRange? range,
        int offset,
        int limit,
        CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(offset);
        ArgumentOutOfRangeException.ThrowIfLessThan(limit, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(limit, 100);
        IQueryable<Workout> workouts = context.Workouts.AsNoTracking()
            .Where(item => item.EndedAtUtc != null && item.DeletedAtUtc == null);
        if (range is not null)
        {
            ArgumentOutOfRangeException.ThrowIfLessThan(range.Through, range.From);
            DateTime fromUtc = LocalDays.StartOfDayUtc(range.From, range.TimeZone);
            DateTime beforeUtc = LocalDays.StartOfDayUtc(range.Through.AddDays(1), range.TimeZone);
            workouts = workouts.Where(item => item.StartedAtUtc >= fromUtc && item.StartedAtUtc < beforeUtc);
        }

        // Die Satzregel in der Zählung unten spiegelt TrainingStatistics.IsRecorded (Core): Wiederholungen >= 1,
        // Gewicht nur bei Kraft- und Assisted-Übungen nötig. Beide Stellen gemeinsam pflegen.
        return await workouts
            .OrderByDescending(item => item.EndedAtUtc)
            .ThenByDescending(item => item.Id)
            .Skip(offset).Take(limit)
            .Select(item => new WorkoutHistorySummary(
                item.Id,
                item.Title,
                item.StartedAtUtc,
                item.EndedAtUtc!.Value,
                (from set in context.WorkoutSets
                 join block in context.WorkoutExercises on set.WorkoutExerciseId equals block.Id
                 where set.WorkoutId == item.Id
                    && set.SetType != WorkoutSetType.Warmup
                    && set.Repetitions >= 1
                    && (set.WeightKg != null
                        || (block.ExerciseTypeSnapshot != ExerciseType.Strength
                            && block.ExerciseTypeSnapshot != ExerciseType.Assisted))
                 select set.Id).Count(),
                item.Version,
                item.SourcePlanId))
            .ToListAsync(cancellationToken);
    }

    public async Task<WorkoutSnapshot?> GetAsync(Guid workoutId, CancellationToken cancellationToken = default)
    {
        Workout? workout = await context.Workouts.AsNoTracking().SingleOrDefaultAsync(
            item => item.Id == workoutId && item.DeletedAtUtc == null,
            cancellationToken);
        if (workout is null) return null;
        List<WorkoutExercise> exercises = await context.WorkoutExercises.AsNoTracking()
            .Where(item => item.WorkoutId == workoutId).OrderBy(item => item.Position).ToListAsync(cancellationToken);
        List<WorkoutSet> sets = await context.WorkoutSets.AsNoTracking()
            .Where(item => item.WorkoutId == workoutId).OrderBy(item => item.Position).ToListAsync(cancellationToken);
        return WorkoutSnapshots.Create(workout, WorkoutSnapshots.ToExerciseValues(exercises, sets));
    }
}
