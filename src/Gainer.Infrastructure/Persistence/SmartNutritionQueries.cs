using Gainer.Core.Nutrition;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class SmartNutritionQueries(AppDbContext context) : ISmartNutritionQueries
{
    public async Task<IReadOnlyList<ReusableMealSnapshot>> GetReusableMealsAsync(
        bool includeArchived,
        CancellationToken cancellationToken = default)
    {
        IQueryable<ReusableMeal> query = context.ReusableMeals.AsNoTracking().Include(item => item.Components);
        if (!includeArchived) query = query.Where(item => item.Status == ReusableMealStatus.Active);
        ReusableMeal[] meals = await query.OrderBy(item => item.Name).ThenBy(item => item.Id).ToArrayAsync(cancellationToken);
        return meals.Select(item => SmartNutritionSnapshots.ReusableMeal(item)).ToArray();
    }

    public async Task<ReusableMealSnapshot?> GetReusableMealAsync(
        Guid reusableMealId,
        CancellationToken cancellationToken = default)
    {
        if (reusableMealId == Guid.Empty) throw new ArgumentException("Reusable meal identifier cannot be empty.", nameof(reusableMealId));
        ReusableMeal? meal = await context.ReusableMeals.AsNoTracking()
            .Include(item => item.Components)
            .SingleOrDefaultAsync(item => item.Id == reusableMealId, cancellationToken);
        return meal is null ? null : SmartNutritionSnapshots.ReusableMeal(meal);
    }

    public async Task<NutritionTargetScheduleSnapshot?> GetNutritionTargetScheduleAsync(
        CancellationToken cancellationToken = default)
    {
        NutritionTargetSchedule? schedule = await context.NutritionTargetSchedules.AsNoTracking()
            .Include(item => item.Versions)
            .SingleOrDefaultAsync(cancellationToken);
        return schedule is null ? null : SmartNutritionSnapshots.TargetSchedule(schedule);
    }

    public async Task<NutritionTargetVersionDraft?> GetEffectiveNutritionTargetAsync(
        DateOnly localDate,
        CancellationToken cancellationToken = default)
    {
        NutritionTargetVersion? target = await context.NutritionTargetVersions.AsNoTracking()
            .Where(item => item.EffectiveFrom <= localDate &&
                (item.EffectiveUntil == null || item.EffectiveUntil >= localDate))
            .OrderByDescending(item => item.EffectiveFrom)
            .ThenByDescending(item => item.Id)
            .FirstOrDefaultAsync(cancellationToken);
        return target is null ? null : SmartNutritionSnapshots.TargetVersion(target);
    }
}
