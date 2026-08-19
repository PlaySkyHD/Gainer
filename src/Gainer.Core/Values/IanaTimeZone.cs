namespace Gainer.Core.Values;

/// <summary>Represents a validated IANA time-zone identifier.</summary>
public readonly record struct IanaTimeZone
{
    private const int MaximumIdLength = 128;

    private IanaTimeZone(string id)
    {
        Id = id;
    }

    /// <summary>Gets the IANA identifier.</summary>
    public string Id { get; }

    /// <summary>Creates a validated IANA time zone.</summary>
    public static IanaTimeZone From(string id)
    {
        return TryCreate(id, out IanaTimeZone timeZone)
            ? timeZone
            : throw new ArgumentException("The value is not a supported IANA time-zone identifier.", nameof(id));
    }

    /// <summary>Attempts to create a supported IANA time zone.</summary>
    public static bool TryCreate(string? id, out IanaTimeZone timeZone)
    {
        if (id is null || !HasIanaShape(id) || !CanResolve(id))
        {
            timeZone = default;
            return false;
        }

        timeZone = new IanaTimeZone(id);
        return true;
    }

    /// <summary>Gets the current local calendar day using the supplied clock.</summary>
    public DateOnly GetLocalDate(TimeProvider timeProvider)
    {
        ArgumentNullException.ThrowIfNull(timeProvider);
        TimeZoneInfo zone = TimeZoneInfo.FindSystemTimeZoneById(Id);
        DateTimeOffset localTime = TimeZoneInfo.ConvertTime(timeProvider.GetUtcNow(), zone);
        return DateOnly.FromDateTime(localTime.DateTime);
    }

    private static bool HasIanaShape(string? id)
    {
        if (id is null || id.Length is 0 or > MaximumIdLength)
        {
            return false;
        }

        if (id == "UTC")
        {
            return true;
        }

        string[] segments = id.Split('/');
        return segments.Length >= 2
               && segments.All(segment => segment.Length > 0 && segment != "." && segment != "..")
               && id.All(character => char.IsAsciiLetterOrDigit(character)
                                      || character is '/' or '_' or '-' or '+' or '.');
    }

    private static bool CanResolve(string id)
    {
        try
        {
            _ = TimeZoneInfo.FindSystemTimeZoneById(id);
            return true;
        }
        catch (TimeZoneNotFoundException)
        {
            return false;
        }
        catch (InvalidTimeZoneException)
        {
            return false;
        }
    }
}
