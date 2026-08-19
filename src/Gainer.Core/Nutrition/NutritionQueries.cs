namespace Gainer.Core.Nutrition;

public interface INutritionQueries
{
    Task<NutritionDaySnapshot?> GetDayAsync(DateOnly localDate, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<NutritionEntrySnapshot>> GetRecentEntriesAsync(
        int limit,
        CancellationToken cancellationToken = default);
}
