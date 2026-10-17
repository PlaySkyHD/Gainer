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

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        ApplyOwnership(eventData.Context);
        return ValueTask.FromResult(result);
    }

    internal void ApplyOwnership(DbContext? context)
    {
        if (context is null)
        {
            return;
        }

        EnforceCatalogOwnership(context);

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
