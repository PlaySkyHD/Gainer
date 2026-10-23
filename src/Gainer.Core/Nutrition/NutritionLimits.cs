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
    public const decimal MaxMacroGramsPer100Grams = 1_000m;
    public const decimal MaxDailyKilocalories = 20_000m;
    public const decimal MaxDailyMacroGrams = 2_000m;
    public const decimal MaxSaltGramsPer100Grams = 100m;
    public const decimal MaxDailySaltTargetGrams = 100m;
    public const decimal DefaultDailySaltTargetGrams = 6m;
    public const decimal MacroEnergyMismatchThreshold = 0.10m;
    public const decimal MacroDistributionTotalPercent = 100m;
}
