namespace Gainer.Core.Values;

/// <summary>Represents a non-negative energy quantity in kilocalories.</summary>
public readonly record struct Kilocalories
{
    private Kilocalories(decimal value)
    {
        Value = value;
    }

    /// <summary>Gets the canonical decimal value.</summary>
    public decimal Value { get; }

    /// <summary>Creates a non-negative kilocalorie value.</summary>
    public static Kilocalories From(decimal value)
    {
        return TryCreate(value, out Kilocalories kilocalories)
            ? kilocalories
            : throw new ArgumentOutOfRangeException(nameof(value), "Kilocalories cannot be negative.");
    }

    /// <summary>Attempts to create a non-negative kilocalorie value.</summary>
    public static bool TryCreate(decimal value, out Kilocalories kilocalories)
    {
        bool isValid = ValueObjectValidation.IsNonNegative(value);
        kilocalories = isValid ? new Kilocalories(value) : default;
        return isValid;
    }
}
