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
    long Version);

public sealed record ExerciseCatalogResponse(
    IReadOnlyList<ExerciseCatalogItemResponse> Items,
    int Offset,
    int Limit,
    int Total);
