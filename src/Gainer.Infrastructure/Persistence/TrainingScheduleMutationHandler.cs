using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

/// <summary>
/// Saves the user's single training schedule as a complete state. Like the removed rotation, creating a second live
/// schedule (base version 0 while one exists, regardless of its id) is a conflict; the client must update or delete
/// the existing one. Deleting keeps a tombstone row without children, so the same id can be saved again with the
/// tombstone version as base version; the version keeps counting up.
/// </summary>
public sealed class TrainingScheduleMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : ITrainingScheduleMutationHandler
{
    public async Task<TrainingScheduleSnapshot> SaveAsync(
        SaveTrainingScheduleMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        TrainingScheduleValues values = TrainingScheduleValidation.Normalize(mutation.Schedule);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;

        // Also finds the tombstone of a deleted schedule; foreign schedules are hidden by the user filter.
        TrainingSchedule? schedule = await context.TrainingSchedules.SingleOrDefaultAsync(
            item => item.Id == values.ScheduleId,
            cancellationToken);
        if (schedule is null)
        {
            if (mutation.BaseVersion != 0)
            {
                throw new TrainingScheduleNotFoundException();
            }
            await EnsureNoOtherLiveScheduleAsync(values.ScheduleId, cancellationToken);
            await EnsurePlansOwnedAsync(userId, values, cancellationToken);
            schedule = new TrainingSchedule
            {
                Id = values.ScheduleId,
                CreatedAtUtc = now,
                UpdatedAtUtc = now,
                Version = 1,
            };
            Apply(schedule, values);
            context.TrainingSchedules.Add(schedule);
        }
        else
        {
            // Stored versions start at 1, so a create (base version 0) over an existing id or tombstone is a conflict.
            if (schedule.Version != mutation.BaseVersion)
            {
                throw new TrainingScheduleConflictException("The schedule changed since the supplied base version.");
            }
            if (schedule.DeletedAtUtc is not null)
            {
                await EnsureNoOtherLiveScheduleAsync(schedule.Id, cancellationToken);
            }
            await EnsurePlansOwnedAsync(userId, values, cancellationToken);
            // Children are replaced completely; removals are flushed before rows with the same unique keys are inserted.
            await RemoveChildrenAsync(schedule.Id, cancellationToken);
            await SaveOrConflictAsync(cancellationToken);
            Apply(schedule, values);
            schedule.DeletedAtUtc = null;
            schedule.UpdatedAtUtc = now;
            schedule.Version++;
        }

        AddChildren(schedule.Id, values);
        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);

        var snapshot = new TrainingScheduleSnapshot(
            schedule.Id,
            TrainingScheduleModes.ToWireValue(schedule.Mode),
            schedule.AnchorDate,
            schedule.ValidFrom,
            values.Slots,
            values.Shifts,
            values.Exceptions,
            schedule.UpdatedAtUtc,
            schedule.Version);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<long> DeleteAsync(
        DeleteTrainingScheduleMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        TrainingSchedule schedule = await context.TrainingSchedules
            .SingleOrDefaultAsync(item => item.Id == mutation.ScheduleId && item.DeletedAtUtc == null, cancellationToken)
            ?? throw new TrainingScheduleNotFoundException();
        if (schedule.Version != mutation.BaseVersion)
        {
            throw new TrainingScheduleConflictException("The schedule changed since the supplied base version.");
        }

        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;
        // The row stays as a tombstone that remembers the version.
        await RemoveChildrenAsync(schedule.Id, cancellationToken);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        schedule.DeletedAtUtc = now;
        schedule.UpdatedAtUtc = now;
        schedule.Version++;
        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        changeCollector?.CaptureDeletion(ResourceKey.Create(ResourceKind.TrainingSchedule, schedule.Id), schedule.Version);
        return schedule.Version;
    }

    private async Task EnsureNoOtherLiveScheduleAsync(Guid scheduleId, CancellationToken cancellationToken)
    {
        if (await context.TrainingSchedules.AnyAsync(
                item => item.Id != scheduleId && item.DeletedAtUtc == null,
                cancellationToken))
        {
            throw new TrainingScheduleConflictException("The user already has a training schedule.");
        }
    }

    private async Task RemoveChildrenAsync(Guid scheduleId, CancellationToken cancellationToken)
    {
        context.TrainingScheduleSlots.RemoveRange(
            await context.TrainingScheduleSlots.Where(item => item.ScheduleId == scheduleId).ToListAsync(cancellationToken));
        context.TrainingScheduleShifts.RemoveRange(
            await context.TrainingScheduleShifts.Where(item => item.ScheduleId == scheduleId).ToListAsync(cancellationToken));
        context.TrainingScheduleExceptions.RemoveRange(
            await context.TrainingScheduleExceptions.Where(item => item.ScheduleId == scheduleId).ToListAsync(cancellationToken));
    }

    /// <summary>Every referenced plan must exist and belong to the user; archived plans are allowed.</summary>
    private async Task EnsurePlansOwnedAsync(Guid userId, TrainingScheduleValues values, CancellationToken cancellationToken)
    {
        Guid[] slotPlans = values.Slots.Where(item => item.PlanId is not null).Select(item => item.PlanId!.Value).Distinct().ToArray();
        Guid[] exceptionPlans = values.Exceptions.Select(item => item.PlanId).Distinct().ToArray();
        Guid[] referenced = slotPlans.Union(exceptionPlans).ToArray();
        HashSet<Guid> owned = (await context.TrainingPlans.AsNoTracking()
            .Where(item => referenced.Contains(item.Id) && item.UserId == userId)
            .Select(item => item.Id)
            .ToListAsync(cancellationToken)).ToHashSet();

        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (slotPlans.Any(id => !owned.Contains(id)))
        {
            errors[nameof(TrainingScheduleValues.Slots)] = "Every slot plan must exist and belong to the user.";
        }
        if (exceptionPlans.Any(id => !owned.Contains(id)))
        {
            errors[nameof(TrainingScheduleValues.Exceptions)] = "Every exception plan must exist and belong to the user.";
        }
        if (errors.Count > 0)
        {
            throw new TrainingScheduleValidationException(errors);
        }
    }

    private static void Apply(TrainingSchedule schedule, TrainingScheduleValues values)
    {
        schedule.Mode = TrainingScheduleModes.Parse(values.Mode);
        schedule.AnchorDate = values.AnchorDate;
        schedule.ValidFrom = values.ValidFrom;
    }

    private void AddChildren(Guid scheduleId, TrainingScheduleValues values)
    {
        for (int position = 0; position < values.Slots.Count; position++)
        {
            context.TrainingScheduleSlots.Add(new TrainingScheduleSlot
            {
                Id = Guid.NewGuid(),
                ScheduleId = scheduleId,
                Position = position,
                PlanId = values.Slots[position].PlanId,
            });
        }
        for (int position = 0; position < values.Shifts.Count; position++)
        {
            TrainingScheduleShiftValues shift = values.Shifts[position];
            context.TrainingScheduleShifts.Add(new TrainingScheduleShift
            {
                Id = Guid.NewGuid(),
                ScheduleId = scheduleId,
                Position = position,
                FromDate = shift.FromDate,
                Days = shift.Days,
            });
        }
        for (int position = 0; position < values.Exceptions.Count; position++)
        {
            TrainingScheduleExceptionValues exception = values.Exceptions[position];
            context.TrainingScheduleExceptions.Add(new TrainingScheduleException
            {
                Id = Guid.NewGuid(),
                ScheduleId = scheduleId,
                Position = position,
                Date = exception.Date,
                PlanId = exception.PlanId,
                MovedToDate = exception.MovedToDate,
            });
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
            throw new TrainingScheduleConflictException("The schedule changed concurrently.");
        }
        catch (DbUpdateException exception) when (
            context.IsKeyViolation<TrainingSchedule>(exception) ||
            context.IsUniqueIndexViolation<TrainingSchedule>(exception, nameof(TrainingSchedule.UserId)))
        {
            throw new TrainingScheduleConflictException("Another live schedule or the same identifier already exists.");
        }
    }

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");
}
