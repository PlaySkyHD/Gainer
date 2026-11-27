using System.Data;
using Gainer.Core.Insights;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

/// <summary>
/// Loads the user's data for the ports of the app's statistics. The global query filter isolates users;
/// exercises are not user-owned and are limited to the base catalog and the user's own ones.
/// </summary>
public sealed class TrainingAnalysisQueries(AppDbContext context, IUserContext userContext) : ITrainingAnalysisQueries
{
    public async Task<TrainingTrendsSnapshot> TrendsAsync(
        TrendPeriod period,
        bool includeWarmups,
        DateOnly today,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(timeZone);
        Guid userId = CurrentUser();
        // A bounded period needs only workouts that ended from its first day; "all" starts at the earliest data.
        DateTime? fromUtc = TrainingTrends.FixedStart(period, today) is { } start ? LocalDays.StartOfDayUtc(start, timeZone) : null;
        await using var transaction = await context.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, cancellationToken);
        // Earlier check-ins give the body weight of the first workouts.
        CheckInWeight[] checkIns = await context.DailyCheckIns.AsNoTracking()
            .Where(item => item.LocalDate <= today)
            .OrderBy(item => item.LocalDate)
            .Select(item => new CheckInWeight(item.LocalDate, item.WeightKg))
            .ToArrayAsync(cancellationToken);
        List<TrainingWorkoutInput> workouts = await context.FinishedWorkoutsAsync(fromUtc, null, null, cancellationToken);
        Dictionary<Guid, ExerciseFactorInput> factors = await context.ExerciseFactorsAsync(workouts, userId, cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        IReadOnlyList<WorkoutTrendEntry> entries = TrainingTrends.Entries(
            workouts.OrderBy(item => item.StartedAtUtc).ThenBy(item => item.WorkoutId), checkIns, factors, timeZone, includeWarmups);
        return TrainingTrends.Compute(entries.ToArray(), checkIns, period, today);
    }

    public async Task<TrainingHeatmapSnapshot> HeatmapAsync(
        DateOnly today,
        TimeZoneInfo timeZone,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(timeZone);
        DateTime fromUtc = LocalDays.StartOfDayUtc(TrainingHeatmap.StartFor(today), timeZone);
        DateTime beforeUtc = LocalDays.StartOfDayUtc(today.AddDays(1), timeZone);
        List<TrainingInterval> workouts = await context.Workouts.AsNoTracking()
            .Where(item => item.EndedAtUtc != null && item.DeletedAtUtc == null)
            .Where(item => item.StartedAtUtc >= fromUtc && item.StartedAtUtc < beforeUtc)
            .Select(item => new TrainingInterval(item.StartedAtUtc, item.EndedAtUtc!.Value))
            .ToListAsync(cancellationToken);
        List<TrainingInterval> cardio = await context.CardioSessions.AsNoTracking()
            .Where(item => item.StartedAtUtc >= fromUtc && item.StartedAtUtc < beforeUtc)
            .Select(item => new TrainingInterval(item.StartedAtUtc, item.EndedAtUtc))
            .ToListAsync(cancellationToken);
        return TrainingHeatmap.Build(workouts.Concat(cardio), today, timeZone);
    }

    public async Task<MuscleVolumeSnapshot?> PlannedMuscleVolumeAsync(Guid? planId, CancellationToken cancellationToken = default)
    {
        List<TrainingPlan> plans = await context.TrainingPlans.AsNoTracking()
            .Where(item => planId == null ? !item.IsArchived : item.Id == planId)
            .ToListAsync(cancellationToken);
        if (planId is not null && plans.Count == 0) return null;
        Guid[] planIds = plans.Select(item => item.Id).ToArray();
        var entries = await context.TrainingPlanEntries.AsNoTracking()
            .Where(item => planIds.Contains(item.PlanId))
            .OrderBy(item => item.Position)
            .Select(item => new { item.PlanId, item.ExerciseId, item.WorkingSets })
            .ToListAsync(cancellationToken);
        ILookup<Guid, PlannedExerciseSets> byPlan = entries.ToLookup(
            item => item.PlanId, item => new PlannedExerciseSets(item.ExerciseId, item.WorkingSets));
        Dictionary<Guid, MuscleExerciseInput> exercises = await ExercisesAsync(
            entries.Select(item => item.ExerciseId), cancellationToken);
        return MuscleVolume.FromPlans(
            plans.OrderBy(item => item.SortOrder).ThenBy(item => item.Id)
                .Select(plan => new PlannedSetsInput(plan.Id, plan.IsArchived, byPlan[plan.Id].ToArray())),
            exercises);
    }

    public async Task<MuscleVolumeSnapshot> TrainedMuscleVolumeAsync(
        DateTime fromUtc,
        DateTime toUtc,
        int weeks,
        CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(weeks, 1);
        var workouts = await context.Workouts.AsNoTracking()
            .Where(item => item.EndedAtUtc != null && item.DeletedAtUtc == null)
            .Where(item => item.StartedAtUtc >= fromUtc && item.StartedAtUtc < toUtc)
            .OrderBy(item => item.StartedAtUtc)
            .ThenBy(item => item.Id)
            .Select(item => new { item.Id, item.StartedAtUtc, item.EndedAtUtc })
            .ToListAsync(cancellationToken);
        Guid[] workoutIds = workouts.Select(item => item.Id).ToArray();
        var blocks = await context.WorkoutExercises.AsNoTracking()
            .Where(item => workoutIds.Contains(item.WorkoutId))
            .OrderBy(item => item.Position)
            .Select(item => new { item.Id, item.WorkoutId, item.SourceExerciseId, item.ExerciseNameSnapshot, item.ExerciseTypeSnapshot })
            .ToListAsync(cancellationToken);
        Guid[] blockIds = blocks.Select(item => item.Id).ToArray();
        var sets = await context.WorkoutSets.AsNoTracking()
            .Where(item => blockIds.Contains(item.WorkoutExerciseId))
            .OrderBy(item => item.Position)
            .Select(item => new { item.WorkoutExerciseId, item.SetType, item.WeightKg, item.Repetitions })
            .ToListAsync(cancellationToken);

        ILookup<Guid, TrainingSetInput> setsByBlock = sets.ToLookup(
            item => item.WorkoutExerciseId, item => new TrainingSetInput(item.SetType, item.WeightKg, item.Repetitions));
        ILookup<Guid, MuscleBlockInput> blocksByWorkout = blocks.ToLookup(
            item => item.WorkoutId,
            item => new MuscleBlockInput(item.SourceExerciseId, item.ExerciseNameSnapshot, item.ExerciseTypeSnapshot,
                setsByBlock[item.Id].ToArray()));
        Dictionary<Guid, MuscleExerciseInput> exercises = await ExercisesAsync(
            blocks.Select(item => item.SourceExerciseId), cancellationToken);
        return MuscleVolume.FromWorkouts(
            workouts.Select(item => new MuscleWorkoutInput(item.StartedAtUtc, item.EndedAtUtc, null, blocksByWorkout[item.Id].ToArray())),
            exercises,
            fromUtc,
            toUtc,
            weeks);
    }

    /// <summary>Names and muscles of the referenced exercises, archived ones included as in the app.</summary>
    private async Task<Dictionary<Guid, MuscleExerciseInput>> ExercisesAsync(
        IEnumerable<Guid> exerciseIds,
        CancellationToken cancellationToken)
    {
        Guid[] ids = exerciseIds.Distinct().ToArray();
        if (ids.Length == 0) return [];
        Guid userId = CurrentUser();
        return await context.Exercises.AsNoTracking()
            .Where(item => ids.Contains(item.Id) && (item.OwnerUserId == null || item.OwnerUserId == userId))
            .Select(item => new MuscleExerciseInput(item.Id, item.Name, item.PrimaryMuscles, item.SecondaryMuscles))
            .ToDictionaryAsync(item => item.ExerciseId, cancellationToken);
    }

    private Guid CurrentUser() =>
        userContext.UserId ?? throw new InvalidOperationException("An authenticated user is required.");
}
