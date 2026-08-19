using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Gainer.Core.Values;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Persistence;

public sealed class WorkoutMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IWorkoutMutationHandler
{
    public async Task<WorkoutSnapshot> StartAsync(
        StartWorkoutMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        WorkoutTemplate template = await context.WorkoutTemplates.AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == mutation.TemplateId && !item.IsArchived, cancellationToken)
            ?? throw new WorkoutTemplateNotFoundException();
        List<WorkoutTemplateItem> templateItems = await context.WorkoutTemplateItems.AsNoTracking()
            .Where(item => item.TemplateId == template.Id)
            .OrderBy(item => item.Position)
            .ToListAsync(cancellationToken);
        if (templateItems.Count == 0)
        {
            throw new WorkoutValidationException(new Dictionary<string, string>
            {
                ["Template"] = "The template does not contain an exercise.",
            });
        }
        Guid[] sourceIds = templateItems.Select(item => item.ExerciseId).Distinct().ToArray();
        Dictionary<Guid, string> exerciseNames = await context.Exercises.AsNoTracking()
            .Where(item => sourceIds.Contains(item.Id))
            .Where(item => item.OwnerUserId == null || item.OwnerUserId == userId)
            .ToDictionaryAsync(item => item.Id, item => item.Name, cancellationToken);
        if (exerciseNames.Count != sourceIds.Length)
        {
            throw new WorkoutValidationException(new Dictionary<string, string>
            {
                ["Template.Exercises"] = "The complete template snapshot is unavailable.",
            });
        }

        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        var workout = new Workout
        {
            Id = mutation.WorkoutId,
            SourceTemplateId = template.Id,
            TemplateNameSnapshot = template.Name,
            Status = WorkoutStatus.Running,
            StartedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        };
        context.Workouts.Add(workout);
        var exerciseSnapshots = new List<WorkoutExerciseSnapshotValues>(templateItems.Count);
        foreach ((WorkoutTemplateItem item, int position) in templateItems.Select((item, index) => (item, index)))
        {
            Guid workoutExerciseId = Guid.NewGuid();
            var sets = Enumerable.Range(0, item.PlannedSets)
                .Select(_ => new WorkoutSetSnapshotValues(Guid.NewGuid(), null, null, null, null, false))
                .ToList();
            var values = new WorkoutExerciseSnapshotValues(
                workoutExerciseId,
                item.ExerciseId,
                exerciseNames[item.ExerciseId],
                item.PlannedSets,
                item.MinimumRepetitions,
                item.MaximumRepetitions,
                item.TargetRir,
                item.RestSeconds,
                item.Notes,
                sets);
            AddExercise(workout.Id, position, values);
            exerciseSnapshots.Add(values);
        }
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            throw new WorkoutConflictException("The workout identifier or snapshot conflicts with stored data.");
        }
        WorkoutSnapshot snapshot = Snapshot(workout, exerciseSnapshots);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<WorkoutSnapshot> EditAsync(
        EditWorkoutMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        Workout workout = await context.Workouts.SingleOrDefaultAsync(
            item => item.Id == mutation.WorkoutId,
            cancellationToken) ?? throw new WorkoutNotFoundException();
        if (workout.Status != WorkoutStatus.Running || workout.Version != mutation.BaseVersion)
        {
            throw new WorkoutConflictException("Only the current version of a running workout can be edited.");
        }
        List<WorkoutExercise> existingExercises = await context.WorkoutExercises
            .Where(item => item.WorkoutId == workout.Id).ToListAsync(cancellationToken);
        List<WorkoutSet> existingSets = await context.WorkoutSets
            .Where(item => item.WorkoutId == workout.Id).ToListAsync(cancellationToken);
        IReadOnlyList<WorkoutExerciseSnapshotValues> normalized = await ValidateAndNormalizeAsync(
            userId,
            mutation.Exercises,
            existingExercises,
            existingSets,
            cancellationToken);

        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;
        context.WorkoutSets.RemoveRange(existingSets);
        context.WorkoutExercises.RemoveRange(existingExercises);
        workout.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        workout.Version++;
        await SaveOrConflictAsync(cancellationToken);
        for (int position = 0; position < normalized.Count; position++)
        {
            AddExercise(workout.Id, position, normalized[position]);
        }
        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        WorkoutSnapshot snapshot = Snapshot(workout, normalized);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    public async Task<CompleteWorkoutResult> CompleteAsync(
        CompleteWorkoutMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(cancellationToken)
            : null;
        Workout workout = await context.Workouts.SingleOrDefaultAsync(
            item => item.Id == mutation.WorkoutId,
            cancellationToken) ?? throw new WorkoutNotFoundException();
        if (workout.Status != WorkoutStatus.Running || workout.Version != mutation.BaseVersion)
        {
            throw new WorkoutConflictException("Only the current version of a running workout can be completed.");
        }
        List<WorkoutExercise> exercises = await context.WorkoutExercises
            .Where(item => item.WorkoutId == workout.Id)
            .OrderBy(item => item.Position)
            .ToListAsync(cancellationToken);
        List<WorkoutSet> sets = await context.WorkoutSets
            .Where(item => item.WorkoutId == workout.Id)
            .OrderBy(item => item.WorkoutExerciseId).ThenBy(item => item.Position)
            .ToListAsync(cancellationToken);
        if (!sets.Any(item => item.IsCompleted))
        {
            throw new WorkoutValidationException(new Dictionary<string, string>
            {
                ["Sets"] = "At least one completed set is required.",
            });
        }

        WorkoutRotation? rotation = null;
        if (mutation.RotationId is { } rotationId && mutation.RotationBaseVersion is { } rotationVersion)
        {
            rotation = await context.WorkoutRotations.SingleOrDefaultAsync(
                item => item.Id == rotationId,
                cancellationToken) ?? throw new WorkoutRotationNotFoundException();
            bool sourceBelongsToRotation = workout.SourceTemplateId is { } templateId &&
                await context.WorkoutRotationItems.AnyAsync(
                    item => item.RotationId == rotationId && item.TemplateId == templateId,
                    cancellationToken);
            if (rotation.Version != rotationVersion || !sourceBelongsToRotation)
            {
                throw new WorkoutRotationConflictException("The rotation does not match the completed workout.");
            }
            rotation.LastCompletedTemplateId = workout.SourceTemplateId;
            rotation.Version++;
        }

        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        workout.Status = WorkoutStatus.Completed;
        workout.CompletedAtUtc = now;
        workout.UpdatedAtUtc = now;
        workout.Version++;
        foreach (WorkoutExercise exercise in exercises)
        {
            exercise.WorkoutCompletedAtUtc = now;
        }
        if (rotation is not null) rotation.UpdatedAtUtc = now;
        await SaveOrConflictAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);

        IReadOnlyList<WorkoutExerciseSnapshotValues> values = ToSnapshots(exercises, sets);
        WorkoutSnapshot workoutSnapshot = Snapshot(workout, values);
        WorkoutRotationSnapshot? rotationSnapshot = rotation is null
            ? null
            : await new WorkoutRotationHandler(context, userContext, timeProvider).GetAsync(cancellationToken);
        changeCollector?.CaptureUpsert(workoutSnapshot);
        if (rotationSnapshot is not null) changeCollector?.CaptureUpsert(rotationSnapshot);
        return new CompleteWorkoutResult(workoutSnapshot, rotationSnapshot);
    }

    public async Task<WorkoutSnapshot> DiscardAsync(
        DiscardWorkoutMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = CurrentUserId();
        Workout workout = await context.Workouts.SingleOrDefaultAsync(
            item => item.Id == mutation.WorkoutId,
            cancellationToken) ?? throw new WorkoutNotFoundException();
        if (workout.Status != WorkoutStatus.Running || workout.Version != mutation.BaseVersion)
        {
            throw new WorkoutConflictException("Only the current version of a running workout can be discarded.");
        }
        List<WorkoutExercise> exercises = await context.WorkoutExercises
            .Where(item => item.WorkoutId == workout.Id).OrderBy(item => item.Position).ToListAsync(cancellationToken);
        List<WorkoutSet> sets = await context.WorkoutSets
            .Where(item => item.WorkoutId == workout.Id).OrderBy(item => item.Position).ToListAsync(cancellationToken);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        workout.Status = WorkoutStatus.Discarded;
        workout.DiscardedAtUtc = now;
        workout.UpdatedAtUtc = now;
        workout.Version++;
        await SaveOrConflictAsync(cancellationToken);
        WorkoutSnapshot snapshot = Snapshot(workout, ToSnapshots(exercises, sets));
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    private async Task<IReadOnlyList<WorkoutExerciseSnapshotValues>> ValidateAndNormalizeAsync(
        Guid userId,
        IReadOnlyList<WorkoutExerciseSnapshotValues> exercises,
        IReadOnlyList<WorkoutExercise> existingExercises,
        IReadOnlyList<WorkoutSet> existingSets,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(exercises);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (exercises.Count > 100 || exercises.Select(item => item.WorkoutExerciseId).Distinct().Count() != exercises.Count ||
            exercises.Any(item => item.WorkoutExerciseId == Guid.Empty))
        {
            errors[nameof(exercises)] = "Workout exercise identifiers must be non-empty and unique.";
        }
        Dictionary<Guid, WorkoutExercise> existingById = existingExercises.ToDictionary(item => item.Id);
        Dictionary<Guid, WorkoutSet> existingSetsById = existingSets.ToDictionary(item => item.Id);
        Guid[] newSourceIds = exercises
            .Where(item => !existingById.ContainsKey(item.WorkoutExerciseId))
            .Select(item => item.SourceExerciseId ?? Guid.Empty)
            .Distinct().ToArray();
        Dictionary<Guid, string> newSourceNames = await context.Exercises.AsNoTracking()
            .Where(item => newSourceIds.Contains(item.Id))
            .Where(item => item.OwnerUserId == null || item.OwnerUserId == userId)
            .Where(item => !item.IsArchived)
            .ToDictionaryAsync(item => item.Id, item => item.Name, cancellationToken);
        var normalized = new List<WorkoutExerciseSnapshotValues>(exercises.Count);
        var allSetIds = new HashSet<Guid>();
        for (int index = 0; index < exercises.Count; index++)
        {
            WorkoutExerciseSnapshotValues item = exercises[index];
            WorkoutExercise? existing = existingById.GetValueOrDefault(item.WorkoutExerciseId);
            string prefix = $"Exercises[{index}]";
            Guid? sourceId = existing?.SourceExerciseId ?? item.SourceExerciseId;
            string name = existing?.ExerciseNameSnapshot ??
                (sourceId is { } id && newSourceNames.TryGetValue(id, out string? sourceName) ? sourceName : string.Empty);
            if (existing is not null && item.SourceExerciseId != existing.SourceExerciseId)
            {
                errors[$"{prefix}.SourceExerciseId"] = "An existing snapshot origin cannot be changed.";
            }
            if (existing is null && (sourceId is null || !newSourceNames.ContainsKey(sourceId.Value)))
            {
                errors[$"{prefix}.SourceExerciseId"] = "A new exercise must reference an available own or base exercise.";
            }
            ValidateExerciseValues(item, prefix, errors);
            var sets = new List<WorkoutSetSnapshotValues>(item.Sets.Count);
            for (int setIndex = 0; setIndex < item.Sets.Count; setIndex++)
            {
                WorkoutSetSnapshotValues set = item.Sets[setIndex];
                string setPrefix = $"{prefix}.Sets[{setIndex}]";
                if (set.SetId == Guid.Empty || !allSetIds.Add(set.SetId)) errors[$"{setPrefix}.SetId"] = "Set identifiers must be non-empty and unique.";
                ValidateSet(set, setPrefix, errors);
                DateTime? completedAt = set.IsCompleted
                    ? existingSetsById.GetValueOrDefault(set.SetId)?.CompletedAtUtc ?? timeProvider.GetUtcNow().UtcDateTime
                    : null;
                sets.Add(set with { Notes = Normalize(set.Notes), CompletedAtUtc = completedAt });
            }
            normalized.Add(item with { SourceExerciseId = sourceId, ExerciseNameSnapshot = name, Notes = Normalize(item.Notes), Sets = sets });
        }
        if (errors.Count > 0) throw new WorkoutValidationException(errors);
        return normalized;
    }

    private static void ValidateExerciseValues(
        WorkoutExerciseSnapshotValues item,
        string prefix,
        IDictionary<string, string> errors)
    {
        if (item.PlannedSets is < 1 or > 100) errors[$"{prefix}.PlannedSets"] = "Planned sets must be between 1 and 100.";
        if (item.MinimumRepetitions is < 1 or > 1_000 || item.MaximumRepetitions < item.MinimumRepetitions || item.MaximumRepetitions > 1_000) errors[$"{prefix}.Repetitions"] = "The repetition range is invalid.";
        if (item.TargetRir is { } rir && !RepetitionsInReserve.TryCreate(rir, out _)) errors[$"{prefix}.TargetRir"] = "RIR must be between 0 and 10.";
        if (item.RestSeconds is < 0 or > 86_400) errors[$"{prefix}.RestSeconds"] = "Rest is outside the supported range.";
        if (item.Notes?.Trim().Length > 2_000) errors[$"{prefix}.Notes"] = "Notes cannot exceed 2000 characters.";
        if (item.Sets.Count > 200) errors[$"{prefix}.Sets"] = "An exercise cannot contain more than 200 sets.";
    }

    private static void ValidateSet(
        WorkoutSetSnapshotValues set,
        string prefix,
        IDictionary<string, string> errors)
    {
        if (set.WeightKg is { } weight && (weight < 0 || !Kilograms.TryCreate(weight, out _))) errors[$"{prefix}.WeightKg"] = "Weight cannot be negative.";
        if (set.Repetitions is { } repetitions && repetitions < 1) errors[$"{prefix}.Repetitions"] = "Repetitions must be positive.";
        if (set.Rir is { } rir && !RepetitionsInReserve.TryCreate(rir, out _)) errors[$"{prefix}.Rir"] = "RIR must be between 0 and 10.";
        if (set.IsCompleted && (set.WeightKg is null || set.Repetitions is null)) errors[$"{prefix}.Completion"] = "A completed set requires weight and repetitions.";
        if (set.Notes?.Trim().Length > 2_000) errors[$"{prefix}.Notes"] = "Notes cannot exceed 2000 characters.";
    }

    private void AddExercise(Guid workoutId, int position, WorkoutExerciseSnapshotValues values)
    {
        context.WorkoutExercises.Add(new WorkoutExercise
        {
            Id = values.WorkoutExerciseId,
            WorkoutId = workoutId,
            SourceExerciseId = values.SourceExerciseId,
            ExerciseNameSnapshot = values.ExerciseNameSnapshot,
            Position = position,
            PlannedSets = values.PlannedSets,
            MinimumRepetitions = values.MinimumRepetitions,
            MaximumRepetitions = values.MaximumRepetitions,
            TargetRir = values.TargetRir,
            RestSeconds = values.RestSeconds,
            Notes = values.Notes,
        });
        for (int setPosition = 0; setPosition < values.Sets.Count; setPosition++)
        {
            WorkoutSetSnapshotValues set = values.Sets[setPosition];
            context.WorkoutSets.Add(new WorkoutSet
            {
                Id = set.SetId,
                WorkoutId = workoutId,
                WorkoutExerciseId = values.WorkoutExerciseId,
                Position = setPosition,
                WeightKg = set.WeightKg,
                Repetitions = set.Repetitions,
                Rir = set.Rir,
                Notes = set.Notes,
                IsCompleted = set.IsCompleted,
                CompletedAtUtc = set.CompletedAtUtc,
            });
        }
    }

    private static IReadOnlyList<WorkoutExerciseSnapshotValues> ToSnapshots(
        IReadOnlyList<WorkoutExercise> exercises,
        IReadOnlyList<WorkoutSet> sets)
    {
        return exercises.OrderBy(item => item.Position).Select(exercise =>
            new WorkoutExerciseSnapshotValues(
                exercise.Id,
                exercise.SourceExerciseId,
                exercise.ExerciseNameSnapshot,
                exercise.PlannedSets,
                exercise.MinimumRepetitions,
                exercise.MaximumRepetitions,
                exercise.TargetRir,
                exercise.RestSeconds,
                exercise.Notes,
                sets.Where(set => set.WorkoutExerciseId == exercise.Id)
                    .OrderBy(set => set.Position)
                    .Select(set => new WorkoutSetSnapshotValues(
                        set.Id,
                        set.WeightKg,
                        set.Repetitions,
                        set.Rir,
                        set.Notes,
                        set.IsCompleted,
                        set.CompletedAtUtc))
                    .ToList()))
            .ToList();
    }

    private async Task SaveOrConflictAsync(CancellationToken cancellationToken)
    {
        try { await context.SaveChangesAsync(cancellationToken); }
        catch (DbUpdateConcurrencyException) { throw new WorkoutConflictException("The workout changed concurrently."); }
        catch (DbUpdateException) { throw new WorkoutConflictException("The workout snapshot conflicts with stored data."); }
    }

    private static WorkoutSnapshot Snapshot(Workout workout, IReadOnlyList<WorkoutExerciseSnapshotValues> exercises) => new(
        workout.Id, workout.SourceTemplateId, workout.TemplateNameSnapshot, workout.Status,
        exercises, workout.StartedAtUtc, workout.CompletedAtUtc, workout.DiscardedAtUtc,
        workout.UpdatedAtUtc, workout.Version);

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private static string? Normalize(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
