using Gainer.Core.Training;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class WorkoutRotationQueries(AppDbContext context) : IWorkoutRotationQueries
{
    public async Task<Guid?> LastFinishedPlanIdAsync(
        IReadOnlyList<Guid> rotationPlanIds,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(rotationPlanIds);
        if (rotationPlanIds.Count == 0)
        {
            return null;
        }
        Guid[] planIds = rotationPlanIds.ToArray();
        return await context.Workouts.AsNoTracking()
            .Where(item => item.EndedAtUtc != null && item.DeletedAtUtc == null && item.SourcePlanId != null)
            .Where(item => planIds.Contains(item.SourcePlanId!.Value))
            .OrderByDescending(item => item.EndedAtUtc)
            .ThenByDescending(item => item.Id)
            .Select(item => item.SourcePlanId)
            .FirstOrDefaultAsync(cancellationToken);
    }

    public async Task<Guid?> NextPlanIdAsync(CancellationToken cancellationToken = default)
    {
        Guid[] rotationPlanIds = await (
            from rotation in context.WorkoutRotations.AsNoTracking()
            join item in context.WorkoutRotationItems.AsNoTracking() on rotation.Id equals item.RotationId
            orderby item.Position
            select item.PlanId)
            .ToArrayAsync(cancellationToken);
        if (rotationPlanIds.Length == 0)
        {
            return null;
        }
        Guid[] archived = await context.TrainingPlans.AsNoTracking()
            .Where(item => rotationPlanIds.Contains(item.Id) && item.IsArchived)
            .Select(item => item.Id)
            .ToArrayAsync(cancellationToken);
        Guid? last = await LastFinishedPlanIdAsync(rotationPlanIds, cancellationToken);
        return WorkoutRotationSuggestion.Next(rotationPlanIds, archived, last);
    }
}
