namespace Gainer.Contracts.Training;

public sealed record ExerciseCatalogItemResponse(
    Guid Id,
    string Name,
    string? Description,
    string? TargetMuscle,
    string? MuscleGroup,
    string? Equipment,
    bool IsCustom,
    string? CatalogVersion,
    long Version,
    string ExerciseType,
    string? Notes,
    decimal? BodyweightFactor,
    decimal? WeightFactor,
    IReadOnlyList<Guid> CategoryIds);

public sealed record ExerciseCategoryResponse(
    Guid Id,
    string Name,
    bool IsBase);

public sealed record ExerciseCatalogResponse(
    IReadOnlyList<ExerciseCatalogItemResponse> Items,
    int Offset,
    int Limit,
    int Total,
    IReadOnlyList<ExerciseCategoryResponse> Categories);
