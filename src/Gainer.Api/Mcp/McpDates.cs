using Gainer.Core.Insights;
using ModelContextProtocol;

namespace Gainer.Api.Mcp;

/// <summary>Local-day ranges of tool arguments, in the time zone the insights use.</summary>
internal static class McpDates
{
    public static TimeZoneInfo TimeZone => LocalDays.Default;

    public static DateOnly Today(TimeProvider timeProvider) => timeProvider.Today(TimeZone);

    /// <summary>
    /// Resolves an optional range: without <paramref name="through"/> it ends today, without
    /// <paramref name="from"/> it spans <paramref name="defaultDays"/> days. Longer ranges than
    /// <paramref name="maximumDays"/> are rejected as a tool error.
    /// </summary>
    public static (DateOnly From, DateOnly Through) Range(
        TimeProvider timeProvider,
        DateOnly? from,
        DateOnly? through,
        int defaultDays,
        int maximumDays)
    {
        DateOnly end = through ?? Today(timeProvider);
        DateOnly start = from ?? end.AddDays(1 - defaultDays);
        if (start > end)
        {
            throw new McpException("from must not be after through.");
        }

        if (end.DayNumber - start.DayNumber + 1 > maximumDays)
        {
            throw new McpException($"The range may cover at most {maximumDays} days.");
        }

        return (start, end);
    }
}
