using Gainer.Core.BodyTracking;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class BodyTrackingQueries(AppDbContext context) : IBodyTrackingQueries
{
    public async Task<BodyGoalSnapshot?> GetActiveGoalAsync(CancellationToken cancellationToken = default)
    {
        BodyGoal? goal = await context.BodyGoals
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.EndedAtUtc == null, cancellationToken);
        return goal is null ? null : BodyTrackingSnapshots.Goal(goal);
    }

    public async Task<IReadOnlyList<BodyGoalSnapshot>> GetGoalHistoryAsync(
        CancellationToken cancellationToken = default)
    {
        return await context.BodyGoals
            .AsNoTracking()
            .Where(item => item.EndedAtUtc != null)
            .OrderByDescending(item => item.StartDate)
            .ThenByDescending(item => item.Id)
            .Select(item => BodyTrackingSnapshots.Goal(item))
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<DailyCheckInSnapshot>> GetCheckInsAsync(
        int offset,
        int limit,
        CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(offset);
        if (limit is < 1 or > 200)
        {
            throw new ArgumentOutOfRangeException(nameof(limit));
        }

        return await context.DailyCheckIns
            .AsNoTracking()
            .OrderBy(item => item.LocalDate)
            .ThenBy(item => item.Id)
            .Skip(offset)
            .Take(limit)
            .Select(item => BodyTrackingSnapshots.CheckIn(item))
            .ToListAsync(cancellationToken);
    }
}

internal static class BodyTrackingSnapshots
{
    public static BodyGoalSnapshot Goal(BodyGoal goal) => new(
        goal.Id,
        goal.Kind,
        goal.StartWeightKg,
        goal.TargetWeightKg,
        goal.StartDate,
        goal.TargetDate,
        goal.CreatedAtUtc,
        goal.EndedAtUtc,
        goal.Version);

    public static DailyCheckInSnapshot CheckIn(DailyCheckIn checkIn) => new(
        checkIn.Id,
        checkIn.LocalDate,
        new DailyCheckInValues(
            checkIn.WeightKg,
            checkIn.CaloriesKcal,
            checkIn.ProteinGrams,
            checkIn.CarbohydrateGrams,
            checkIn.FatGrams,
            checkIn.Steps,
            checkIn.SleepMinutes,
            checkIn.RestingHeartRateBpm,
            checkIn.RestingHrvMs),
        checkIn.CreatedAtUtc,
        checkIn.UpdatedAtUtc,
        checkIn.Version);
}
