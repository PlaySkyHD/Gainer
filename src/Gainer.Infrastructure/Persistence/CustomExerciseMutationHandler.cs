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
    private const int MaximumCategories = 10;
    private const string UnavailableCategoriesMessage = "One or more categories are unknown or unavailable.";

    public async Task<CustomExerciseSnapshot> CreateAsync(
        CreateCustomExerciseMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        CustomExerciseValues values = ValidateAndNormalize(mutation.Values);
        await EnsureCategoriesAvailableAsync(userId, values.CategoryIds!, cancellationToken);
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
        context.ExerciseCategoryAssignments.AddRange(values.CategoryIds!.Select(categoryId => new ExerciseCategoryAssignment
        {
            ExerciseId = exercise.Id,
            CategoryId = categoryId,
        }));
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            throw new CustomExerciseConflictException("The exercise identifier already exists.");
        }
        return Capture(exercise, values.CategoryIds!);
    }

    public async Task<CustomExerciseSnapshot> UpdateAsync(
        UpdateCustomExerciseMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        CustomExerciseValues values = ValidateAndNormalize(mutation.Values);
        Guid userId = CurrentUserId();
        Exercise exercise = await FindOwnedAsync(mutation.ExerciseId, cancellationToken);
        if (exercise.Version != mutation.BaseVersion || exercise.IsArchived)
        {
            throw new CustomExerciseConflictException("The custom exercise cannot be updated from this version.");
        }
        await EnsureCategoriesAvailableAsync(userId, values.CategoryIds!, cancellationToken);
        await ReplaceCategoriesAsync(exercise.Id, values.CategoryIds!, cancellationToken);
        Apply(exercise, values);
        Advance(exercise);
        await SaveOrConflictAsync(cancellationToken);
        return Capture(exercise, values.CategoryIds!);
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
        Guid[] categoryIds = await context.ExerciseCategoryAssignments.AsNoTracking()
            .Where(item => item.ExerciseId == exercise.Id)
            .Select(item => item.CategoryId)
            .OrderBy(item => item)
            .ToArrayAsync(cancellationToken);
        return Capture(exercise, categoryIds);
    }

    private async Task<Exercise> FindOwnedAsync(Guid exerciseId, CancellationToken cancellationToken)
    {
        Guid userId = CurrentUserId();
        return await context.Exercises.SingleOrDefaultAsync(
            item => item.Id == exerciseId && item.OwnerUserId == userId,
            cancellationToken) ?? throw new CustomExerciseNotFoundException();
    }

    /// <summary>Base categories and own, non-archived categories are assignable; anything else is reported as unavailable.</summary>
    private async Task EnsureCategoriesAvailableAsync(Guid userId, IReadOnlyList<Guid> categoryIds, CancellationToken cancellationToken)
    {
        if (categoryIds.Count == 0)
        {
            return;
        }
        Guid[] requested = categoryIds.ToArray();
        int available = await context.ExerciseCategories.AsNoTracking()
            .Where(item => requested.Contains(item.Id))
            .Where(item => item.OwnerUserId == null || (item.OwnerUserId == userId && !item.IsArchived))
            .CountAsync(cancellationToken);
        if (available != requested.Length)
        {
            throw new CustomExerciseValidationException(new Dictionary<string, string>(StringComparer.Ordinal)
            {
                [nameof(CustomExerciseValues.CategoryIds)] = UnavailableCategoriesMessage,
            });
        }
    }

    private async Task ReplaceCategoriesAsync(Guid exerciseId, IReadOnlyList<Guid> categoryIds, CancellationToken cancellationToken)
    {
        List<ExerciseCategoryAssignment> current = await context.ExerciseCategoryAssignments
            .Where(item => item.ExerciseId == exerciseId)
            .ToListAsync(cancellationToken);
        context.ExerciseCategoryAssignments.RemoveRange(current.Where(item => !categoryIds.Contains(item.CategoryId)));
        context.ExerciseCategoryAssignments.AddRange(categoryIds
            .Except(current.Select(item => item.CategoryId))
            .Select(categoryId => new ExerciseCategoryAssignment { ExerciseId = exerciseId, CategoryId = categoryId }));
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

    private CustomExerciseSnapshot Capture(Exercise exercise, IReadOnlyList<Guid> categoryIds)
    {
        CustomExerciseSnapshot snapshot = Snapshot(exercise, categoryIds);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    internal static CustomExerciseSnapshot Snapshot(Exercise exercise, IReadOnlyList<Guid> categoryIds) => new(
        exercise.Id,
        new CustomExerciseValues(
            exercise.Name,
            ExerciseTypes.ToStorageValue(exercise.ExerciseType),
            exercise.Description,
            exercise.TargetMuscle,
            exercise.MuscleGroup,
            exercise.Equipment,
            exercise.Notes,
            exercise.BodyweightFactor,
            exercise.WeightFactor,
            categoryIds,
            exercise.PrimaryMuscles,
            exercise.SecondaryMuscles),
        exercise.IsArchived,
        exercise.CreatedAtUtc,
        exercise.UpdatedAtUtc,
        exercise.Version);

    private static CustomExerciseValues ValidateAndNormalize(CustomExerciseValues values)
    {
        ArgumentNullException.ThrowIfNull(values);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        string name = values.Name?.Trim() ?? string.Empty;
        if (name.Length is < 1 or > 160)
        {
            errors[nameof(values.Name)] = "Name must contain between 1 and 160 characters.";
        }
        if (!ExerciseTypes.TryParse(values.ExerciseType, out ExerciseType exerciseType))
        {
            errors[nameof(values.ExerciseType)] = "The exercise type is unknown.";
        }
        ValidateOptional(values.Description, 2_000, nameof(values.Description), errors);
        ValidateOptional(values.TargetMuscle, 100, nameof(values.TargetMuscle), errors);
        ValidateOptional(values.MuscleGroup, 100, nameof(values.MuscleGroup), errors);
        ValidateOptional(values.Equipment, 100, nameof(values.Equipment), errors);
        ValidateOptional(values.Notes, 2_000, nameof(values.Notes), errors);
        if (values.BodyweightFactor is < 0m or > ExerciseFactors.MaximumBodyweightFactor)
        {
            errors[nameof(values.BodyweightFactor)] = "The bodyweight factor must be between 0 and 1.";
        }
        if (values.WeightFactor is <= 0m or > ExerciseFactors.MaximumWeightFactor)
        {
            errors[nameof(values.WeightFactor)] = "The weight factor must be greater than 0 and at most 10.";
        }
        Guid[] categoryIds = values.CategoryIds?.ToArray() ?? [];
        if (categoryIds.Length > MaximumCategories)
        {
            errors[nameof(values.CategoryIds)] = $"An exercise can belong to at most {MaximumCategories} categories.";
        }
        else if (categoryIds.Distinct().Count() != categoryIds.Length)
        {
            errors[nameof(values.CategoryIds)] = "Categories must not be repeated.";
        }
        string[] primaryMuscles = values.PrimaryMuscles?.ToArray() ?? [];
        string[] secondaryMuscles = values.SecondaryMuscles?.ToArray() ?? [];
        string? muscleError = MuscleKeys.Validate(primaryMuscles, secondaryMuscles);
        if (muscleError is not null)
        {
            errors[nameof(values.PrimaryMuscles)] = muscleError;
        }
        if (errors.Count > 0)
        {
            throw new CustomExerciseValidationException(errors);
        }
        return new CustomExerciseValues(
            name,
            ExerciseTypes.ToStorageValue(exerciseType),
            Normalize(values.Description),
            Normalize(values.TargetMuscle),
            Normalize(values.MuscleGroup),
            Normalize(values.Equipment),
            Normalize(values.Notes),
            values.BodyweightFactor,
            values.WeightFactor,
            categoryIds.Order().ToArray(),
            primaryMuscles,
            secondaryMuscles);
    }

    private static void ValidateOptional(
        string? value,
        int maximum,
        string name,
        Dictionary<string, string> errors)
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
        exercise.ExerciseType = ExerciseTypes.Parse(values.ExerciseType);
        exercise.Description = values.Description;
        exercise.TargetMuscle = values.TargetMuscle;
        exercise.MuscleGroup = values.MuscleGroup;
        exercise.Equipment = values.Equipment;
        exercise.Notes = values.Notes;
        exercise.BodyweightFactor = values.BodyweightFactor;
        exercise.WeightFactor = values.WeightFactor;
        exercise.PrimaryMuscles = [.. values.PrimaryMuscles!];
        exercise.SecondaryMuscles = [.. values.SecondaryMuscles!];
    }
}
