using System.Data;
using Gainer.Core.BodyTracking;
using Gainer.Core.Insights;
using Gainer.Core.Nutrition;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class InsightQueries(AppDbContext context) : IInsightQueries
{
    public async Task<DashboardInsightSnapshot> DashboardAsync(
        DateOnly through,
        int days,
        CancellationToken cancellationToken = default)
    {
        if (days is < 1 or > 365) throw new ArgumentOutOfRangeException(nameof(days));
        DateOnly from = through.AddDays(1 - days);
        await using var transaction = await context.Database.BeginTransactionAsync(
            IsolationLevel.RepeatableRead, cancellationToken);
        long revision = await CurrentRevisionAsync(cancellationToken);
        List<DailyCheckIn> checkIns = await context.DailyCheckIns.AsNoTracking()
            .Where(item => item.LocalDate >= from && item.LocalDate <= through)
            .OrderBy(item => item.LocalDate)
            .ToListAsync(cancellationToken);
        List<NutritionDay> nutritionDays = await context.NutritionDays.AsNoTracking()
            .Where(item => item.LocalDate >= from && item.LocalDate <= through)
            .Include(item => item.Entries)
            .AsSplitQuery()
            .OrderBy(item => item.LocalDate)
            .ToListAsync(cancellationToken);
        BodyGoal? goal = await context.BodyGoals.AsNoTracking()
            .Where(item => item.EndedAtUtc == null)
            .OrderByDescending(item => item.StartDate)
            .ThenByDescending(item => item.Id)
            .FirstOrDefaultAsync(cancellationToken);
        DateTime workoutFromUtc = from.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
        DateTime workoutThroughUtc = through.AddDays(1).ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
        Guid[] workoutIds = await context.Workouts.AsNoTracking()
            .Where(item => item.EndedAtUtc != null && item.DeletedAtUtc == null &&
                item.EndedAtUtc >= workoutFromUtc && item.EndedAtUtc < workoutThroughUtc)
            .Select(item => item.Id)
            .ToArrayAsync(cancellationToken);
        List<SetRow> sets = await CompletedSets(workoutIds, cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        WeightInsights weight = InsightAlgorithms.Weight(
            checkIns.Select(item => new WeightPoint(item.LocalDate, item.WeightKg)).ToArray(), from, through);
        DateOnly sevenDayFrom = through.AddDays(-6);
        WeightInsights sevenDayWeight = InsightAlgorithms.Weight(
            checkIns.Select(item => new WeightPoint(item.LocalDate, item.WeightKg)).ToArray(), sevenDayFrom, through);
        NutritionInsights nutrition = InsightAlgorithms.Nutrition(
            ProjectNutrition(checkIns, nutritionDays), from, through);
        TrainingInsights training = InsightAlgorithms.Training(sets.Select(ToPerformance).ToArray(), workoutIds);
        DailyCheckIn? latest = checkIns.OrderByDescending(item => item.LocalDate).ThenByDescending(item => item.Id).FirstOrDefault();
        return new DashboardInsightSnapshot(
            revision,
            from,
            through,
            goal is null ? null : BodyTrackingSnapshots.Goal(goal),
            latest is null ? null : new WeightPoint(latest.LocalDate, latest.WeightKg),
            checkIns.Select(item => new WeightPoint(item.LocalDate, item.WeightKg)).ToList(),
            sevenDayWeight,
            weight,
            nutrition,
            training,
            sets.Where(item => DateOnly.FromDateTime(item.CompletedAtUtc) >= sevenDayFrom)
                .Select(item => item.WorkoutId).Distinct().Count());
    }

    public async Task<ExerciseProgressSnapshot> ExerciseProgressAsync(
        Guid exerciseId,
        int? windowDays,
        DateTime throughUtc,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default)
    {
        if (exerciseId == Guid.Empty) throw new ArgumentException("Exercise id is required.", nameof(exerciseId));
        if (windowDays is not (null or 7 or 30 or 90)) throw new ArgumentOutOfRangeException(nameof(windowDays));
        if (throughUtc.Kind != DateTimeKind.Utc) throw new ArgumentException("UTC is required.", nameof(throughUtc));
        DateOnly localThrough = DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(throughUtc, timeZone));
        DateOnly? localFrom = windowDays is { } days ? localThrough.AddDays(1 - days) : null;
        DateTime fromUtc = localFrom is { } from
            ? TimeZoneInfo.ConvertTimeToUtc(from.ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified), timeZone)
            : DateTime.UnixEpoch;
        DateTime endExclusiveUtc = TimeZoneInfo.ConvertTimeToUtc(
            localThrough.AddDays(1).ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified), timeZone);

        await using var transaction = await context.Database.BeginTransactionAsync(
            IsolationLevel.RepeatableRead, cancellationToken);
        long revision = await CurrentRevisionAsync(cancellationToken);
        List<SetRow> rows = await (
            from workout in context.Workouts.AsNoTracking()
            join exercise in context.WorkoutExercises.AsNoTracking() on workout.Id equals exercise.WorkoutId
            join set in context.WorkoutSets.AsNoTracking() on exercise.Id equals set.WorkoutExerciseId
            where workout.EndedAtUtc != null && workout.DeletedAtUtc == null && exercise.SourceExerciseId == exerciseId &&
                  workout.EndedAtUtc >= fromUtc && workout.EndedAtUtc < endExclusiveUtc &&
                  set.SetType != WorkoutSetType.Warmup && set.WeightKg != null && set.Repetitions > 0
            select new SetRow(
                workout.Id, exerciseId, workout.EndedAtUtc!.Value,
                set.WeightKg, set.Repetitions))
            .ToListAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        TrainingInsights aggregate = InsightAlgorithms.Training(
            rows.Select(ToPerformance).ToArray(), rows.Select(item => item.WorkoutId).Distinct().ToArray());
        List<ExerciseProgressPoint> points = rows.GroupBy(item => new { item.WorkoutId, item.CompletedAtUtc })
            .Select(group =>
            {
                SetRow[] valid = group.Where(item => item.WeightKg is > 0 && item.Repetitions is > 0).ToArray();
                SetRow? best = valid.Where(item => item.Repetitions is >= 1 and <= 12)
                    .OrderByDescending(item => InsightAlgorithms.Epley(item.WeightKg!.Value, item.Repetitions!.Value))
                    .ThenByDescending(item => item.WeightKg)
                    .ThenByDescending(item => item.Repetitions)
                    .FirstOrDefault();
                return new ExerciseProgressPoint(
                    group.Key.WorkoutId,
                    group.Key.CompletedAtUtc,
                    decimal.Round(valid.Sum(item => item.WeightKg!.Value * item.Repetitions!.Value), 2, MidpointRounding.AwayFromZero),
                    best?.WeightKg,
                    best?.Repetitions,
                    best is null ? null : decimal.Round(
                        InsightAlgorithms.Epley(best.WeightKg!.Value, best.Repetitions!.Value), 2, MidpointRounding.AwayFromZero));
            })
            .OrderBy(item => item.CompletedAtUtc)
            .ThenBy(item => item.WorkoutId)
            .ToList();
        return new ExerciseProgressSnapshot(
            revision, exerciseId, windowDays, fromUtc, endExclusiveUtc.AddTicks(-1), points, aggregate.BestSet);
    }

    private async Task<long> CurrentRevisionAsync(CancellationToken cancellationToken) =>
        await context.UserSyncStates.AsNoTracking().Select(item => (long?)item.CurrentRevision)
            .SingleOrDefaultAsync(cancellationToken) ?? 0;

    private async Task<List<SetRow>> CompletedSets(Guid[] workoutIds, CancellationToken cancellationToken) =>
        await (
            from exercise in context.WorkoutExercises.AsNoTracking()
            join set in context.WorkoutSets.AsNoTracking() on exercise.Id equals set.WorkoutExerciseId
            join workout in context.Workouts.AsNoTracking() on exercise.WorkoutId equals workout.Id
            where workoutIds.Contains(workout.Id) && set.SetType != WorkoutSetType.Warmup &&
                  set.WeightKg != null && set.Repetitions > 0
            select new SetRow(
                workout.Id, exercise.SourceExerciseId, workout.EndedAtUtc!.Value,
                set.WeightKg, set.Repetitions))
            .ToListAsync(cancellationToken);

    private static SetPerformance ToPerformance(SetRow row) => new(
        row.WorkoutId, row.ExerciseId, row.CompletedAtUtc, row.WeightKg, row.Repetitions);

    private static NutritionPoint[] ProjectNutrition(
        IReadOnlyCollection<DailyCheckIn> checkIns,
        IReadOnlyCollection<NutritionDay> nutritionDays)
    {
        Dictionary<DateOnly, DailyCheckIn> legacy = checkIns
            .GroupBy(item => item.LocalDate)
            .ToDictionary(group => group.Key, group => group.OrderByDescending(item => item.Id).First());
        Dictionary<DateOnly, NutritionDay> diary = nutritionDays
            .Where(item => item.Entries.Count > 0)
            .GroupBy(item => item.LocalDate)
            .ToDictionary(group => group.Key, group => group.OrderByDescending(item => item.Id).First());

        return legacy.Keys.Concat(diary.Keys).Distinct().OrderBy(date => date).Select(date =>
        {
            if (diary.TryGetValue(date, out NutritionDay? day))
            {
                NutritionTotals total = NutritionCalculator.Sum(day.Entries.Select(item => new NutritionTotals(
                    item.Kilocalories, item.ProteinGrams, item.CarbohydrateGrams, item.FatGrams)));
                return new NutritionPoint(date, total.Kilocalories, total.ProteinGrams,
                    total.CarbohydrateGrams, total.FatGrams, NutritionSources.MealDiary);
            }

            DailyCheckIn item = legacy[date];
            return new NutritionPoint(date, item.CaloriesKcal, item.ProteinGrams,
                item.CarbohydrateGrams, item.FatGrams, NutritionSources.LegacyCheckIn);
        }).ToArray();
    }

    private sealed record SetRow(
        Guid WorkoutId,
        Guid ExerciseId,
        DateTime CompletedAtUtc,
        decimal? WeightKg,
        int? Repetitions);
}
