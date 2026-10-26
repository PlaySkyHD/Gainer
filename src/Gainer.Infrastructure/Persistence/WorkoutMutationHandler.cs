using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

public sealed class WorkoutMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IWorkoutMutationHandler
{
    private const string UnavailableReferenceMessage = "The referenced item is unavailable.";

    public async Task<WorkoutSnapshot> CreateAsync(
        CreateWorkoutMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        WorkoutValues values = WorkoutValidation.Normalize(mutation.Workout);
        await EnsureReferencesAvailableAsync(userId, values, cancellationToken);
        if (values.EndedAtUtc is null) await EnsureNoOtherActiveWorkoutAsync(values.WorkoutId, cancellationToken);

        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        var workout = new Workout
        {
            Id = values.WorkoutId,
            CreatedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        };
        Apply(workout, values);
        context.Workouts.Add(workout);
        AddExercises(workout.Id, values.Exercises);
        await SaveOrConflictAsync(cancellationToken);
        return Capture(workout, values.Exercises);
    }

    public async Task<WorkoutSnapshot> SaveAsync(
        SaveWorkoutMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        WorkoutValues values = WorkoutValidation.Normalize(mutation.Workout);
        Workout workout = await FindOwnedAsync(values.WorkoutId, cancellationToken);
        if (workout.Version != mutation.BaseVersion)
        {
            throw new WorkoutConflictException("Only the current version of an existing workout can be saved.");
        }
        await EnsureReferencesAvailableAsync(userId, values, cancellationToken);
        if (values.EndedAtUtc is null) await EnsureNoOtherActiveWorkoutAsync(workout.Id, cancellationToken);

        List<WorkoutExercise> existingExercises = await context.WorkoutExercises
            .Where(item => item.WorkoutId == workout.Id).ToListAsync(cancellationToken);
        List<WorkoutSet> existingSets = await context.WorkoutSets
            .Where(item => item.WorkoutId == workout.Id).ToListAsync(cancellationToken);

        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;
        // Removals are flushed before the stable child IDs are reused by the replacement rows.
        context.WorkoutSets.RemoveRange(existingSets);
        context.WorkoutExercises.RemoveRange(existingExercises);
        await SaveOrConflictAsync(cancellationToken);
        Apply(workout, values);
        workout.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        workout.Version++;
        AddExercises(workout.Id, values.Exercises);
        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        return Capture(workout, values.Exercises);
    }

    public async Task<DeleteWorkoutResult> DeleteAsync(
        DeleteWorkoutMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        Workout workout = await FindOwnedAsync(mutation.WorkoutId, cancellationToken);
        if (workout.Version != mutation.BaseVersion)
        {
            throw new WorkoutConflictException("Only the current version of an existing workout can be deleted.");
        }

        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;
        List<WorkoutSet> sets = await context.WorkoutSets.Where(item => item.WorkoutId == workout.Id).ToListAsync(cancellationToken);
        List<WorkoutExercise> exercises = await context.WorkoutExercises.Where(item => item.WorkoutId == workout.Id).ToListAsync(cancellationToken);
        context.WorkoutSets.RemoveRange(sets);
        context.WorkoutExercises.RemoveRange(exercises);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        workout.DeletedAtUtc = now;
        workout.UpdatedAtUtc = now;
        workout.Version++;
        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);

        changeCollector?.CaptureDeletion(ResourceKey.Create(ResourceKind.Workout, workout.Id), workout.Version);
        return new DeleteWorkoutResult(workout.Id, workout.Version);
    }

    private async Task<Workout> FindOwnedAsync(Guid workoutId, CancellationToken cancellationToken) =>
        await context.Workouts.SingleOrDefaultAsync(
            item => item.Id == workoutId && item.DeletedAtUtc == null,
            cancellationToken) ?? throw new WorkoutNotFoundException();

    /// <summary>Own workout, own or base exercises (archived allowed for history), own or missing source plan and source workout.</summary>
    private async Task EnsureReferencesAvailableAsync(Guid userId, WorkoutValues values, CancellationToken cancellationToken)
    {
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        Guid[] exerciseIds = values.Exercises.Select(item => item.SourceExerciseId).Distinct().ToArray();
        if (exerciseIds.Length > 0)
        {
            int available = await context.Exercises.AsNoTracking()
                .Where(item => exerciseIds.Contains(item.Id))
                .Where(item => item.OwnerUserId == null || item.OwnerUserId == userId)
                .CountAsync(cancellationToken);
            if (available != exerciseIds.Length)
            {
                errors["Exercises.SourceExerciseId"] = UnavailableReferenceMessage;
            }
        }
        if (values.SourcePlanId is { } planId &&
            !await context.TrainingPlans.AsNoTracking().AnyAsync(item => item.Id == planId, cancellationToken))
        {
            errors[nameof(WorkoutValues.SourcePlanId)] = UnavailableReferenceMessage;
        }
        if (values.SourceWorkoutId is { } sourceId &&
            !await context.Workouts.AsNoTracking().AnyAsync(item => item.Id == sourceId, cancellationToken))
        {
            errors[nameof(WorkoutValues.SourceWorkoutId)] = UnavailableReferenceMessage;
        }
        if (errors.Count > 0)
        {
            throw new WorkoutValidationException(errors);
        }
    }

    private async Task EnsureNoOtherActiveWorkoutAsync(Guid workoutId, CancellationToken cancellationToken)
    {
        if (await context.Workouts.AsNoTracking().AnyAsync(
                item => item.Id != workoutId && item.EndedAtUtc == null && item.DeletedAtUtc == null,
                cancellationToken))
        {
            throw new ActiveWorkoutExistsException();
        }
    }

    private void AddExercises(Guid workoutId, IReadOnlyList<WorkoutExerciseValues> exercises)
    {
        for (int position = 0; position < exercises.Count; position++)
        {
            WorkoutExerciseValues exercise = exercises[position];
            context.WorkoutExercises.Add(new WorkoutExercise
            {
                Id = exercise.WorkoutExerciseId,
                WorkoutId = workoutId,
                SourceExerciseId = exercise.SourceExerciseId,
                ExerciseNameSnapshot = exercise.ExerciseNameSnapshot,
                ExerciseTypeSnapshot = ExerciseTypes.Parse(exercise.ExerciseTypeSnapshot),
                Position = position,
                Notes = exercise.Notes,
                SupersetId = exercise.SupersetId,
            });
            for (int setPosition = 0; setPosition < exercise.Sets.Count; setPosition++)
            {
                WorkoutSetValues set = exercise.Sets[setPosition];
                context.WorkoutSets.Add(new WorkoutSet
                {
                    Id = set.SetId,
                    WorkoutId = workoutId,
                    WorkoutExerciseId = exercise.WorkoutExerciseId,
                    Position = setPosition,
                    SetType = WorkoutSetTypes.ParseOrNormal(set.SetType),
                    WeightKg = set.WeightKg,
                    Repetitions = set.Repetitions,
                    Rir = set.Rir,
                    Notes = set.Notes,
                });
            }
        }
    }

    private static void Apply(Workout workout, WorkoutValues values)
    {
        workout.Title = values.Title;
        workout.Notes = values.Notes;
        workout.StartedAtUtc = values.StartedAtUtc;
        workout.EndedAtUtc = values.EndedAtUtc;
        workout.PreviousValueSource = PreviousValueSources.Parse(values.PreviousValueSource);
        workout.SourcePlanId = values.SourcePlanId;
        workout.SourceWorkoutId = values.SourceWorkoutId;
    }

    private WorkoutSnapshot Capture(Workout workout, IReadOnlyList<WorkoutExerciseValues> exercises)
    {
        WorkoutSnapshot snapshot = WorkoutSnapshots.Create(workout, exercises);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    private async Task SaveOrConflictAsync(CancellationToken cancellationToken)
    {
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new WorkoutConflictException("The workout changed concurrently.");
        }
        catch (DbUpdateException exception) when (context.IsKeyViolation<Workout>(exception))
        {
            throw new WorkoutConflictException("A workout with this identifier already exists.");
        }
        catch (DbUpdateException exception) when (context.IsUniqueIndexViolation<Workout>(exception, nameof(Workout.UserId)))
        {
            throw new ActiveWorkoutExistsException();
        }
    }

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");
}
