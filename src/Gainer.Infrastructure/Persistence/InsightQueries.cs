using System.Data;
using Gainer.Core.BodyTracking;
using Gainer.Core.Insights;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class InsightQueries(AppDbContext context, IUserContext userContext)
    : IInsightQueries, IWorkoutSummaryQueries
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
        // Lokale Tagesgrenzen des Nutzers, wie bei den Check-ins und der Ernährung.
        DateTime workoutFromUtc = LocalDays.StartOfDayUtc(from, timeZone);
        DateTime workoutThroughUtc = LocalDays.StartOfDayUtc(through.AddDays(1), timeZone);
        // Die 7-Tage-Zahl braucht die letzten 7 lokalen Tage, auch wenn das Fenster kürzer ist.
        DateTime loadFromUtc = LocalDays.StartOfDayUtc(DateOnly.FromDayNumber(Math.Min(from.DayNumber, sevenDayFrom.DayNumber)), timeZone);
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
        List<TrainingWorkoutInput> loadedWorkouts = await context.FinishedWorkoutsAsync(
            loadFromUtc, workoutThroughUtc, exerciseIds: null, cancellationToken);
        Dictionary<Guid, ExerciseFactorInput> factors = await context.ExerciseFactorsAsync(loadedWorkouts, userId, cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        List<TrainingWorkoutInput> workouts = loadedWorkouts
            .Where(item => item.EndedAtUtc >= workoutFromUtc)
            .ToList();
        CheckInWeight[] bodyweights = ToCheckInWeights(checkIns);
        List<DailyCheckIn> windowCheckIns = checkIns
            .Where(item => item.LocalDate >= from && item.LocalDate <= through)
            .ToList();
        WeightPoint[] windowWeights = windowCheckIns.Select(item => new WeightPoint(item.LocalDate, item.WeightKg)).ToArray();
        WeightInsights weight = InsightAlgorithms.Weight(windowWeights, from, through);
        WeightPoint[] sevenDayWeights = checkIns
            .Where(item => item.LocalDate >= sevenDayFrom && item.LocalDate <= through)
            .Select(item => new WeightPoint(item.LocalDate, item.WeightKg))
            .ToArray();
        WeightInsights sevenDayWeight = InsightAlgorithms.Weight(sevenDayWeights, sevenDayFrom, through);
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
            loadedWorkouts.Count(item => DateOnly.FromDateTime(
                TimeZoneInfo.ConvertTimeFromUtc(item.EndedAtUtc!.Value, timeZone)) >= sevenDayFrom));
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
        DateTime fromUtc = localFrom is { } from ? LocalDays.StartOfDayUtc(from, timeZone) : DateTime.UnixEpoch;
        DateTime endExclusiveUtc = LocalDays.StartOfDayUtc(localThrough.AddDays(1), timeZone);

        await using var transaction = await context.Database.BeginTransactionAsync(
            IsolationLevel.RepeatableRead, cancellationToken);
        long revision = await CurrentRevisionAsync(cancellationToken);
        // Die Rekorde gelten für die gesamte Historie bis zum Stichtag, daher kein unterer Zeitrand.
        List<DailyCheckIn> checkIns = await context.DailyCheckIns.AsNoTracking()
            .Where(item => item.LocalDate <= localThrough)
            .OrderBy(item => item.LocalDate)
            .ToListAsync(cancellationToken);
        List<TrainingWorkoutInput> workouts = await context.FinishedWorkoutsAsync(
            fromUtc: null, endExclusiveUtc, [exerciseId], cancellationToken);
        Dictionary<Guid, ExerciseFactorInput> factors = await context.ExerciseFactorsAsync(workouts, userId, cancellationToken);
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

    public async Task<WorkoutSummarySnapshot?> WorkoutSummaryAsync(
        Guid workoutId,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(timeZone);
        Guid userId = CurrentUser();
        await using var transaction = await context.Database.BeginTransactionAsync(
            IsolationLevel.RepeatableRead, cancellationToken);
        Workout? workout = await context.Workouts.AsNoTracking().SingleOrDefaultAsync(
            item => item.Id == workoutId && item.EndedAtUtc != null && item.DeletedAtUtc == null,
            cancellationToken);
        if (workout is null) return null;
        var blocks = await context.WorkoutExercises.AsNoTracking()
            .Where(item => item.WorkoutId == workoutId)
            .OrderBy(item => item.Position)
            .Select(item => new { item.SourceExerciseId, item.ExerciseNameSnapshot })
            .ToListAsync(cancellationToken);
        Guid[] exerciseIds = blocks.Select(item => item.SourceExerciseId).Distinct().ToArray();
        // Records need the history of the workout's exercises up to this workout; later ones change nothing.
        // The bound is exclusive and Postgres keeps microseconds, so one tick would drop this workout itself.
        List<TrainingWorkoutInput> workouts = await context.FinishedWorkoutsAsync(
            fromUtc: null, toUtc: workout.EndedAtUtc!.Value.AddMilliseconds(1), exerciseIds, cancellationToken);
        // The counters follow the app's summary screen: every completed workout, week of this workout's start.
        List<DateTime> countedStarts = await context.Workouts.AsNoTracking()
            .Where(item => item.EndedAtUtc != null && item.DeletedAtUtc == null)
            .Select(item => item.StartedAtUtc)
            .ToListAsync(cancellationToken);
        DateOnly startDay = LocalDays.DateOf(workout.StartedAtUtc, timeZone);
        List<DailyCheckIn> checkIns = await context.DailyCheckIns.AsNoTracking()
            .Where(item => item.LocalDate <= startDay)
            .OrderBy(item => item.LocalDate)
            .ToListAsync(cancellationToken);
        Dictionary<Guid, ExerciseFactorInput> factors = await context.ExerciseFactorsAsync(workouts, userId, cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        CheckInWeight[] bodyweights = ToCheckInWeights(checkIns);
        TrainingWorkoutInput current = workouts.Single(item => item.WorkoutId == workoutId);
        TrainingSummary summary = TrainingStatistics.Summarize(current, workouts, bodyweights, factors, timeZone);
        WorkoutCounts counts = TrainingStatistics.CountsFromStarts(countedStarts, current.StartedAtUtc, timeZone);
        bool bodyweightMissing = TrainingStatistics.WorkoutBlocks(current, bodyweights, factors, timeZone)
            .Any(block => block.BodyweightMissing);
        return new WorkoutSummarySnapshot(
            workout.Id,
            workout.Title,
            workout.StartedAtUtc,
            workout.EndedAtUtc.Value,
            summary,
            counts,
            blocks
                .GroupBy(item => item.SourceExerciseId)
                .ToDictionary(group => group.Key, group => group.First().ExerciseNameSnapshot),
            bodyweightMissing);
    }

    private Guid CurrentUser() =>
        userContext.UserId ?? throw new InvalidOperationException("An authenticated user is required.");

    private async Task<long> CurrentRevisionAsync(CancellationToken cancellationToken) =>
        await context.UserSyncStates.AsNoTracking().Select(item => (long?)item.CurrentRevision)
            .SingleOrDefaultAsync(cancellationToken) ?? 0;

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
                    item.Kilocalories, item.ProteinGrams, item.CarbohydrateGrams, item.FatGrams, FiberGrams: item.FiberGrams)));
                return new NutritionPoint(date, total.Kilocalories, total.ProteinGrams,
                    total.CarbohydrateGrams, total.FatGrams, NutritionSources.MealDiary, total.FiberGrams);
            }

            DailyCheckIn item = legacy[date];
            return new NutritionPoint(date, item.CaloriesKcal, item.ProteinGrams,
                item.CarbohydrateGrams, item.FatGrams, NutritionSources.LegacyCheckIn);
        }).ToArray();
    }
}
