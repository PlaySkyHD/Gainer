namespace Gainer.Core.Nutrition;

/// <summary>
/// Weight of one piece (egg, slice, roll) and, when the amount was entered in pieces, the count.
/// The amount in grams stays the source of truth; with a count it must equal count × piece weight.
/// </summary>
public sealed record NutritionPortion(decimal PieceGrams, decimal? PieceCount)
{
    public const decimal MaxPieceGrams = 5_000m;
    public const decimal MaxPieceCount = 1_000m;
    private const decimal AmountTolerance = 0.01m;

    /// <summary>Returns null when neither value is set; a count without a piece weight is invalid.</summary>
    public static NutritionPortion? From(decimal? pieceGrams, decimal? pieceCount)
    {
        if (pieceGrams is null && pieceCount is null) return null;
        if (pieceGrams is null)
        {
            throw new NutritionValidationException(new Dictionary<string, string>
            {
                [nameof(PieceGrams)] = "PieceGrams is required when PieceCount is set.",
            });
        }
        return new NutritionPortion(pieceGrams.Value, pieceCount);
    }

    public decimal? AmountGrams => PieceCount is { } count
        ? decimal.Round(count * PieceGrams, 2, MidpointRounding.AwayFromZero)
        : null;

    public void Validate(decimal amountGrams, Dictionary<string, string> errors)
    {
        ArgumentNullException.ThrowIfNull(errors);
        if (PieceGrams is < NutritionLimits.MinAmountGrams or > MaxPieceGrams)
            errors[nameof(PieceGrams)] = "PieceGrams is outside the allowed range.";
        if (PieceCount is <= 0m or > MaxPieceCount)
            errors[nameof(PieceCount)] = "PieceCount is outside the allowed range.";
        if (AmountGrams is { } expected && decimal.Abs(expected - amountGrams) > AmountTolerance)
            errors["AmountGrams"] = "AmountGrams must equal PieceCount × PieceGrams.";
    }
}
