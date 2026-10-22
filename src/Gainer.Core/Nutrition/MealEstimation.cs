namespace Gainer.Core.Nutrition;

public enum MealEstimateConfidence
{
    Low = 1,
    Medium = 2,
    High = 3,
}

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
    string? SourceUrl = null)
{
    public static MealEstimateComponentDraft Create(
        string name,
        decimal amountGrams,
        decimal kilocalories,
        decimal? proteinGrams,
        decimal? carbohydrateGrams,
        decimal? fatGrams,
        MealEstimateConfidence confidence,
        IEnumerable<string> dataGaps,
        decimal? saltGrams = null,
        string? sourceUrl = null)
    {
        ArgumentNullException.ThrowIfNull(name);
        ArgumentNullException.ThrowIfNull(dataGaps);
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
        if (!Enum.IsDefined(confidence)) errors[nameof(Confidence)] = "Confidence is invalid.";
        if (normalizedGaps.Length > NutritionLimits.MaxDataGapsPerEstimateComponent ||
            normalizedGaps.Any(item => item.Length > NutritionLimits.MaxDataGapLength))
            errors[nameof(DataGaps)] = "Data gaps exceed the allowed limits.";
        if (errors.Count > 0) throw new NutritionValidationException(errors);
        return new MealEstimateComponentDraft(
            normalizedName, amountGrams, kilocalories, proteinGrams, carbohydrateGrams,
            fatGrams, confidence, normalizedGaps, saltGrams, sourceUrl);
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
