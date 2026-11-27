using Gainer.Core.Nutrition;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class NutritionDayTemplateQueries(AppDbContext context) : INutritionDayTemplateQueries
{
    public async Task<IReadOnlyList<NutritionDayTemplateSnapshot>> ListAsync(CancellationToken cancellationToken = default)
    {
        List<NutritionDayTemplate> templates = await context.NutritionDayTemplates.AsNoTracking()
            .Include(item => item.Entries)
            .AsSplitQuery()
            .OrderBy(item => item.Name)
            .ThenBy(item => item.Id)
            .ToListAsync(cancellationToken);
        return templates.Select(template => NutritionDayTemplateMutationHandler.Snapshot(template)).ToList();
    }
}
