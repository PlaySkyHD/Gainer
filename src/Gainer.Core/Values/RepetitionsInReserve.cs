namespace Gainer.Core.Values;

/// <summary>Represents repetitions in reserve between zero and ten.</summary>
public readonly record struct RepetitionsInReserve
{
    private const decimal Minimum = 0m;
    private const decimal Maximum = 10m;

    private RepetitionsInReserve(decimal value)
    {
        Value = value;
    }

    /// <summary>Gets the RIR value.</summary>
    public decimal Value { get; }

    /// <summary>Creates a valid RIR value.</summary>
    public static RepetitionsInReserve From(decimal value)
    {
        return TryCreate(value, out RepetitionsInReserve rir)
            ? rir
            : throw new ArgumentOutOfRangeException(nameof(value), "RIR must be between 0 and 10.");
    }

    /// <summary>Attempts to create a valid RIR value.</summary>
    public static bool TryCreate(decimal value, out RepetitionsInReserve rir)
    {
        bool isValid = value >= Minimum && value <= Maximum;
        rir = isValid ? new RepetitionsInReserve(value) : default;
        return isValid;
    }
}
