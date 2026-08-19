namespace Gainer.Core.Values;

/// <summary>Represents a non-negative whole step count.</summary>
public readonly record struct Steps
{
    private Steps(int value)
    {
        Value = value;
    }

    /// <summary>Gets the whole step count.</summary>
    public int Value { get; }

    /// <summary>Creates a non-negative step count.</summary>
    public static Steps From(int value)
    {
        return TryCreate(value, out Steps steps)
            ? steps
            : throw new ArgumentOutOfRangeException(nameof(value), "Steps cannot be negative.");
    }

    /// <summary>Attempts to create a non-negative step count.</summary>
    public static bool TryCreate(int value, out Steps steps)
    {
        bool isValid = value >= 0;
        steps = isValid ? new Steps(value) : default;
        return isValid;
    }
}
