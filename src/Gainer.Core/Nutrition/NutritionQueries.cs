namespace Gainer.Core.Nutrition;

public interface INutritionQueries
{
    Task<NutritionDaySnapshot?> GetDayAsync(DateOnly localDate, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<NutritionEntrySnapshot>> GetRecentEntriesAsync(
        int limit,
        CancellationToken cancellationToken = default);
}

public interface ISmartNutritionQueries
{
    Task<IReadOnlyList<ReusableMealSnapshot>> GetReusableMealsAsync(
        bool includeArchived,
        CancellationToken cancellationToken = default);

    Task<ReusableMealSnapshot?> GetReusableMealAsync(
        Guid reusableMealId,
        CancellationToken cancellationToken = default);

    Task<NutritionTargetScheduleSnapshot?> GetNutritionTargetScheduleAsync(
        CancellationToken cancellationToken = default);

    Task<NutritionTargetVersionDraft?> GetEffectiveNutritionTargetAsync(
        DateOnly localDate,
        CancellationToken cancellationToken = default);
}
