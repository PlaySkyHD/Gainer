using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

public sealed record WorkoutTemplateItemValues(
    Guid ItemId,
    Guid ExerciseId,
    int PlannedSets,
    int MinimumRepetitions,
    int MaximumRepetitions,
    decimal? TargetRir = null,
    int? RestSeconds = null,
    string? Notes = null);

public sealed record SaveWorkoutTemplateMutation : ITypedMutation<WorkoutTemplateSnapshot>
{
    private SaveWorkoutTemplateMutation(
        MutationMetadata metadata,
        Guid templateId,
        long baseVersion,
        string name,
        IReadOnlyList<WorkoutTemplateItemValues> items)
    {
        Metadata = metadata;
        TemplateId = templateId;
        BaseVersion = baseVersion;
        Name = name;
        Items = items;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.WorkoutTemplate, templateId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid TemplateId { get; }
    public long BaseVersion { get; }
    public string Name { get; }
    public IReadOnlyList<WorkoutTemplateItemValues> Items { get; }

    public static SaveWorkoutTemplateMutation Create(
        MutationMetadata metadata,
        Guid templateId,
        long baseVersion,
        string name,
        IReadOnlyList<WorkoutTemplateItemValues> items)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(name);
        ArgumentNullException.ThrowIfNull(items);
        if (templateId == Guid.Empty)
        {
            throw new ArgumentException("The template identifier cannot be empty.", nameof(templateId));
        }
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        return new(metadata, templateId, baseVersion, name, items);
    }
}

public sealed record ArchiveWorkoutTemplateMutation : ITypedMutation<WorkoutTemplateSnapshot>
{
    private ArchiveWorkoutTemplateMutation(MutationMetadata metadata, Guid templateId, long baseVersion)
    {
        Metadata = metadata;
        TemplateId = templateId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.WorkoutTemplate, templateId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid TemplateId { get; }
    public long BaseVersion { get; }

    public static ArchiveWorkoutTemplateMutation Create(
        MutationMetadata metadata,
        Guid templateId,
        long baseVersion)
    {
        if (templateId == Guid.Empty)
        {
            throw new ArgumentException("The template identifier cannot be empty.", nameof(templateId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, templateId, baseVersion);
    }
}

public sealed record WorkoutTemplateSnapshot(
    Guid TemplateId,
    string Name,
    bool IsArchived,
    IReadOnlyList<WorkoutTemplateItemValues> Items,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.WorkoutTemplate, TemplateId);
}

public interface IWorkoutTemplateMutationHandler
{
    Task<WorkoutTemplateSnapshot> SaveAsync(SaveWorkoutTemplateMutation mutation, CancellationToken cancellationToken = default);
    Task<WorkoutTemplateSnapshot> ArchiveAsync(ArchiveWorkoutTemplateMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class WorkoutTemplateValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The workout template is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class WorkoutTemplateConflictException(string message) : Exception(message);

public sealed class WorkoutTemplateNotFoundException : Exception;
