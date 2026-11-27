using Gainer.Core.Nutrition;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class WaterIntakeQueries(AppDbContext context) : IWaterIntakeQueries
{
    public async Task<IReadOnlyList<WaterIntakeDaySnapshot>> GetDaysAsync(
        DateOnly from,
        DateOnly through,
        CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(through, from);
        List<WaterIntakeDay> days = await context.WaterIntakeDays.AsNoTracking()
            .Where(item => item.LocalDate >= from && item.LocalDate <= through)
            .OrderBy(item => item.LocalDate)
            .ToListAsync(cancellationToken);
        return days.Select(WaterIntakeMutationHandler.Snapshot).ToList();
    }
}
