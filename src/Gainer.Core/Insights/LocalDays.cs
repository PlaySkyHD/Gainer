namespace Gainer.Core.Insights;

/// <summary>Lokale Tagesgrenzen in einer Zeitzone; gemeinsam für Dashboard, Coach und Tageskontingent.</summary>
public static class LocalDays
{
    private static readonly Lazy<TimeZoneInfo> DefaultZone = new(
        () => TimeZoneInfo.FindSystemTimeZoneById(TrainingStatistics.DefaultTimeZoneId));

    /// <summary>Zeitzone ohne explizite Angabe (Europe/Berlin).</summary>
    public static TimeZoneInfo Default => DefaultZone.Value;

    /// <summary>Das heutige Datum in der Zeitzone.</summary>
    public static DateOnly Today(this TimeProvider timeProvider, TimeZoneInfo timeZone) =>
        DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(timeProvider.GetUtcNow().UtcDateTime, timeZone));

    /// <summary>Beginn des lokalen Tages in UTC; fällt Mitternacht in eine Zeitumstellungslücke, gilt die erste gültige Zeit danach.</summary>
    /// <summary>Local calendar day of a UTC instant in the given time zone.</summary>
    public static DateOnly DateOf(DateTime utc, TimeZoneInfo timeZone) =>
        DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(utc, timeZone));

    public static DateTime StartOfDayUtc(DateOnly date, TimeZoneInfo timeZone)
    {
        DateTime local = date.ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified);
        while (timeZone.IsInvalidTime(local)) local = local.AddMinutes(30);
        return TimeZoneInfo.ConvertTimeToUtc(local, timeZone);
    }
}
