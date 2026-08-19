using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class CustomExerciseMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : ICustomExerciseMutationHandler
{
    public async Task<CustomExerciseSnapshot> CreateAsync(
        CreateCustomExerciseMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        CustomExerciseValues values = ValidateAndNormalize(mutation.Values);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        var exercise = new Exercise
        {
            Id = mutation.ExerciseId,
            OwnerUserId = userId,
            CreatedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        };
        Apply(exercise, values);
        context.Exercises.Add(exercise);
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            throw new CustomExerciseConflictException("The exercise identifier already exists.");
        }
        return Capture(exercise);
    }

    public async Task<CustomExerciseSnapshot> UpdateAsync(
        UpdateCustomExerciseMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        CustomExerciseValues values = ValidateAndNormalize(mutation.Values);
        Exercise exercise = await FindOwnedAsync(mutation.ExerciseId, cancellationToken);
        if (exercise.Version != mutation.BaseVersion || exercise.IsArchived)
        {
            throw new CustomExerciseConflictException("The custom exercise cannot be updated from this version.");
        }
        Apply(exercise, values);
        Advance(exercise);
        await SaveOrConflictAsync(cancellationToken);
        return Capture(exercise);
    }

    public async Task<CustomExerciseSnapshot> ArchiveAsync(
        ArchiveCustomExerciseMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Exercise exercise = await FindOwnedAsync(mutation.ExerciseId, cancellationToken);
        if (exercise.Version != mutation.BaseVersion || exercise.IsArchived)
        {
            throw new CustomExerciseConflictException("The custom exercise cannot be archived from this version.");
        }
        exercise.IsArchived = true;
        Advance(exercise);
        await SaveOrConflictAsync(cancellationToken);
        return Capture(exercise);
    }

    private async Task<Exercise> FindOwnedAsync(Guid exerciseId, CancellationToken cancellationToken)
    {
        Guid userId = CurrentUserId();
        return await context.Exercises.SingleOrDefaultAsync(
            item => item.Id == exerciseId && item.OwnerUserId == userId,
            cancellationToken) ?? throw new CustomExerciseNotFoundException();
    }

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private void Advance(Exercise exercise)
    {
        exercise.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        exercise.Version++;
    }

    private async Task SaveOrConflictAsync(CancellationToken cancellationToken)
    {
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new CustomExerciseConflictException("The custom exercise changed concurrently.");
        }
    }

    private CustomExerciseSnapshot Capture(Exercise exercise)
    {
        CustomExerciseSnapshot snapshot = Snapshot(exercise);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    internal static CustomExerciseSnapshot Snapshot(Exercise exercise) => new(
        exercise.Id,
        new CustomExerciseValues(
            exercise.Name,
            exercise.Description,
            exercise.TargetMuscle,
            exercise.MuscleGroup,
            exercise.Equipment),
        exercise.IsArchived,
        exercise.CreatedAtUtc,
        exercise.UpdatedAtUtc,
        exercise.Version);

    private static CustomExerciseValues ValidateAndNormalize(CustomExerciseValues values)
    {
        ArgumentNullException.ThrowIfNull(values);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        string name = values.Name.Trim();
        if (name.Length is < 1 or > 160)
        {
            errors[nameof(values.Name)] = "Name must contain between 1 and 160 characters.";
        }
        ValidateOptional(values.Description, 2_000, nameof(values.Description), errors);
        ValidateOptional(values.TargetMuscle, 100, nameof(values.TargetMuscle), errors);
        ValidateOptional(values.MuscleGroup, 100, nameof(values.MuscleGroup), errors);
        ValidateOptional(values.Equipment, 100, nameof(values.Equipment), errors);
        if (errors.Count > 0)
        {
            throw new CustomExerciseValidationException(errors);
        }
        return new CustomExerciseValues(
            name,
            Normalize(values.Description),
            Normalize(values.TargetMuscle),
            Normalize(values.MuscleGroup),
            Normalize(values.Equipment));
    }

    private static void ValidateOptional(
        string? value,
        int maximum,
        string name,
        IDictionary<string, string> errors)
    {
        if (value?.Trim().Length > maximum)
        {
            errors[name] = $"{name} cannot exceed {maximum} characters.";
        }
    }

    private static string? Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static void Apply(Exercise exercise, CustomExerciseValues values)
    {
        exercise.Name = values.Name;
        exercise.Description = values.Description;
        exercise.TargetMuscle = values.TargetMuscle;
        exercise.MuscleGroup = values.MuscleGroup;
        exercise.Equipment = values.Equipment;
    }
}
