namespace Gainer.Core.Values;

/// <summary>Represents sleep duration between zero and twenty-four hours.</summary>
public readonly record struct SleepMinutes
{
    /// <summary>The maximum duration accepted for one daily check-in.</summary>
    public const int Maximum = 24 * 60;

    private SleepMinutes(int value)
    {
        Value = value;
    }

    /// <summary>Gets the duration in whole minutes.</summary>
    public int Value { get; }

    /// <summary>Creates a valid sleep duration.</summary>
    public static SleepMinutes From(int value)
    {
        return TryCreate(value, out SleepMinutes minutes)
            ? minutes
            : throw new ArgumentOutOfRangeException(nameof(value), "Sleep must be between 0 and 1440 minutes.");
    }

    /// <summary>Attempts to create a valid sleep duration.</summary>
    public static bool TryCreate(int value, out SleepMinutes minutes)
    {
        bool isValid = ValueObjectValidation.IsInRange(value, minimum: 0, Maximum);
        minutes = isValid ? new SleepMinutes(value) : default;
        return isValid;
    }
}
