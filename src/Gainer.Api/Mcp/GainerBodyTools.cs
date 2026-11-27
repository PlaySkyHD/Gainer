using System.ComponentModel;
using Gainer.Core.BodyTracking;
using ModelContextProtocol.Server;

namespace Gainer.Api.Mcp;

/// <summary>Body goals and daily check-ins (weight, steps, sleep, resting heart rate, HRV).</summary>
[McpServerToolType]
public sealed class GainerBodyTools(IBodyTrackingQueries body, TimeProvider timeProvider)
{
    private const int MaximumCheckInDays = 366;

    [McpServerTool(Name = "get_body_goals", Title = "Ziele", ReadOnly = true, Idempotent = true, OpenWorld = false,
        UseStructuredContent = true)]
    [Description("The active body goal (bulk, maintain or cut with start and target weight in kg and target date) " +
        "and all earlier goals.")]
    public async Task<BodyGoalsResult> GetBodyGoals(CancellationToken cancellationToken = default) => new(
        await body.GetActiveGoalAsync(cancellationToken),
        await body.GetGoalHistoryAsync(cancellationToken));

    [McpServerTool(Name = "list_check_ins", Title = "Check-ins", ReadOnly = true, Idempotent = true, OpenWorld = false,
        UseStructuredContent = true)]
    [Description("Daily check-ins in a range of local days, oldest first: body weight in kg, logged calories and macros, " +
        "steps, sleep minutes, resting heart rate (bpm) and resting HRV (RMSSD in ms). Days without a check-in are " +
        "missing, not zero. Defaults to the last 30 days; at most 366 days.")]
    public async Task<CheckInListResult> ListCheckIns(
        [Description("First local day (YYYY-MM-DD); default 30 days before through.")] DateOnly? from = null,
        [Description("Last local day (YYYY-MM-DD); default today.")] DateOnly? through = null,
        CancellationToken cancellationToken = default)
    {
        (DateOnly start, DateOnly end) = McpDates.Range(timeProvider, from, through, 30, MaximumCheckInDays);
        IReadOnlyList<DailyCheckInSnapshot> items = await body.GetCheckInsBetweenAsync(start, end, cancellationToken);
        return new CheckInListResult(start, end, items
            .Select(item => new CheckInResult(
                item.LocalDate,
                item.Values.WeightKg,
                item.Values.CaloriesKcal,
                item.Values.ProteinGrams,
                item.Values.CarbohydrateGrams,
                item.Values.FatGrams,
                item.Values.Steps,
                item.Values.SleepMinutes,
                item.Values.RestingHeartRateBpm,
                item.Values.RestingHrvMs))
            .ToList());
    }
}

public sealed record BodyGoalsResult(BodyGoalSnapshot? Active, IReadOnlyList<BodyGoalSnapshot> History);

public sealed record CheckInListResult(DateOnly From, DateOnly Through, IReadOnlyList<CheckInResult> CheckIns);

public sealed record CheckInResult(
    DateOnly Date,
    decimal WeightKg,
    decimal? CaloriesKcal,
    decimal? ProteinGrams,
    decimal? CarbohydrateGrams,
    decimal? FatGrams,
    int? Steps,
    int? SleepMinutes,
    int? RestingHeartRateBpm,
    int? RestingHrvMs);
