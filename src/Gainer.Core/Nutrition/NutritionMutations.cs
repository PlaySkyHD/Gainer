using Gainer.Core.Mutations;

namespace Gainer.Core.Nutrition;

public sealed record NutritionSourceSnapshot(
    string? Provider,
    string? Barcode,
    DateTime? RetrievedAtUtc,
    decimal BasisGrams);

public sealed record NutritionEntryInput
{
    private NutritionEntryInput(
        Guid entryId,
        MealType meal,
        int position,
        string productName,
        string? brand,
        decimal amountGrams,
        NutritionPer100Grams per100Grams,
        NutritionSourceSnapshot? source)
    {
        EntryId = entryId;
        Meal = meal;
        Position = position;
        ProductName = productName.Trim();
        Brand = string.IsNullOrWhiteSpace(brand) ? null : brand.Trim();
        AmountGrams = amountGrams;
        Per100Grams = per100Grams;
        Source = source;
    }

    public Guid EntryId { get; }
    public MealType Meal { get; }
    public int Position { get; }
    public string ProductName { get; }
    public string? Brand { get; }
    public decimal AmountGrams { get; }
    public NutritionPer100Grams Per100Grams { get; }
    public NutritionSourceSnapshot? Source { get; }

    public static NutritionEntryInput Create(
        Guid entryId,
        MealType meal,
        int position,
        string productName,
        decimal amountGrams,
        NutritionPer100Grams per100Grams,
        string? brand = null,
        NutritionSourceSnapshot? source = null)
    {
        ArgumentNullException.ThrowIfNull(productName);
        ArgumentNullException.ThrowIfNull(per100Grams);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (entryId == Guid.Empty) errors[nameof(EntryId)] = "EntryId cannot be empty.";
        if (!Enum.IsDefined(meal)) errors[nameof(Meal)] = "Meal is invalid.";
        if (position < 0) errors[nameof(Position)] = "Position cannot be negative.";
        if (string.IsNullOrWhiteSpace(productName)) errors[nameof(ProductName)] = "ProductName is required.";
        if (productName.Length > 200) errors[nameof(ProductName)] = "ProductName is too long.";
        if (brand?.Length > 160) errors[nameof(Brand)] = "Brand is too long.";
        try
        {
            _ = NutritionCalculator.Calculate(amountGrams, per100Grams);
        }
        catch (NutritionValidationException exception)
        {
            foreach ((string field, string error) in exception.Errors) errors[field] = error;
        }
        if (errors.Count > 0) throw new NutritionValidationException(errors);
        return new NutritionEntryInput(entryId, meal, position, productName, brand, amountGrams, per100Grams, source);
    }
}

public sealed record SaveNutritionDayMutation : ITypedMutation<NutritionDaySnapshot>
{
    private SaveNutritionDayMutation(
        MutationMetadata metadata,
        Guid nutritionDayId,
        DateOnly localDate,
        long baseVersion,
        IReadOnlyList<NutritionEntryInput> entries)
    {
        Metadata = metadata;
        NutritionDayId = nutritionDayId;
        LocalDate = localDate;
        BaseVersion = baseVersion;
        Entries = entries;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.NutritionDay, nutritionDayId),
            baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid NutritionDayId { get; }
    public DateOnly LocalDate { get; }
    public long BaseVersion { get; }
    public IReadOnlyList<NutritionEntryInput> Entries { get; }

    public static SaveNutritionDayMutation Create(
        MutationMetadata metadata,
        Guid nutritionDayId,
        DateOnly localDate,
        long baseVersion,
        IEnumerable<NutritionEntryInput> entries)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(entries);
        if (nutritionDayId == Guid.Empty) throw new ArgumentException("Nutrition day identifier cannot be empty.", nameof(nutritionDayId));
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        NutritionEntryInput[] entryArray = entries.ToArray();
        ValidateEntries(entryArray);
        return new SaveNutritionDayMutation(metadata, nutritionDayId, localDate, baseVersion, entryArray);
    }

    private static void ValidateEntries(NutritionEntryInput[] entries)
    {
        if (entries.Length > 200) throw new NutritionValidationException(new Dictionary<string, string> { [nameof(Entries)] = "A day can contain at most 200 entries." });
        if (entries.Select(item => item.EntryId).Distinct().Count() != entries.Length)
            throw new NutritionValidationException(new Dictionary<string, string> { [nameof(Entries)] = "Entry identifiers must be unique." });
        if (entries.GroupBy(item => item.Meal).Any(group => group.Select(item => item.Position).Distinct().Count() != group.Count()))
            throw new NutritionValidationException(new Dictionary<string, string> { [nameof(Entries)] = "Positions must be unique within a meal." });
    }
}

public sealed record NutritionEntrySnapshot(
    Guid EntryId,
    MealType Meal,
    int Position,
    string ProductName,
    string? Brand,
    decimal AmountGrams,
    NutritionTotals Totals,
    NutritionPer100Grams Per100Grams,
    NutritionSourceSnapshot? Source);

public sealed record NutritionDaySnapshot(
    Guid NutritionDayId,
    DateOnly LocalDate,
    IReadOnlyList<NutritionEntrySnapshot> Entries,
    NutritionTotals Totals,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.NutritionDay, NutritionDayId);
}

public sealed record DeleteNutritionDayMutation : ITypedMutation<long>
{
    private DeleteNutritionDayMutation(MutationMetadata metadata, Guid nutritionDayId, long baseVersion)
    {
        Metadata = metadata;
        NutritionDayId = nutritionDayId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.NutritionDay, nutritionDayId),
            baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid NutritionDayId { get; }
    public long BaseVersion { get; }

    public static DeleteNutritionDayMutation Create(MutationMetadata metadata, Guid nutritionDayId, long baseVersion)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (nutritionDayId == Guid.Empty) throw new ArgumentException("Nutrition day identifier cannot be empty.", nameof(nutritionDayId));
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new DeleteNutritionDayMutation(metadata, nutritionDayId, baseVersion);
    }
}

public interface INutritionDayMutationHandler
{
    Task<NutritionDaySnapshot> SaveAsync(SaveNutritionDayMutation mutation, CancellationToken cancellationToken = default);
    Task<long> DeleteAsync(DeleteNutritionDayMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class NutritionDayConflictException(string message) : Exception(message);
public sealed class NutritionDayNotFoundException : Exception;
