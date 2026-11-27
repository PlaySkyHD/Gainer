using System.Data;
using Gainer.Core.Insights;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

/// <summary>
/// Loads the inputs of the training schedule projection. The global query filter isolates users; the rhythm, its
/// children, plans and workouts are read in one repeatable-read transaction so they fit together.
/// </summary>
public sealed class TrainingScheduleQueries(AppDbContext context) : ITrainingScheduleQueries
{
    public async Task<TrainingScheduleProjection> ProjectionAsync(
        DateOnly from,
        DateOnly through,
        DateOnly today,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(timeZone);
        DateTime fromUtc = LocalDays.StartOfDayUtc(from, timeZone);
        DateTime beforeUtc = through == DateOnly.MaxValue ? DateTime.MaxValue : LocalDays.StartOfDayUtc(through.AddDays(1), timeZone);
        await using var transaction = await context.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, cancellationToken);
        ScheduleProjectionInput? schedule = await ScheduleAsync(cancellationToken);
        List<SchedulePlanInput> plans = await context.TrainingPlans.AsNoTracking()
            .OrderBy(item => item.SortOrder)
            .ThenBy(item => item.Id)
            .Select(item => new SchedulePlanInput(item.Id, item.Name, item.IsArchived))
            .ToListAsync(cancellationToken);
        List<ScheduleWorkoutInput> workouts = await context.Workouts.AsNoTracking()
            .Where(item => item.EndedAtUtc != null && item.DeletedAtUtc == null)
            .Where(item => item.StartedAtUtc >= fromUtc && item.StartedAtUtc < beforeUtc)
            .OrderBy(item => item.StartedAtUtc)
            .ThenBy(item => item.Id)
            .Select(item => new ScheduleWorkoutInput(item.Id, item.StartedAtUtc, item.EndedAtUtc, item.DeletedAtUtc, item.SourcePlanId))
            .ToListAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new TrainingScheduleProjection(schedule, plans, workouts, today, timeZone);
    }

    private async Task<ScheduleProjectionInput?> ScheduleAsync(CancellationToken cancellationToken)
    {
        TrainingSchedule? schedule = await context.TrainingSchedules.AsNoTracking()
            .Where(item => item.DeletedAtUtc == null)
            .OrderByDescending(item => item.UpdatedAtUtc)
            .FirstOrDefaultAsync(cancellationToken);
        if (schedule is null) return null;
        Guid?[] slots = await context.TrainingScheduleSlots.AsNoTracking()
            .Where(item => item.ScheduleId == schedule.Id)
            .OrderBy(item => item.Position)
            .Select(item => item.PlanId)
            .ToArrayAsync(cancellationToken);
        ScheduleShiftInput[] shifts = await context.TrainingScheduleShifts.AsNoTracking()
            .Where(item => item.ScheduleId == schedule.Id)
            .OrderBy(item => item.Position)
            .Select(item => new ScheduleShiftInput(item.FromDate, item.Days))
            .ToArrayAsync(cancellationToken);
        ScheduleExceptionInput[] exceptions = await context.TrainingScheduleExceptions.AsNoTracking()
            .Where(item => item.ScheduleId == schedule.Id)
            .OrderBy(item => item.Position)
            .Select(item => new ScheduleExceptionInput(item.Date, item.PlanId, item.MovedToDate))
            .ToArrayAsync(cancellationToken);
        return new ScheduleProjectionInput(schedule.Mode, schedule.AnchorDate, schedule.ValidFrom, slots, shifts, exceptions);
    }
}
