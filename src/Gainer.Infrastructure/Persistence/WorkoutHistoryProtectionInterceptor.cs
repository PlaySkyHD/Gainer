using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace Gainer.Infrastructure.Persistence;

internal sealed class WorkoutHistoryProtectionInterceptor : SaveChangesInterceptor
{
    public override InterceptionResult<int> SavingChanges(
        DbContextEventData eventData,
        InterceptionResult<int> result)
    {
        Validate(eventData.Context, isAsync: false).GetAwaiter().GetResult();
        return result;
    }

    public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        await Validate(eventData.Context, isAsync: true, cancellationToken);
        return result;
    }

    private static async Task Validate(
        DbContext? context,
        bool isAsync,
        CancellationToken cancellationToken = default)
    {
        if (context is null) return;
        foreach (EntityEntry<Workout> entry in context.ChangeTracker.Entries<Workout>()
                     .Where(entry => entry.State is EntityState.Modified or EntityState.Deleted))
        {
            WorkoutStatus original = entry.OriginalValues.GetValue<WorkoutStatus>(nameof(Workout.Status));
            if (original != WorkoutStatus.Running) throw new HistoricalWorkoutImmutableException();
        }

        Guid[] changedChildWorkoutIds = context.ChangeTracker.Entries()
            .Where(entry => entry.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .Select(entry => entry.Entity switch
            {
                WorkoutExercise exercise => exercise.WorkoutId,
                WorkoutSet set => set.WorkoutId,
                _ => Guid.Empty,
            })
            .Where(id => id != Guid.Empty)
            .Distinct()
            .ToArray();
        if (changedChildWorkoutIds.Length == 0) return;

        var trackedStatuses = context.ChangeTracker.Entries<Workout>()
            .Where(entry => changedChildWorkoutIds.Contains(entry.Entity.Id))
            .ToDictionary(
                entry => entry.Entity.Id,
                entry => entry.State == EntityState.Added
                    ? WorkoutStatus.Running
                    : entry.OriginalValues.GetValue<WorkoutStatus>(nameof(Workout.Status)));
        Guid[] unresolved = changedChildWorkoutIds.Where(id => !trackedStatuses.ContainsKey(id)).ToArray();
        if (unresolved.Length > 0)
        {
            IQueryable<Workout> query = context.Set<Workout>().AsNoTracking().IgnoreQueryFilters()
                .Where(item => unresolved.Contains(item.Id));
            Dictionary<Guid, WorkoutStatus> stored = isAsync
                ? await query.ToDictionaryAsync(item => item.Id, item => item.Status, cancellationToken)
                : query.ToDictionary(item => item.Id, item => item.Status);
            foreach ((Guid id, WorkoutStatus status) in stored) trackedStatuses[id] = status;
        }
        if (trackedStatuses.Values.Any(status => status != WorkoutStatus.Running))
        {
            throw new HistoricalWorkoutImmutableException();
        }
    }
}
