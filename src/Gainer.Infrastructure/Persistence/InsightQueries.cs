using System.Data;
using Gainer.Core.BodyTracking;
using Gainer.Core.Insights;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class InsightQueries(AppDbContext context, IUserContext userContext) : IInsightQueries
{
    public async Task<DashboardInsightSnapshot> DashboardAsync(
        DateOnly through,
        int days,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default)
    {
        if (days is < 1 or > 365) throw new ArgumentOutOfRangeException(nameof(days));
        Guid userId = CurrentUser();
        DateOnly from = through.AddDays(1 - days);
        DateOnly sevenDayFrom = through.AddDays(-6);
        DateTime workoutFromUtc = from.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
        DateTime workoutThroughUtc = through.AddDays(1).ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
        await using var transaction = await context.Database.BeginTransactionAsync(
            IsolationLevel.RepeatableRead, cancellationToken);
        long revision = await CurrentRevisionAsync(cancellationToken);
        // Ein Training am Ende des Zeitraums kann einen Starttag bis einen Tag später haben.
        List<DailyCheckIn> checkIns = await context.DailyCheckIns.AsNoTracking()
            .Where(item => item.LocalDate <= through.AddDays(2))
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
        List<TrainingWorkoutInput> workouts = await FinishedWorkoutsAsync(
            workoutFromUtc, workoutThroughUtc, exerciseId: null, cancellationToken);
        Dictionary<Guid, ExerciseFactorInput> factors = await ExerciseFactorsAsync(workouts, userId, cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        CheckInWeight[] bodyweights = ToCheckInWeights(checkIns);
        List<DailyCheckIn> windowCheckIns = checkIns
            .Where(item => item.LocalDate >= from && item.LocalDate <= through)
            .ToList();
        WeightPoint[] windowWeights = windowCheckIns.Select(item => new WeightPoint(item.LocalDate, item.WeightKg)).ToArray();
        WeightInsights weight = InsightAlgorithms.Weight(windowWeights, from, through);
        WeightInsights sevenDayWeight = InsightAlgorithms.Weight(windowWeights, sevenDayFrom, through);
        NutritionInsights nutrition = InsightAlgorithms.Nutrition(
            ProjectNutrition(windowCheckIns, nutritionDays), from, through);
        List<BlockStatistics> blocks = workouts
            .SelectMany(workout => TrainingStatistics.WorkoutBlocks(workout, bodyweights, factors, timeZone))
            .ToList();
        TrainingInsights training = InsightAlgorithms.Training(blocks, workouts.Count);
        DailyCheckIn? latest = windowCheckIns.OrderByDescending(item => item.LocalDate).ThenByDescending(item => item.Id).FirstOrDefault();
        return new DashboardInsightSnapshot(
            revision,
            from,
            through,
            goal is null ? null : BodyTrackingSnapshots.Goal(goal),
            latest is null ? null : new WeightPoint(latest.LocalDate, latest.WeightKg),
            windowWeights,
            sevenDayWeight,
            weight,
            nutrition,
            training,
            workouts.Count(item => DateOnly.FromDateTime(item.EndedAtUtc!.Value) >= sevenDayFrom));
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
        Guid userId = CurrentUser();
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
        // Die Rekorde gelten für die gesamte Historie bis zum Stichtag, daher kein unterer Zeitrand.
        List<DailyCheckIn> checkIns = await context.DailyCheckIns.AsNoTracking()
            .Where(item => item.LocalDate <= localThrough)
            .OrderBy(item => item.LocalDate)
            .ToListAsync(cancellationToken);
        List<TrainingWorkoutInput> workouts = await FinishedWorkoutsAsync(
            fromUtc: null, endExclusiveUtc, exerciseId, cancellationToken);
        Dictionary<Guid, ExerciseFactorInput> factors = await ExerciseFactorsAsync(workouts, userId, cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        ExerciseHistory history = TrainingStatistics.History(
            exerciseId, workouts, ToCheckInWeights(checkIns), factors, timeZone);
        ExerciseWorkoutTotals[] window = history.Workouts
            .Where(item => item.CompletedAtUtc >= fromUtc)
            .ToArray();
        List<ExerciseProgressPoint> points = window
            .Select(item => new ExerciseProgressPoint(
                item.WorkoutId,
                item.CompletedAtUtc,
                item.VolumeKg,
                item.MaxWeightKg,
                item.MaxRepetitions,
                item.EstimatedOneRepMaxKg,
                item.BodyweightMissing))
            .OrderBy(item => item.CompletedAtUtc)
            .ThenBy(item => item.WorkoutId)
            .ToList();
        return new ExerciseProgressSnapshot(
            revision,
            exerciseId,
            windowDays,
            fromUtc,
            endExclusiveUtc.AddTicks(-1),
            points,
            TrainingStatistics.BestOf(window.Select(item => item.Best)),
            history.Records());
    }

    private Guid CurrentUser() =>
        userContext.UserId ?? throw new InvalidOperationException("An authenticated user is required.");

    private async Task<long> CurrentRevisionAsync(CancellationToken cancellationToken) =>
        await context.UserSyncStates.AsNoTracking().Select(item => (long?)item.CurrentRevision)
            .SingleOrDefaultAsync(cancellationToken) ?? 0;

    /// <summary>Beendete, nicht gelöschte Trainings mit Blöcken; Blöcke optional auf eine Übung begrenzt.</summary>
    private async Task<List<TrainingWorkoutInput>> FinishedWorkoutsAsync(
        DateTime? fromUtc,
        DateTime toUtc,
        Guid? exerciseId,
        CancellationToken cancellationToken)
    {
        IQueryable<Workout> query = context.Workouts.AsNoTracking()
            .Where(item => item.EndedAtUtc != null && item.DeletedAtUtc == null && item.EndedAtUtc < toUtc);
        if (fromUtc is { } from) query = query.Where(item => item.EndedAtUtc >= from);
        var workouts = await query
            .Select(item => new { item.Id, item.StartedAtUtc, item.EndedAtUtc })
            .ToListAsync(cancellationToken);

        Guid[] workoutIds = workouts.Select(item => item.Id).ToArray();
        IQueryable<WorkoutExercise> blockQuery = context.WorkoutExercises.AsNoTracking()
            .Where(item => workoutIds.Contains(item.WorkoutId));
        if (exerciseId is { } id) blockQuery = blockQuery.Where(item => item.SourceExerciseId == id);
        var blocks = await blockQuery
            .OrderBy(item => item.Position)
            .Select(item => new { item.Id, item.WorkoutId, item.SourceExerciseId, item.ExerciseTypeSnapshot })
            .ToListAsync(cancellationToken);

        Guid[] blockIds = blocks.Select(item => item.Id).ToArray();
        var sets = await context.WorkoutSets.AsNoTracking()
            .Where(item => blockIds.Contains(item.WorkoutExerciseId))
            .OrderBy(item => item.Position)
            .Select(item => new { item.WorkoutExerciseId, item.SetType, item.WeightKg, item.Repetitions })
            .ToListAsync(cancellationToken);

        ILookup<Guid, TrainingSetInput> setsByBlock = sets.ToLookup(
            item => item.WorkoutExerciseId,
            item => new TrainingSetInput(item.SetType, item.WeightKg, item.Repetitions));
        ILookup<Guid, TrainingBlockInput> blocksByWorkout = blocks.ToLookup(
            item => item.WorkoutId,
            item => new TrainingBlockInput(item.Id, item.SourceExerciseId, item.ExerciseTypeSnapshot,
                setsByBlock[item.Id].ToArray()));
        return workouts.Select(item => new TrainingWorkoutInput(
            item.Id,
            item.StartedAtUtc,
            item.EndedAtUtc,
            DeletedAtUtc: null,
            blocksByWorkout[item.Id].ToArray())).ToList();
    }

    /// <summary>Katalogfaktoren der Übungen: Basiskatalog oder eigene Übungen des Nutzers.</summary>
    private async Task<Dictionary<Guid, ExerciseFactorInput>> ExerciseFactorsAsync(
        IEnumerable<TrainingWorkoutInput> workouts,
        Guid userId,
        CancellationToken cancellationToken)
    {
        Guid[] exerciseIds = workouts
            .SelectMany(workout => workout.Exercises)
            .Select(block => block.SourceExerciseId)
            .Distinct()
            .ToArray();
        if (exerciseIds.Length == 0) return new Dictionary<Guid, ExerciseFactorInput>();
        List<ExerciseFactorInput> rows = await context.Exercises.AsNoTracking()
            .Where(item => exerciseIds.Contains(item.Id) && (item.OwnerUserId == null || item.OwnerUserId == userId))
            .Select(item => new ExerciseFactorInput(item.Id, item.BodyweightFactor, item.WeightFactor))
            .ToListAsync(cancellationToken);
        return rows.ToDictionary(item => item.ExerciseId);
    }

    private static CheckInWeight[] ToCheckInWeights(IEnumerable<DailyCheckIn> checkIns) =>
        checkIns.Select(item => new CheckInWeight(item.LocalDate, item.WeightKg)).ToArray();

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
}
