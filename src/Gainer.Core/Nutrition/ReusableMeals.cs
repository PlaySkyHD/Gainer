using Gainer.Core.Security;
using Gainer.Core.Mutations;

namespace Gainer.Core.Nutrition;

public enum ReusableMealStatus
{
    Active = 1,
    Archived = 2,
}

public sealed class ReusableMeal : UserOwnedEntity
{
    public Guid Id { get; init; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public decimal StandardPortion { get; set; }
    public ReusableMealStatus Status { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
    public ICollection<ReusableMealComponent> Components { get; } = new List<ReusableMealComponent>();
}

public sealed class ReusableMealComponent : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid ReusableMealId { get; init; }
    public ReusableMeal ReusableMeal { get; init; } = null!;
    public int Position { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Brand { get; set; }
    public decimal AmountGrams { get; set; }
    public decimal? PieceGrams { get; set; }
    public decimal? PieceCount { get; set; }
    public decimal Kilocalories { get; set; }
    public decimal? ProteinGrams { get; set; }
    public decimal? CarbohydrateGrams { get; set; }
    public decimal? FatGrams { get; set; }
    public decimal? SaltGrams { get; set; }
    public decimal? FiberGrams { get; set; }
    public decimal KilocaloriesPer100Grams { get; set; }
    public decimal? ProteinGramsPer100Grams { get; set; }
    public decimal? CarbohydrateGramsPer100Grams { get; set; }
    public decimal? FatGramsPer100Grams { get; set; }
    public decimal? SaltGramsPer100Grams { get; set; }
    public decimal? FiberGramsPer100Grams { get; set; }
    public decimal BasisGrams { get; set; } = 100m;
    public string? Provider { get; set; }
    public string? Barcode { get; set; }
    public DateTime? RetrievedAtUtc { get; set; }
}

public sealed record ReusableMealComponentDraft(
    Guid ComponentId,
    int Position,
    string Name,
    string? Brand,
    decimal AmountGrams,
    NutritionPer100Grams Per100Grams,
    NutritionTotals Totals,
    NutritionSourceSnapshot? Source,
    NutritionPortion? Portion = null)
{
    public static ReusableMealComponentDraft Create(
        Guid componentId,
        int position,
        string? name,
        decimal amountGrams,
        NutritionPer100Grams per100Grams,
        string? brand = null,
        NutritionSourceSnapshot? source = null,
        NutritionPortion? portion = null)
    {
        ArgumentNullException.ThrowIfNull(per100Grams);
        // A missing name in a sync payload is a validation error, not a server fault.
        name ??= string.Empty;
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (componentId == Guid.Empty) errors[nameof(ComponentId)] = "ComponentId cannot be empty.";
        if (position < 0) errors[nameof(Position)] = "Position cannot be negative.";
        string normalizedName = name.Trim();
        if (normalizedName.Length is 0 or > NutritionLimits.MaxComponentNameLength)
            errors[nameof(Name)] = $"Name must contain 1 to {NutritionLimits.MaxComponentNameLength} characters.";
        string? normalizedBrand = string.IsNullOrWhiteSpace(brand) ? null : brand.Trim();
        if (normalizedBrand?.Length > 160) errors[nameof(Brand)] = "Brand is too long.";
        if (amountGrams is < NutritionLimits.MinAmountGrams or > NutritionLimits.MaxAmountGrams)
            errors[nameof(AmountGrams)] = $"AmountGrams must be between {NutritionLimits.MinAmountGrams} and {NutritionLimits.MaxAmountGrams}.";
        NutritionLimits.ValidatePer100Grams(per100Grams, errors);
        portion?.Validate(amountGrams, errors);

        NutritionTotals? totals = null;
        if (errors.Count == 0)
        {
            try { totals = NutritionCalculator.Calculate(amountGrams, per100Grams); }
            catch (NutritionValidationException exception)
            {
                foreach ((string key, string value) in exception.Errors) errors[key] = value;
            }
        }

        if (errors.Count > 0) throw new NutritionValidationException(errors);
        return new ReusableMealComponentDraft(
            componentId, position, normalizedName, normalizedBrand, amountGrams,
            per100Grams, totals!, source, portion);
    }
}

public sealed record ReusableMealDraft(
    string Name,
    string? Description,
    decimal StandardPortion,
    IReadOnlyList<ReusableMealComponentDraft> Components)
{
    public static ReusableMealDraft Create(
        string? name,
        string? description,
        decimal standardPortion,
        IEnumerable<ReusableMealComponentDraft> components)
    {
        ArgumentNullException.ThrowIfNull(components);
        // A missing name in a sync payload is a validation error, not a server fault.
        string normalizedName = name?.Trim() ?? string.Empty;
        string? normalizedDescription = string.IsNullOrWhiteSpace(description) ? null : description.Trim();
        ReusableMealComponentDraft[] ordered = components.OrderBy(item => item.Position).ToArray();
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (normalizedName.Length is 0 or > NutritionLimits.MaxReusableMealNameLength)
            errors[nameof(Name)] = $"Name must contain 1 to {NutritionLimits.MaxReusableMealNameLength} characters.";
        if (normalizedDescription?.Length > NutritionLimits.MaxReusableMealDescriptionLength)
            errors[nameof(Description)] = "Description is too long.";
        if (standardPortion is < NutritionLimits.MinPortionFactor or > NutritionLimits.MaxPortionFactor)
            errors[nameof(StandardPortion)] = "StandardPortion is outside the allowed range.";
        if (ordered.Length is 0 or > NutritionLimits.MaxReusableMealComponents)
            errors[nameof(Components)] = $"A reusable meal must contain 1 to {NutritionLimits.MaxReusableMealComponents} components.";
        else if (ordered.Select(item => item.ComponentId).Distinct().Count() != ordered.Length ||
                 ordered.Select(item => item.Position).Distinct().Count() != ordered.Length)
            errors[nameof(Components)] = "Component identifiers and positions must be unique.";
        if (errors.Count > 0) throw new NutritionValidationException(errors);
        return new ReusableMealDraft(normalizedName, normalizedDescription, standardPortion, ordered);
    }
}

public sealed record ReusableMealSnapshot(
    Guid ReusableMealId,
    string Name,
    string? Description,
    decimal StandardPortion,
    ReusableMealStatus Status,
    IReadOnlyList<ReusableMealComponentDraft> Components,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.ReusableMeal, ReusableMealId);
}

public sealed record SaveReusableMealMutation : ITypedMutation
{
    private SaveReusableMealMutation(
        MutationMetadata metadata,
        Guid reusableMealId,
        long baseVersion,
        ReusableMealDraft values)
    {
        Metadata = metadata;
        ReusableMealId = reusableMealId;
        BaseVersion = baseVersion;
        Values = values;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.ReusableMeal, reusableMealId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid ReusableMealId { get; }
    public long BaseVersion { get; }
    public ReusableMealDraft Values { get; }

    public static SaveReusableMealMutation Create(
        MutationMetadata metadata,
        Guid reusableMealId,
        long baseVersion,
        ReusableMealDraft values)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(values);
        if (reusableMealId == Guid.Empty) throw new ArgumentException("Reusable meal identifier cannot be empty.", nameof(reusableMealId));
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        return new SaveReusableMealMutation(metadata, reusableMealId, baseVersion, values);
    }
}

public sealed record ArchiveReusableMealMutation : ITypedMutation
{
    private ArchiveReusableMealMutation(MutationMetadata metadata, Guid reusableMealId, long baseVersion)
    {
        Metadata = metadata;
        ReusableMealId = reusableMealId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.ReusableMeal, reusableMealId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid ReusableMealId { get; }
    public long BaseVersion { get; }

    public static ArchiveReusableMealMutation Create(MutationMetadata metadata, Guid reusableMealId, long baseVersion)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (reusableMealId == Guid.Empty) throw new ArgumentException("Reusable meal identifier cannot be empty.", nameof(reusableMealId));
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new ArchiveReusableMealMutation(metadata, reusableMealId, baseVersion);
    }
}

public interface IReusableMealMutationHandler
{
    Task<ReusableMealSnapshot> SaveAsync(SaveReusableMealMutation mutation, CancellationToken cancellationToken = default);
    Task<ReusableMealSnapshot> ArchiveAsync(ArchiveReusableMealMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class ReusableMealConflictException(string message) : Exception(message);
public sealed class ReusableMealNotFoundException : Exception;
