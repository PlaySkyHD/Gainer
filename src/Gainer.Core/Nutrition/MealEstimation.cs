namespace Gainer.Core.Nutrition;

public enum MealEstimateConfidence
{
    Low = 1,
    Medium = 2,
    High = 3,
}

/// <summary>The nutrient values of one estimated component; macros not stated stay null.</summary>
public sealed record MealEstimateNutrients(
    decimal Kilocalories,
    decimal? ProteinGrams = null,
    decimal? CarbohydrateGrams = null,
    decimal? FatGrams = null,
    decimal? SaltGrams = null,
    decimal? FiberGrams = null);

/// <summary>The counted pieces of an estimated component, kept only when plausible for the amount.</summary>
public sealed record MealEstimatePieces(decimal? Count, decimal? Grams);

public sealed record MealEstimateComponentDraft(
    string Name,
    decimal AmountGrams,
    decimal Kilocalories,
    decimal? ProteinGrams,
    decimal? CarbohydrateGrams,
    decimal? FatGrams,
    MealEstimateConfidence Confidence,
    IReadOnlyList<string> DataGaps,
    decimal? SaltGrams = null,
    string? SourceUrl = null,
    decimal? PieceCount = null,
    decimal? PieceGrams = null,
    decimal? FiberGrams = null)
{
    public static MealEstimateComponentDraft Create(
        string name,
        decimal amountGrams,
        MealEstimateNutrients nutrients,
        MealEstimateConfidence confidence,
        IEnumerable<string> dataGaps,
        string? sourceUrl = null,
        MealEstimatePieces? pieces = null)
    {
        ArgumentNullException.ThrowIfNull(name);
        ArgumentNullException.ThrowIfNull(nutrients);
        ArgumentNullException.ThrowIfNull(dataGaps);
        (decimal kilocalories, decimal? proteinGrams, decimal? carbohydrateGrams, decimal? fatGrams, decimal? saltGrams, decimal? fiberGrams) =
            (nutrients.Kilocalories, nutrients.ProteinGrams, nutrients.CarbohydrateGrams, nutrients.FatGrams, nutrients.SaltGrams, nutrients.FiberGrams);
        string normalizedName = name.Trim();
        string[] normalizedGaps = dataGaps
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .Select(item => item.Trim())
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (normalizedName.Length is 0 or > NutritionLimits.MaxComponentNameLength)
            errors[nameof(Name)] = "Name is required and must fit the component name limit.";
        if (amountGrams is < NutritionLimits.MinAmountGrams or > NutritionLimits.MaxAmountGrams)
            errors[nameof(AmountGrams)] = "AmountGrams is outside the allowed range.";
        // 0 kcal is valid for a stated amount of added salt.
        if (kilocalories is < 0m or > NutritionLimits.MaxDailyKilocalories)
            errors[nameof(Kilocalories)] = "Kilocalories is outside the allowed range.";
        ValidateOptional(proteinGrams, nameof(ProteinGrams), errors);
        ValidateOptional(carbohydrateGrams, nameof(CarbohydrateGrams), errors);
        ValidateOptional(fatGrams, nameof(FatGrams), errors);
        if (saltGrams is < 0m or > NutritionLimits.MaxSaltGramsPer100Grams)
            errors[nameof(SaltGrams)] = "SaltGrams is outside the allowed range.";
        ValidateOptional(fiberGrams, nameof(FiberGrams), errors);
        if (!Enum.IsDefined(confidence)) errors[nameof(Confidence)] = "Confidence is invalid.";
        if (normalizedGaps.Length > NutritionLimits.MaxDataGapsPerEstimateComponent ||
            normalizedGaps.Any(item => item.Length > NutritionLimits.MaxDataGapLength))
            errors[nameof(DataGaps)] = "Data gaps exceed the allowed limits.";
        if (errors.Count > 0) throw new NutritionValidationException(errors);
        (decimal? count, decimal? grams) = ConsistentPortion(amountGrams, pieces?.Count, pieces?.Grams);
        return new MealEstimateComponentDraft(
            normalizedName, amountGrams, kilocalories, proteinGrams, carbohydrateGrams,
            fatGrams, confidence, normalizedGaps, saltGrams, sourceUrl, count, grams, fiberGrams);
    }

    /// <summary>
    /// Keeps the counted pieces only when count and piece weight are plausible and match the amount;
    /// otherwise the suggestion stays in grams instead of failing.
    /// </summary>
    private static (decimal? Count, decimal? Grams) ConsistentPortion(decimal amountGrams, decimal? count, decimal? grams)
    {
        if (count is not { } pieces || grams is not { } pieceGrams) return (null, null);
        var portion = new NutritionPortion(pieceGrams, pieces);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        portion.Validate(amountGrams, errors);
        return errors.Count == 0 ? (pieces, pieceGrams) : (null, null);
    }

    private static void ValidateOptional(decimal? value, string field, Dictionary<string, string> errors)
    {
        if (value is < 0m or > NutritionLimits.MaxDailyMacroGrams)
            errors[field] = $"{field} is outside the allowed range.";
    }
}

public sealed record MealEstimateDraft(
    IReadOnlyList<MealEstimateComponentDraft> Components,
    string Provider,
    string SchemaVersion,
    DateTime EstimatedAtUtc)
{
    public static MealEstimateDraft Create(
        IEnumerable<MealEstimateComponentDraft> components,
        string provider,
        string schemaVersion,
        DateTime estimatedAtUtc)
    {
        ArgumentNullException.ThrowIfNull(components);
        ArgumentNullException.ThrowIfNull(provider);
        ArgumentNullException.ThrowIfNull(schemaVersion);
        MealEstimateComponentDraft[] items = components.ToArray();
        string normalizedProvider = provider.Trim();
        string normalizedSchemaVersion = schemaVersion.Trim();
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (items.Length is 0 || items.Length > NutritionLimits.MaxEstimateComponents)
            errors[nameof(Components)] = $"An estimate must contain 1 to {NutritionLimits.MaxEstimateComponents} components.";
        if (normalizedProvider.Length is 0 or > 80) errors[nameof(Provider)] = "Provider is invalid.";
        if (normalizedSchemaVersion.Length is 0 or > 80) errors[nameof(SchemaVersion)] = "SchemaVersion is invalid.";
        if (estimatedAtUtc.Kind != DateTimeKind.Utc) errors[nameof(EstimatedAtUtc)] = "EstimatedAtUtc must be UTC.";
        if (errors.Count > 0) throw new NutritionValidationException(errors);
        return new MealEstimateDraft(items, normalizedProvider, normalizedSchemaVersion, estimatedAtUtc);
    }
}
