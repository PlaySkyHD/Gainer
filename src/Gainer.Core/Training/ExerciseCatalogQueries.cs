namespace Gainer.Core.Training;

/// <summary>
/// Catalog search. <see cref="OnlyWithoutMuscles"/> keeps only the user's own exercises without primary and
/// secondary muscles.
/// </summary>
public sealed record ExerciseCatalogFilter(
    string? Search = null,
    string? TargetMuscle = null,
    string? MuscleGroup = null,
    string? Equipment = null,
    int Offset = 0,
    int Limit = 50,
    Guid? CategoryId = null,
    bool IncludeArchived = false,
    bool OnlyWithoutMuscles = false);

public sealed record ExerciseCatalogItem(
    Guid Id,
    string Name,
    string? Description,
    string? TargetMuscle,
    string? MuscleGroup,
    string? Equipment,
    bool IsCustom,
    string? CatalogVersion,
    long Version,
    ExerciseType ExerciseType,
    string? Notes,
    decimal? BodyweightFactor,
    decimal? WeightFactor,
    IReadOnlyList<Guid> CategoryIds,
    IReadOnlyList<string> PrimaryMuscles,
    IReadOnlyList<string> SecondaryMuscles);

public sealed record ExerciseCategoryItem(
    Guid Id,
    string Name,
    bool IsBase);

public sealed record ExerciseCatalogPage(
    IReadOnlyList<ExerciseCatalogItem> Items,
    int Offset,
    int Limit,
    int Total,
    IReadOnlyList<ExerciseCategoryItem> Categories);

public interface IExerciseCatalogQueries
{
    Task<ExerciseCatalogPage> SearchAsync(
        ExerciseCatalogFilter filter,
        CancellationToken cancellationToken = default);
}
