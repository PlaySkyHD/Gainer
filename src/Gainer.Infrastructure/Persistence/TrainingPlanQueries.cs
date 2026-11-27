using Gainer.Core.Security;
using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class TrainingPlanQueries(AppDbContext context, IUserContext userContext) : ITrainingPlanQueries
{
    public async Task<IReadOnlyList<TrainingPlanDetail>> ListAsync(
        bool includeArchived,
        CancellationToken cancellationToken = default)
    {
        List<TrainingPlan> plans = await context.TrainingPlans.AsNoTracking()
            .Where(item => includeArchived || !item.IsArchived)
            .OrderBy(item => item.SortOrder)
            .ThenBy(item => item.Id)
            .ToListAsync(cancellationToken);
        return await DetailsAsync(plans, cancellationToken);
    }

    public async Task<TrainingPlanDetail?> GetAsync(Guid planId, CancellationToken cancellationToken = default)
    {
        TrainingPlan? plan = await context.TrainingPlans.AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == planId, cancellationToken);
        return plan is null ? null : (await DetailsAsync([plan], cancellationToken))[0];
    }

    private async Task<IReadOnlyList<TrainingPlanDetail>> DetailsAsync(
        List<TrainingPlan> plans,
        CancellationToken cancellationToken)
    {
        if (plans.Count == 0) return [];
        Guid userId = userContext.UserId
            ?? throw new InvalidOperationException("An authenticated user is required.");
        Guid[] planIds = plans.Select(item => item.Id).ToArray();
        List<TrainingPlanEntry> entries = await context.TrainingPlanEntries.AsNoTracking()
            .Where(item => planIds.Contains(item.PlanId))
            .OrderBy(item => item.Position)
            .ToListAsync(cancellationToken);
        Guid[] exerciseIds = entries.Select(item => item.ExerciseId).Distinct().ToArray();
        // Exercises are not user-owned entities: base catalog or the user's own ones only.
        Dictionary<Guid, string> names = await context.Exercises.AsNoTracking()
            .Where(item => exerciseIds.Contains(item.Id))
            .Where(item => item.OwnerUserId == null || item.OwnerUserId == userId)
            .ToDictionaryAsync(item => item.Id, item => item.Name, cancellationToken);
        ILookup<Guid, TrainingPlanEntry> entriesByPlan = entries.ToLookup(item => item.PlanId);
        return plans
            .Select(plan => new TrainingPlanDetail(
                TrainingSnapshots.Plan(plan, entriesByPlan[plan.Id].Select(TrainingSnapshots.PlanEntry).ToList()),
                names))
            .ToList();
    }
}
