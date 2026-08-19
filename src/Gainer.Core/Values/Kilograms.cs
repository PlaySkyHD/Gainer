namespace Gainer.Core.Values;

/// <summary>Represents a non-negative weight in canonical kilograms.</summary>
public readonly record struct Kilograms
{
    private Kilograms(decimal value)
    {
        Value = value;
    }

    /// <summary>Gets the canonical decimal value.</summary>
    public decimal Value { get; }

    /// <summary>Gets whether the weight is strictly positive.</summary>
    public bool IsPositive => ValueObjectValidation.IsPositive(Value);

    /// <summary>Creates a non-negative kilogram value.</summary>
    public static Kilograms From(decimal value)
    {
        return TryCreate(value, out Kilograms kilograms)
            ? kilograms
            : throw new ArgumentOutOfRangeException(nameof(value), "Kilograms cannot be negative.");
    }

    /// <summary>Attempts to create a non-negative kilogram value.</summary>
    public static bool TryCreate(decimal value, out Kilograms kilograms)
    {
        bool isValid = ValueObjectValidation.IsNonNegative(value);
        kilograms = isValid ? new Kilograms(value) : default;
        return isValid;
    }
}
