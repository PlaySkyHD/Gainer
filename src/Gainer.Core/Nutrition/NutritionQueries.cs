namespace Gainer.Core.Nutrition;

public interface INutritionQueries
{
    Task<NutritionDaySnapshot?> GetDayAsync(DateOnly localDate, CancellationToken cancellationToken = default);

    /// <summary>Logged days in the inclusive range with their entries, oldest first; days without a log are missing.</summary>
    Task<IReadOnlyList<NutritionDaySnapshot>> GetDaysAsync(
        DateOnly from,
        DateOnly through,
        CancellationToken cancellationToken = default);

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
