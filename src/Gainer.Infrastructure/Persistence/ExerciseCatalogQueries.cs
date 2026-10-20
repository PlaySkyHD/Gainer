using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class ExerciseCatalogQueries(AppDbContext context, IUserContext userContext)
    : IExerciseCatalogQueries, IExerciseResolver
{
    public async Task<ExerciseCatalogPage> SearchAsync(
        ExerciseCatalogFilter filter,
        CancellationToken cancellationToken = default)
    {
        if (filter.Offset < 0 || filter.Limit is < 1 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(filter));
        }

        ValidateFilterLength(filter.Search, nameof(filter.Search));
        ValidateFilterLength(filter.TargetMuscle, nameof(filter.TargetMuscle));
        ValidateFilterLength(filter.MuscleGroup, nameof(filter.MuscleGroup));
        ValidateFilterLength(filter.Equipment, nameof(filter.Equipment));

        Guid userId = userContext.UserId
            ?? throw new InvalidOperationException("An authenticated user is required.");
        IQueryable<Exercise> query = context.Exercises
            .AsNoTracking()
            .Where(item => item.OwnerUserId == null || item.OwnerUserId == userId)
            .Where(item => !item.IsArchived);

        if (!string.IsNullOrWhiteSpace(filter.Search))
        {
            string pattern = $"%{EscapeLikePattern(filter.Search.Trim())}%";
            query = query.Where(item => EF.Functions.ILike(item.Name, pattern, "\\"));
        }
        if (!string.IsNullOrWhiteSpace(filter.TargetMuscle))
        {
            query = query.Where(item => item.TargetMuscle == filter.TargetMuscle.Trim());
        }
        if (!string.IsNullOrWhiteSpace(filter.MuscleGroup))
        {
            query = query.Where(item => item.MuscleGroup == filter.MuscleGroup.Trim());
        }
        if (!string.IsNullOrWhiteSpace(filter.Equipment))
        {
            query = query.Where(item => item.Equipment == filter.Equipment.Trim());
        }

        int total = await query.CountAsync(cancellationToken);
        List<ExerciseCatalogItem> items = await Project(query
            .OrderBy(item => item.Name)
            .ThenBy(item => item.Id)
            .Skip(filter.Offset)
            .Take(filter.Limit), cancellationToken);
        List<ExerciseCategoryItem> categories = await context.ExerciseCategories
            .AsNoTracking()
            .Where(item => item.OwnerUserId == null || (item.OwnerUserId == userId && !item.IsArchived))
            .Select(item => new ExerciseCategoryItem(item.Id, item.Name, item.OwnerUserId == null))
            .ToListAsync(cancellationToken);
        return new ExerciseCatalogPage(
            items,
            filter.Offset,
            filter.Limit,
            total,
            categories.OrderBy(item => item.IsBase ? 0 : 1).ThenBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase).ToList());
    }

    public async Task<ExerciseCatalogItem?> ResolveAsync(
        Guid exerciseId,
        bool includeArchived,
        CancellationToken cancellationToken = default)
    {
        Guid userId = userContext.UserId
            ?? throw new InvalidOperationException("An authenticated user is required.");
        List<ExerciseCatalogItem> items = await Project(context.Exercises
            .AsNoTracking()
            .Where(item => item.Id == exerciseId)
            .Where(item => item.OwnerUserId == null || item.OwnerUserId == userId)
            .Where(item => includeArchived || !item.IsArchived), cancellationToken);
        return items.SingleOrDefault();
    }

    private async Task<List<ExerciseCatalogItem>> Project(IQueryable<Exercise> query, CancellationToken cancellationToken)
    {
        List<ExerciseCatalogItem> exercises = await query
            .Select(item => new ExerciseCatalogItem(
                item.Id,
                item.Name,
                item.Description,
                item.TargetMuscle,
                item.MuscleGroup,
                item.Equipment,
                item.OwnerUserId != null,
                item.CatalogVersion,
                item.Version,
                item.ExerciseType,
                item.Notes,
                item.BodyweightFactor,
                item.WeightFactor,
                Array.Empty<Guid>(),
                item.PrimaryMuscles,
                item.SecondaryMuscles))
            .ToListAsync(cancellationToken);
        if (exercises.Count == 0)
        {
            return exercises;
        }
        Guid[] exerciseIds = exercises.Select(item => item.Id).ToArray();
        var categoryIds = (await context.ExerciseCategoryAssignments.AsNoTracking()
            .Where(item => exerciseIds.Contains(item.ExerciseId))
            .Select(item => new { item.ExerciseId, item.CategoryId })
            .ToListAsync(cancellationToken))
            .GroupBy(item => item.ExerciseId)
            .ToDictionary(group => group.Key, group => group.Select(item => item.CategoryId).Order().ToArray());
        return exercises.Select(item => item with
        {
            CategoryIds = categoryIds.TryGetValue(item.Id, out Guid[]? ids) ? ids : Array.Empty<Guid>(),
        }).ToList();
    }

    private static void ValidateFilterLength(string? value, string name)
    {
        if (value?.Length > 100)
        {
            throw new ArgumentOutOfRangeException(name);
        }
    }

    private static string EscapeLikePattern(string value) =>
        value.Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("%", "\\%", StringComparison.Ordinal)
            .Replace("_", "\\_", StringComparison.Ordinal);
}
