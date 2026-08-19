namespace Gainer.Core.Values;

/// <summary>Provides shared validation predicates for canonical numeric values.</summary>
public static class ValueObjectValidation
{
    /// <summary>Returns whether a decimal value is zero or positive.</summary>
    public static bool IsNonNegative(decimal value) => value >= decimal.Zero;

    /// <summary>Returns whether a decimal value is strictly positive.</summary>
    public static bool IsPositive(decimal value) => value > decimal.Zero;

    /// <summary>Returns whether an integer is inside the inclusive range.</summary>
    public static bool IsInRange(int value, int minimum, int maximum) =>
        value >= minimum && value <= maximum;
}
