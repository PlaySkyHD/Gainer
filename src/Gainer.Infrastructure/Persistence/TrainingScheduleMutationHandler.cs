using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

/// <summary>
/// Saves the user's single training schedule as a complete state. Like the removed rotation, creating a second
/// schedule (base version 0 while one exists, regardless of its id) is a conflict; the client must update or delete
/// the existing one.
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

        TrainingSchedule schedule;
        if (mutation.BaseVersion == 0)
        {
            if (await context.TrainingSchedules.AnyAsync(cancellationToken))
            {
                throw new TrainingScheduleConflictException("The user already has a training schedule.");
            }
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
            schedule = await context.TrainingSchedules.SingleOrDefaultAsync(
                item => item.Id == values.ScheduleId,
                cancellationToken) ?? throw new TrainingScheduleNotFoundException();
            if (schedule.Version != mutation.BaseVersion)
            {
                throw new TrainingScheduleConflictException("The schedule changed since the supplied base version.");
            }
            await EnsurePlansOwnedAsync(userId, values, cancellationToken);
            // Children are replaced completely; removals are flushed before rows with the same unique keys are inserted.
            context.TrainingScheduleSlots.RemoveRange(
                await context.TrainingScheduleSlots.Where(item => item.ScheduleId == schedule.Id).ToListAsync(cancellationToken));
            context.TrainingScheduleShifts.RemoveRange(
                await context.TrainingScheduleShifts.Where(item => item.ScheduleId == schedule.Id).ToListAsync(cancellationToken));
            context.TrainingScheduleExceptions.RemoveRange(
                await context.TrainingScheduleExceptions.Where(item => item.ScheduleId == schedule.Id).ToListAsync(cancellationToken));
            await SaveOrConflictAsync(cancellationToken);
            Apply(schedule, values);
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
            .SingleOrDefaultAsync(item => item.Id == mutation.ScheduleId, cancellationToken)
            ?? throw new TrainingScheduleNotFoundException();
        if (schedule.Version != mutation.BaseVersion)
        {
            throw new TrainingScheduleConflictException("The schedule changed since the supplied base version.");
        }

        long deletedVersion = schedule.Version + 1;
        // Children are removed by the database cascade.
        context.TrainingSchedules.Remove(schedule);
        await SaveOrConflictAsync(cancellationToken);
        changeCollector?.CaptureDeletion(ResourceKey.Create(ResourceKind.TrainingSchedule, schedule.Id), deletedVersion);
        return deletedVersion;
    }

    /// <summary>Every referenced plan must exist and belong to the user; archived plans are allowed.</summary>
    private async Task EnsurePlansOwnedAsync(Guid userId, TrainingScheduleValues values, CancellationToken cancellationToken)
    {
        Guid[] slotPlans = values.Slots.Where(item => item.PlanId is not null).Select(item => item.PlanId!.Value).Distinct().ToArray();
        Guid[] exceptionPlans = values.Exceptions.Select(item => item.PlanId).Distinct().ToArray();
        Guid[] referenced = TrainingScheduleValidation.ReferencedPlanIds(values).ToArray();
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
        catch (DbUpdateException)
        {
            throw new TrainingScheduleConflictException("The schedule conflicts with stored data.");
        }
    }

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");
}
