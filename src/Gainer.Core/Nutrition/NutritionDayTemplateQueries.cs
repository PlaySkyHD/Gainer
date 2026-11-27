namespace Gainer.Core.Nutrition;

public interface INutritionDayTemplateQueries
{
    /// <summary>The user's nutrition day templates with their entries, by name.</summary>
    Task<IReadOnlyList<NutritionDayTemplateSnapshot>> ListAsync(CancellationToken cancellationToken = default);
}
