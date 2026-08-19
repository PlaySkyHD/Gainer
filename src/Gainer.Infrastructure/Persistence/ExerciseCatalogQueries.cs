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
        List<ExerciseCatalogItem> items = await query
            .OrderBy(item => item.Name)
            .ThenBy(item => item.Id)
            .Skip(filter.Offset)
            .Take(filter.Limit)
            .Select(item => new ExerciseCatalogItem(
                item.Id,
                item.Name,
                item.Description,
                item.TargetMuscle,
                item.MuscleGroup,
                item.Equipment,
                item.OwnerUserId != null,
                item.CatalogVersion,
                item.Version))
            .ToListAsync(cancellationToken);
        return new ExerciseCatalogPage(items, filter.Offset, filter.Limit, total);
    }

    public async Task<ExerciseCatalogItem?> ResolveAsync(
        Guid exerciseId,
        bool includeArchived,
        CancellationToken cancellationToken = default)
    {
        Guid userId = userContext.UserId
            ?? throw new InvalidOperationException("An authenticated user is required.");
        return await context.Exercises
            .AsNoTracking()
            .Where(item => item.Id == exerciseId)
            .Where(item => item.OwnerUserId == null || item.OwnerUserId == userId)
            .Where(item => includeArchived || !item.IsArchived)
            .Select(item => new ExerciseCatalogItem(
                item.Id,
                item.Name,
                item.Description,
                item.TargetMuscle,
                item.MuscleGroup,
                item.Equipment,
                item.OwnerUserId != null,
                item.CatalogVersion,
                item.Version))
            .SingleOrDefaultAsync(cancellationToken);
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
