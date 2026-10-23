using Gainer.Core.Mutations;
using Gainer.Core.Security;

namespace Gainer.Core.Nutrition;

/// <summary>A named copy of a nutrition day's entries that can be applied to other days.</summary>
public sealed class NutritionDayTemplate : UserOwnedEntity
{
    public Guid Id { get; init; }
    public string Name { get; set; } = string.Empty;

    /// <summary>Day kind the template is meant for; used to suggest it on empty days.</summary>
    public NutritionDayKind? DayKind { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
    public ICollection<NutritionDayTemplateEntry> Entries { get; } = new List<NutritionDayTemplateEntry>();
}

/// <summary>Entry of a day template; holds the same values as a diary entry.</summary>
public sealed class NutritionDayTemplateEntry : NutritionEntryValues
{
    public Guid NutritionDayTemplateId { get; init; }
    public NutritionDayTemplate NutritionDayTemplate { get; init; } = null!;
}

public sealed record NutritionDayTemplateSnapshot(
    Guid TemplateId,
    string Name,
    NutritionDayKind? DayKind,
    IReadOnlyList<NutritionEntrySnapshot> Entries,
    NutritionTotals Totals,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.NutritionDayTemplate, TemplateId);
}

public sealed record SaveNutritionDayTemplateMutation : ITypedMutation<NutritionDayTemplateSnapshot>
{
    private SaveNutritionDayTemplateMutation(
        MutationMetadata metadata,
        Guid templateId,
        long baseVersion,
        string name,
        NutritionDayKind? dayKind,
        IReadOnlyList<NutritionEntryInput> entries)
    {
        Metadata = metadata;
        TemplateId = templateId;
        BaseVersion = baseVersion;
        Name = name;
        DayKind = dayKind;
        Entries = entries;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.NutritionDayTemplate, templateId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid TemplateId { get; }
    public long BaseVersion { get; }
    public string Name { get; }
    public NutritionDayKind? DayKind { get; }
    public IReadOnlyList<NutritionEntryInput> Entries { get; }

    public static SaveNutritionDayTemplateMutation Create(
        MutationMetadata metadata,
        Guid templateId,
        long baseVersion,
        string name,
        NutritionDayKind? dayKind,
        IEnumerable<NutritionEntryInput> entries)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(entries);
        if (templateId == Guid.Empty) throw new ArgumentException("Day template identifier cannot be empty.", nameof(templateId));
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        string normalizedName = name?.Trim() ?? string.Empty;
        if (normalizedName.Length is 0 or > NutritionLimits.MaxDayTemplateNameLength)
            errors[nameof(Name)] = $"Name must contain 1 to {NutritionLimits.MaxDayTemplateNameLength} characters.";
        if (dayKind is { } kind && !Enum.IsDefined(kind)) errors[nameof(DayKind)] = "Day kind is invalid.";
        NutritionEntryInput[] entryArray = entries.ToArray();
        if (entryArray.Length == 0) errors[nameof(Entries)] = "A day template needs at least one entry.";
        if (errors.Count > 0) throw new NutritionValidationException(errors);
        SaveNutritionDayMutation.ValidateEntries(entryArray);
        return new SaveNutritionDayTemplateMutation(metadata, templateId, baseVersion, normalizedName, dayKind, entryArray);
    }
}

public sealed record DeleteNutritionDayTemplateMutation : ITypedMutation<long>
{
    private DeleteNutritionDayTemplateMutation(MutationMetadata metadata, Guid templateId, long baseVersion)
    {
        Metadata = metadata;
        TemplateId = templateId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.NutritionDayTemplate, templateId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid TemplateId { get; }
    public long BaseVersion { get; }

    public static DeleteNutritionDayTemplateMutation Create(MutationMetadata metadata, Guid templateId, long baseVersion)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (templateId == Guid.Empty) throw new ArgumentException("Day template identifier cannot be empty.", nameof(templateId));
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new DeleteNutritionDayTemplateMutation(metadata, templateId, baseVersion);
    }
}

public interface INutritionDayTemplateMutationHandler
{
    Task<NutritionDayTemplateSnapshot> SaveAsync(SaveNutritionDayTemplateMutation mutation, CancellationToken cancellationToken = default);
    Task<long> DeleteAsync(DeleteNutritionDayTemplateMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class NutritionDayTemplateConflictException(string message) : Exception(message);
public sealed class NutritionDayTemplateNotFoundException : Exception;
