namespace Gainer.Core.Nutrition;

public sealed record NutritionPer100Grams(
    decimal Kilocalories,
    decimal? ProteinGrams,
    decimal? CarbohydrateGrams,
    decimal? FatGrams);

public sealed record NutritionTotals(
    decimal Kilocalories,
    decimal? ProteinGrams,
    decimal? CarbohydrateGrams,
    decimal? FatGrams)
{
    public static NutritionTotals Empty { get; } = new(0m, 0m, 0m, 0m);
}

public static class NutritionCalculator
{
    public static NutritionTotals Calculate(decimal amountGrams, NutritionPer100Grams values)
    {
        ArgumentNullException.ThrowIfNull(values);
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        ValidatePositive(amountGrams, nameof(amountGrams), "AmountGrams", errors);
        ValidatePositive(values.Kilocalories, nameof(values.Kilocalories), "KilocaloriesPer100Grams", errors);
        ValidateOptional(values.ProteinGrams, "ProteinGramsPer100Grams", errors);
        ValidateOptional(values.CarbohydrateGrams, "CarbohydrateGramsPer100Grams", errors);
        ValidateOptional(values.FatGrams, "FatGramsPer100Grams", errors);
        if (errors.Count > 0)
        {
            throw new NutritionValidationException(errors);
        }

        decimal factor = amountGrams / 100m;
        return new NutritionTotals(
            Round(values.Kilocalories * factor),
            Scale(values.ProteinGrams, factor),
            Scale(values.CarbohydrateGrams, factor),
            Scale(values.FatGrams, factor));
    }

    public static NutritionTotals Sum(IEnumerable<NutritionTotals> values)
    {
        ArgumentNullException.ThrowIfNull(values);
        NutritionTotals[] items = values.ToArray();
        return new NutritionTotals(
            Round(items.Sum(item => item.Kilocalories)),
            SumOptional(items.Select(item => item.ProteinGrams)),
            SumOptional(items.Select(item => item.CarbohydrateGrams)),
            SumOptional(items.Select(item => item.FatGrams)));
    }

    private static decimal? Scale(decimal? value, decimal factor) =>
        value is null ? null : Round(value.Value * factor);

    private static decimal? SumOptional(IEnumerable<decimal?> values)
    {
        decimal?[] items = values.ToArray();
        return items.Any(item => item.HasValue)
            ? Round(items.Where(item => item.HasValue).Sum(item => item!.Value))
            : null;
    }

    private static decimal Round(decimal value) =>
        decimal.Round(value, 2, MidpointRounding.AwayFromZero);

    private static void ValidatePositive(
        decimal value,
        string sourceName,
        string field,
        IDictionary<string, string> errors)
    {
        _ = sourceName;
        if (value <= 0m)
        {
            errors[field] = $"{field} must be positive.";
        }
    }

    private static void ValidateOptional(decimal? value, string field, IDictionary<string, string> errors)
    {
        if (value is < 0m)
        {
            errors[field] = $"{field} cannot be negative.";
        }
    }
}

public sealed class NutritionValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The nutrition data is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}
