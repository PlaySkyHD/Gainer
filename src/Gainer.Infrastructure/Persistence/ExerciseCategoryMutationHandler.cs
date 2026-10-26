using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class ExerciseCategoryMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IExerciseCategoryMutationHandler
{
    public async Task<ExerciseCategorySnapshot> CreateAsync(
        CreateExerciseCategoryMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        Guid userId = CurrentUserId();
        string name = ValidateName(mutation.Name);
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        var category = new ExerciseCategory
        {
            Id = mutation.CategoryId,
            OwnerUserId = userId,
            Name = name,
            CreatedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        };
        context.ExerciseCategories.Add(category);
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException exception) when (context.IsKeyViolation<ExerciseCategory>(exception))
        {
            throw new ExerciseCategoryConflictException("The category identifier already exists.");
        }
        return Capture(category);
    }

    public async Task<ExerciseCategorySnapshot> UpdateAsync(
        UpdateExerciseCategoryMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        string name = ValidateName(mutation.Name);
        ExerciseCategory category = await FindOwnedAsync(mutation.CategoryId, cancellationToken);
        if (category.Version != mutation.BaseVersion || category.IsArchived)
        {
            throw new ExerciseCategoryConflictException("The category cannot be renamed from this version.");
        }
        category.Name = name;
        Advance(category);
        await SaveOrConflictAsync(cancellationToken);
        return Capture(category);
    }

    public async Task<ExerciseCategorySnapshot> ArchiveAsync(
        ArchiveExerciseCategoryMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        ExerciseCategory category = await FindOwnedAsync(mutation.CategoryId, cancellationToken);
        if (category.Version != mutation.BaseVersion || category.IsArchived)
        {
            throw new ExerciseCategoryConflictException("The category cannot be archived from this version.");
        }
        category.IsArchived = true;
        Advance(category);
        await SaveOrConflictAsync(cancellationToken);
        return Capture(category);
    }

    private async Task<ExerciseCategory> FindOwnedAsync(Guid categoryId, CancellationToken cancellationToken)
    {
        Guid userId = CurrentUserId();
        return await context.ExerciseCategories.SingleOrDefaultAsync(
            item => item.Id == categoryId && item.OwnerUserId == userId,
            cancellationToken) ?? throw new ExerciseCategoryNotFoundException();
    }

    private Guid CurrentUserId() => userContext.UserId
        ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private void Advance(ExerciseCategory category)
    {
        category.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        category.Version++;
    }

    private async Task SaveOrConflictAsync(CancellationToken cancellationToken)
    {
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new ExerciseCategoryConflictException("The category changed concurrently.");
        }
    }

    private ExerciseCategorySnapshot Capture(ExerciseCategory category)
    {
        var snapshot = new ExerciseCategorySnapshot(
            category.Id,
            category.Name,
            category.IsArchived,
            category.CreatedAtUtc,
            category.UpdatedAtUtc,
            category.Version);
        changeCollector?.CaptureUpsert(snapshot);
        return snapshot;
    }

    private static string ValidateName(string? name)
    {
        string trimmed = name?.Trim() ?? string.Empty;
        if (trimmed.Length is < 1 or > 80)
        {
            throw new ExerciseCategoryValidationException(new Dictionary<string, string>(StringComparer.Ordinal)
            {
                [nameof(ExerciseCategory.Name)] = "Name must contain between 1 and 80 characters.",
            });
        }
        return trimmed;
    }
}
