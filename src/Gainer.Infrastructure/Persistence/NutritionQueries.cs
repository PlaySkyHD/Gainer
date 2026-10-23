using Gainer.Core.Nutrition;
using Microsoft.EntityFrameworkCore;

namespace Gainer.Infrastructure.Persistence;

public sealed class NutritionQueries(AppDbContext context) : INutritionQueries
{
    public async Task<NutritionDaySnapshot?> GetDayAsync(
        DateOnly localDate,
        CancellationToken cancellationToken = default)
    {
        NutritionDay? day = await context.NutritionDays
            .AsNoTracking()
            .Include(item => item.Entries)
            .SingleOrDefaultAsync(item => item.LocalDate == localDate, cancellationToken);
        return day is null ? null : NutritionSnapshots.Day(day);
    }

    public async Task<IReadOnlyList<NutritionEntrySnapshot>> GetRecentEntriesAsync(
        int limit,
        CancellationToken cancellationToken = default)
    {
        if (limit is < 1 or > 50) throw new ArgumentOutOfRangeException(nameof(limit));
        NutritionEntry[] entries = await context.NutritionEntries
            .AsNoTracking()
            .OrderByDescending(item => item.NutritionDay.LocalDate)
            .ThenByDescending(item => item.NutritionDay.UpdatedAtUtc)
            .ThenByDescending(item => item.Id)
            .Take(limit * 4)
            .ToArrayAsync(cancellationToken);
        return entries
            .DistinctBy(item => new
            {
                item.ProductName,
                item.Brand,
                item.Barcode,
                item.KilocaloriesPerBasis,
                item.ProteinGramsPerBasis,
                item.CarbohydrateGramsPerBasis,
                item.FatGramsPerBasis,
                item.SaltGramsPerBasis,
                item.FiberGramsPerBasis,
                item.PieceGrams,
            })
            .Take(limit)
            .Select(NutritionSnapshots.Entry)
            .ToArray();
    }
}
