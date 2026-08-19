namespace Gainer.Core.Values;

/// <summary>Represents a non-negative quantity in canonical grams.</summary>
public readonly record struct Grams
{
    private Grams(decimal value)
    {
        Value = value;
    }

    /// <summary>Gets the canonical decimal value.</summary>
    public decimal Value { get; }

    /// <summary>Creates a non-negative gram value.</summary>
    public static Grams From(decimal value)
    {
        return TryCreate(value, out Grams grams)
            ? grams
            : throw new ArgumentOutOfRangeException(nameof(value), "Grams cannot be negative.");
    }

    /// <summary>Attempts to create a non-negative gram value.</summary>
    public static bool TryCreate(decimal value, out Grams grams)
    {
        bool isValid = ValueObjectValidation.IsNonNegative(value);
        grams = isValid ? new Grams(value) : default;
        return isValid;
    }
}
