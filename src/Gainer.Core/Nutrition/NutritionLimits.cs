namespace Gainer.Core.Nutrition;

public static class NutritionLimits
{
    public const int MaxReusableMealNameLength = 120;
    public const int MaxReusableMealDescriptionLength = 500;
    public const int MaxComponentNameLength = 200;
    public const int MaxReusableMealComponents = 50;
    public const int MaxTargetVersions = 100;
    public const int MaxDayTemplates = 50;
    public const int MaxDayTemplateNameLength = 80;
    public const int MaxTargetPhaseNameLength = 80;
    public const int MaxEstimateComponents = 20;
    public const int MaxDataGapsPerEstimateComponent = 10;
    public const int MaxDataGapLength = 240;
    public const decimal MinAmountGrams = 0.01m;
    public const decimal MaxAmountGrams = 100_000m;
    public const decimal MinPortionFactor = 0.01m;
    public const decimal MaxPortionFactor = 100m;
    public const decimal MaxKilocaloriesPer100Grams = 10_000m;
    /// <summary>Keeps the energy of one diary or template entry inside its numeric(9,2) column.</summary>
    public const decimal MaxEntryKilocalories = 1_000_000m;
    /// <summary>Reference amount of a product source; keeps the per-basis values inside their columns.</summary>
    public const decimal MaxSourceBasisGrams = 10_000m;
    public const decimal MaxMacroGramsPer100Grams = 1_000m;
    public const decimal MaxDailyKilocalories = 20_000m;
    public const decimal MaxDailyMacroGrams = 2_000m;
    public const decimal MaxSaltGramsPer100Grams = 100m;
    public const decimal MaxDailySaltTargetGrams = 100m;
    public const decimal DefaultDailySaltTargetGrams = 6m;
    public const decimal MaxFiberGramsPer100Grams = 100m;
    public const decimal MaxDailyFiberTargetGrams = 100m;
    public const decimal DefaultDailyFiberTargetGrams = 30m;
    public const decimal MacroEnergyMismatchThreshold = 0.10m;
    public const decimal MacroDistributionTotalPercent = 100m;

    /// <summary>
    /// Range check of the per-100-gram values shared by diary entries, template entries and meal components. It keeps
    /// every stored value inside its column range, so an implausible value is a validation error, not a database error.
    /// </summary>
    internal static void ValidatePer100Grams(NutritionPer100Grams values, Dictionary<string, string> errors)
    {
        ArgumentNullException.ThrowIfNull(values);
        ArgumentNullException.ThrowIfNull(errors);
        if (values.Kilocalories is < 0m or > MaxKilocaloriesPer100Grams)
            errors["KilocaloriesPer100Grams"] = "KilocaloriesPer100Grams is outside the allowed range.";
        ValidateOptional(values.ProteinGrams, "ProteinGramsPer100Grams", MaxMacroGramsPer100Grams, errors);
        ValidateOptional(values.CarbohydrateGrams, "CarbohydrateGramsPer100Grams", MaxMacroGramsPer100Grams, errors);
        ValidateOptional(values.FatGrams, "FatGramsPer100Grams", MaxMacroGramsPer100Grams, errors);
        ValidateOptional(values.SaltGrams, "SaltGramsPer100Grams", MaxSaltGramsPer100Grams, errors);
        ValidateOptional(values.FiberGrams, "FiberGramsPer100Grams", MaxFiberGramsPer100Grams, errors);
    }

    private static void ValidateOptional(decimal? value, string field, decimal maximum, Dictionary<string, string> errors)
    {
        if (value < 0m || value > maximum)
            errors[field] = $"{field} is outside the allowed range.";
    }
}
