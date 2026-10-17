using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

public sealed class WorkoutRotationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IWorkoutRotationHandler
{
    private const int MaximumPlans = 100;

    public async Task<WorkoutRotationSnapshot> SaveAsync(
        SaveWorkoutRotationMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        ValidatePlanIds(mutation.PlanIds);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;

        WorkoutRotation rotation;
        if (mutation.BaseVersion == 0)
        {
            if (await context.WorkoutRotations.AnyAsync(cancellationToken))
            {
                throw new WorkoutRotationConflictException("The user already has a workout rotation.");
            }
            await EnsurePlansSelectableAsync(userId, mutation.PlanIds, cancellationToken);
            rotation = new WorkoutRotation
            {
                Id = mutation.RotationId,
                CreatedAtUtc = now,
                UpdatedAtUtc = now,
                Version = 1,
            };
            context.WorkoutRotations.Add(rotation);
        }
        else
        {
            rotation = await context.WorkoutRotations.SingleOrDefaultAsync(
                item => item.Id == mutation.RotationId,
                cancellationToken) ?? throw new WorkoutRotationNotFoundException();
            if (rotation.Version != mutation.BaseVersion)
            {
                throw new WorkoutRotationConflictException("The rotation changed since the supplied base version.");
            }
            await EnsurePlansSelectableAsync(userId, mutation.PlanIds, cancellationToken);
            List<WorkoutRotationItem> existing = await context.WorkoutRotationItems
                .Where(item => item.RotationId == rotation.Id)
                .ToListAsync(cancellationToken);
            // Removals are flushed before the replacement rows are inserted under the same unique positions.
            context.WorkoutRotationItems.RemoveRange(existing);
            await SaveOrConflictAsync(cancellationToken);
            rotation.UpdatedAtUtc = now;
            rotation.Version++;
        }

        for (int position = 0; position < mutation.PlanIds.Count; position++)
        {
            context.WorkoutRotationItems.Add(new WorkoutRotationItem
            {
                Id = Guid.NewGuid(),
                RotationId = rotation.Id,
                PlanId = mutation.PlanIds[position],
                Position = position,
            });
        }
        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);

        var snapshot = new WorkoutRotationSnapshot(
            rotation.Id,
            mutation.PlanIds.ToArray(),
            rotation.UpdatedAtUtc,
            rotation.Version);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    /// <summary>Only own, non-archived plans without duplicates can be part of a rotation.</summary>
    private async Task EnsurePlansSelectableAsync(Guid userId, IReadOnlyList<Guid> planIds, CancellationToken cancellationToken)
    {
        if (planIds.Count == 0)
        {
            return;
        }
        Guid[] ids = planIds.ToArray();
        int selectable = await context.TrainingPlans.AsNoTracking()
            .Where(item => ids.Contains(item.Id) && item.UserId == userId && !item.IsArchived)
            .CountAsync(cancellationToken);
        if (selectable != ids.Length)
        {
            throw new WorkoutRotationValidationException(new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["PlanIds"] = "Every plan must belong to the user and must not be archived.",
            });
        }
    }

    private static void ValidatePlanIds(IReadOnlyList<Guid> planIds)
    {
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (planIds.Count > MaximumPlans)
        {
            errors[nameof(SaveWorkoutRotationMutation.PlanIds)] = $"A rotation cannot contain more than {MaximumPlans} plans.";
        }
        if (planIds.Any(item => item == Guid.Empty) || planIds.Distinct().Count() != planIds.Count)
        {
            errors[nameof(SaveWorkoutRotationMutation.PlanIds)] = "Plan identifiers must be non-empty and unique.";
        }
        if (errors.Count > 0)
        {
            throw new WorkoutRotationValidationException(errors);
        }
    }

    private async Task SaveOrConflictAsync(CancellationToken cancellationToken)
    {
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new WorkoutRotationConflictException("The rotation changed concurrently.");
        }
        catch (DbUpdateException)
        {
            throw new WorkoutRotationConflictException("The rotation conflicts with stored data.");
        }
    }

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");
}
