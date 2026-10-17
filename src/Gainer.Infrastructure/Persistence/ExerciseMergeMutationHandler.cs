using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

/// <summary>
/// Repoints the user's workout blocks and plan entries to the target and archives the source. The caller's sync
/// transaction makes the rewrite, the new versions and the change snapshots one atomic unit.
/// </summary>
public sealed class ExerciseMergeMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null)
{
    public async Task<MergeExercisesResult> MergeAsync(
        MergeExercisesMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;

        Exercise source = await context.Exercises.SingleOrDefaultAsync(
            item => item.Id == mutation.SourceExerciseId && item.OwnerUserId == userId && !item.IsArchived,
            cancellationToken) ?? throw new CustomExerciseNotFoundException();
        Exercise target = await context.Exercises.SingleOrDefaultAsync(
            item => item.Id == mutation.TargetExerciseId
                && (item.OwnerUserId == null || item.OwnerUserId == userId)
                && !item.IsArchived,
            cancellationToken) ?? throw new CustomExerciseNotFoundException();
        if (source.Version != mutation.SourceBaseVersion
            || (target.OwnerUserId is not null && target.Version != mutation.TargetBaseVersion))
        {
            throw new CustomExerciseConflictException("The merge is based on an outdated exercise version.");
        }

        int workoutCount = await RepointWorkoutBlocksAsync(userId, source.Id, target.Id, now, cancellationToken);
        int planCount = await RepointPlanEntriesAsync(userId, source.Id, target.Id, now, cancellationToken);

        source.IsArchived = true;
        source.UpdatedAtUtc = now;
        source.Version++;
        Guid[] sourceCategoryIds = await context.ExerciseCategoryAssignments.AsNoTracking()
            .Where(item => item.ExerciseId == source.Id)
            .Select(item => item.CategoryId)
            .OrderBy(item => item)
            .ToArrayAsync(cancellationToken);
        changeCollector?.CaptureUpsert(CustomExerciseMutationHandler.Snapshot(source, sourceCategoryIds));

        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new CustomExerciseConflictException("The exercises changed concurrently.");
        }
        return new MergeExercisesResult(workoutCount, planCount);
    }

    private async Task<int> RepointWorkoutBlocksAsync(
        Guid userId,
        Guid sourceId,
        Guid targetId,
        DateTime now,
        CancellationToken cancellationToken)
    {
        List<WorkoutExercise> blocks = await context.WorkoutExercises
            .Where(item => item.UserId == userId && item.SourceExerciseId == sourceId)
            .ToListAsync(cancellationToken);
        Guid[] workoutIds = blocks.Select(item => item.WorkoutId).Distinct().ToArray();
        List<Workout> workouts = await context.Workouts
            .Where(item => item.UserId == userId && workoutIds.Contains(item.Id))
            .OrderBy(item => item.StartedAtUtc)
            .ToListAsync(cancellationToken);
        List<WorkoutExercise> exercises = await context.WorkoutExercises
            .Where(item => workoutIds.Contains(item.WorkoutId))
            .ToListAsync(cancellationToken);
        List<WorkoutSet> sets = await context.WorkoutSets
            .Where(item => workoutIds.Contains(item.WorkoutId))
            .ToListAsync(cancellationToken);

        foreach (WorkoutExercise block in blocks)
        {
            block.SourceExerciseId = targetId;
        }
        foreach (Workout workout in workouts)
        {
            workout.UpdatedAtUtc = now;
            workout.Version++;
            IReadOnlyList<WorkoutExerciseValues> values = WorkoutSnapshots.ToExerciseValues(
                exercises.Where(item => item.WorkoutId == workout.Id).ToList(),
                sets.Where(item => item.WorkoutId == workout.Id).ToList());
            changeCollector?.CaptureUpsert(WorkoutSnapshots.Create(workout, values));
        }
        return workouts.Count;
    }

    private async Task<int> RepointPlanEntriesAsync(
        Guid userId,
        Guid sourceId,
        Guid targetId,
        DateTime now,
        CancellationToken cancellationToken)
    {
        List<TrainingPlanEntry> sourceEntries = await context.TrainingPlanEntries
            .Where(item => item.UserId == userId && item.ExerciseId == sourceId)
            .ToListAsync(cancellationToken);
        Guid[] planIds = sourceEntries.Select(item => item.PlanId).Distinct().ToArray();
        List<TrainingPlan> plans = await context.TrainingPlans
            .Where(item => item.UserId == userId && planIds.Contains(item.Id))
            .OrderBy(item => item.SortOrder)
            .ToListAsync(cancellationToken);
        List<TrainingPlanEntry> entries = await context.TrainingPlanEntries
            .Where(item => planIds.Contains(item.PlanId))
            .OrderBy(item => item.Position)
            .ToListAsync(cancellationToken);

        foreach (TrainingPlanEntry entry in sourceEntries)
        {
            entry.ExerciseId = targetId;
        }
        foreach (TrainingPlan plan in plans)
        {
            plan.UpdatedAtUtc = now;
            plan.Version++;
            var values = entries
                .Where(item => item.PlanId == plan.Id)
                .Select(item => new TrainingPlanEntryValues(
                    item.Id, item.ExerciseId, item.WarmupSets, item.WorkingSets, item.Notes, item.SupersetId))
                .ToList();
            changeCollector?.CaptureUpsert(new TrainingPlanSnapshot(
                plan.Id,
                plan.Name,
                plan.Notes,
                PreviousValueSources.ToStorageValue(plan.PreviousValueSource),
                values,
                plan.SortOrder,
                plan.IsArchived,
                plan.CreatedAtUtc,
                plan.UpdatedAtUtc,
                plan.Version));
        }
        return plans.Count;
    }

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");
}
