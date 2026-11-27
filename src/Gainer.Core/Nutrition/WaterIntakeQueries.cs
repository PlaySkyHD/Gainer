namespace Gainer.Core.Nutrition;

public interface IWaterIntakeQueries
{
    /// <summary>Stored water days in the inclusive range, oldest first; days without a stored value are missing.</summary>
    Task<IReadOnlyList<WaterIntakeDaySnapshot>> GetDaysAsync(
        DateOnly from,
        DateOnly through,
        CancellationToken cancellationToken = default);
}
