namespace Gainer.Core.Training;

public sealed record ExerciseCatalogFilter(
    string? Search = null,
    string? TargetMuscle = null,
    string? MuscleGroup = null,
    string? Equipment = null,
    int Offset = 0,
    int Limit = 50);

public sealed record ExerciseCatalogItem(
    Guid Id,
    string Name,
    string? Description,
    string? TargetMuscle,
    string? MuscleGroup,
    string? Equipment,
    bool IsCustom,
    string? CatalogVersion,
    long Version);

public sealed record ExerciseCatalogPage(
    IReadOnlyList<ExerciseCatalogItem> Items,
    int Offset,
    int Limit,
    int Total);

public interface IExerciseCatalogQueries
{
    Task<ExerciseCatalogPage> SearchAsync(
        ExerciseCatalogFilter filter,
        CancellationToken cancellationToken = default);
}
