using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace Gainer.Infrastructure.Persistence;

internal sealed class UserOwnershipInterceptor(IUserContext userContext) : SaveChangesInterceptor
{
    public override InterceptionResult<int> SavingChanges(
        DbContextEventData eventData,
        InterceptionResult<int> result)
    {
        ApplyOwnership(eventData.Context);
        return result;
    }

    public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        if (eventData.Context is { } context)
        {
            EntityEntry<ExerciseCategoryAssignment>[] assignments = ChangedAssignments(context);
            if (assignments.Length > 0)
            {
                Dictionary<Guid, Exercise> exercises = await FindAsync<Exercise>(context, assignments, item => item.ExerciseId, cancellationToken);
                Dictionary<Guid, ExerciseCategory> categories = await FindAsync<ExerciseCategory>(context, assignments, item => item.CategoryId, cancellationToken);
                EnforceAssignmentOwnership(assignments, exercises, categories);
            }
        }
        ApplyOwnership(eventData.Context, checkAssignments: false);
        return result;
    }

    internal void ApplyOwnership(DbContext? context) => ApplyOwnership(context, checkAssignments: true);

    private void ApplyOwnership(DbContext? context, bool checkAssignments)
    {
        if (context is null)
        {
            return;
        }

        EnforceCatalogOwnership(context);
        if (checkAssignments)
        {
            EntityEntry<ExerciseCategoryAssignment>[] assignments = ChangedAssignments(context);
            if (assignments.Length > 0)
            {
                EnforceAssignmentOwnership(
                    assignments,
                    Find<Exercise>(context, assignments, item => item.ExerciseId),
                    Find<ExerciseCategory>(context, assignments, item => item.CategoryId));
            }
        }

        EntityEntry<IUserOwnedEntity>[] ownedEntries = context.ChangeTracker.Entries<IUserOwnedEntity>()
            .Where(entry => entry.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .ToArray();
        if (ownedEntries.Length == 0)
        {
            return;
        }

        Guid currentUserId = userContext.UserId ?? throw new UserIsolationViolationException();
        foreach (EntityEntry<IUserOwnedEntity> entry in ownedEntries)
        {
            EnforceOwnership(entry, currentUserId);
        }
    }

    private static EntityEntry<ExerciseCategoryAssignment>[] ChangedAssignments(DbContext context) =>
        context.ChangeTracker.Entries<ExerciseCategoryAssignment>()
            .Where(entry => entry.State is EntityState.Added or EntityState.Deleted)
            .ToArray();

    /// <summary>Own exercises may take base or own, non-archived categories; base exercises are immutable.</summary>
    private void EnforceAssignmentOwnership(
        EntityEntry<ExerciseCategoryAssignment>[] assignments,
        IReadOnlyDictionary<Guid, Exercise> exercises,
        IReadOnlyDictionary<Guid, ExerciseCategory> categories)
    {
        Guid currentUserId = userContext.UserId ?? throw new UserIsolationViolationException();
        foreach (EntityEntry<ExerciseCategoryAssignment> entry in assignments)
        {
            if (!exercises.TryGetValue(entry.Entity.ExerciseId, out Exercise? exercise))
            {
                throw new UserIsolationViolationException();
            }
            if (exercise.OwnerUserId is null)
            {
                throw new BaseExerciseImmutableException();
            }
            if (exercise.OwnerUserId != currentUserId ||
                !categories.TryGetValue(entry.Entity.CategoryId, out ExerciseCategory? category))
            {
                throw new UserIsolationViolationException();
            }
            if (category.OwnerUserId is { } categoryOwner &&
                (categoryOwner != currentUserId || (entry.State == EntityState.Added && category.IsArchived)))
            {
                throw new UserIsolationViolationException();
            }
        }
    }

    private static Dictionary<Guid, TEntity> Find<TEntity>(
        DbContext context,
        EntityEntry<ExerciseCategoryAssignment>[] assignments,
        Func<ExerciseCategoryAssignment, Guid> keyOf)
        where TEntity : class
    {
        var found = new Dictionary<Guid, TEntity>();
        foreach (Guid id in assignments.Select(entry => keyOf(entry.Entity)).Distinct())
        {
            if (context.Find<TEntity>(id) is { } entity)
            {
                found[id] = entity;
            }
        }
        return found;
    }

    private static async Task<Dictionary<Guid, TEntity>> FindAsync<TEntity>(
        DbContext context,
        EntityEntry<ExerciseCategoryAssignment>[] assignments,
        Func<ExerciseCategoryAssignment, Guid> keyOf,
        CancellationToken cancellationToken)
        where TEntity : class
    {
        var found = new Dictionary<Guid, TEntity>();
        foreach (Guid id in assignments.Select(entry => keyOf(entry.Entity)).Distinct())
        {
            if (await context.FindAsync<TEntity>([id], cancellationToken) is { } entity)
            {
                found[id] = entity;
            }
        }
        return found;
    }

    private void EnforceCatalogOwnership(DbContext context)
    {
        EnforceCatalogOwnership<Exercise>(context, item => item.OwnerUserId, nameof(Exercise.OwnerUserId));
        EnforceCatalogOwnership<ExerciseCategory>(context, item => item.OwnerUserId, nameof(ExerciseCategory.OwnerUserId));
    }

    private void EnforceCatalogOwnership<TEntity>(
        DbContext context,
        Func<TEntity, Guid?> ownerOf,
        string ownerProperty)
        where TEntity : class
    {
        EntityEntry<TEntity>[] entries = context.ChangeTracker.Entries<TEntity>()
            .Where(entry => entry.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .ToArray();
        if (entries.Length == 0)
        {
            return;
        }

        Guid currentUserId = userContext.UserId ?? throw new UserIsolationViolationException();
        foreach (EntityEntry<TEntity> entry in entries)
        {
            Guid? originalOwner = entry.State == EntityState.Added
                ? ownerOf(entry.Entity)
                : entry.OriginalValues.GetValue<Guid?>(ownerProperty);
            if (originalOwner is null)
            {
                throw new BaseExerciseImmutableException();
            }
            if (originalOwner != currentUserId || ownerOf(entry.Entity) != currentUserId)
            {
                throw new UserIsolationViolationException();
            }
        }
    }

    private static void EnforceOwnership(EntityEntry<IUserOwnedEntity> entry, Guid currentUserId)
    {
        var owner = entry.Property(entity => entity.UserId);
        if (entry.State == EntityState.Added && (owner.CurrentValue == Guid.Empty || owner.IsTemporary))
        {
            owner.CurrentValue = currentUserId;
            owner.IsTemporary = false;
            return;
        }

        bool ownershipMatches = owner.CurrentValue == currentUserId
                                && (entry.State == EntityState.Added || owner.OriginalValue == currentUserId);
        if (!ownershipMatches)
        {
            throw new UserIsolationViolationException();
        }
    }
}
