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

        EnforceExerciseOwnership(context);

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

    private void EnforceExerciseOwnership(DbContext context)
    {
        EntityEntry<Exercise>[] exercises = context.ChangeTracker.Entries<Exercise>()
            .Where(entry => entry.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .ToArray();
        if (exercises.Length == 0)
        {
            return;
        }

        Guid currentUserId = userContext.UserId ?? throw new UserIsolationViolationException();
        foreach (EntityEntry<Exercise> entry in exercises)
        {
            Guid? originalOwner = entry.State == EntityState.Added
                ? entry.Entity.OwnerUserId
                : entry.OriginalValues.GetValue<Guid?>(nameof(Exercise.OwnerUserId));
            if (originalOwner is null)
            {
                throw new BaseExerciseImmutableException();
            }
            if (originalOwner != currentUserId || entry.Entity.OwnerUserId != currentUserId)
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
