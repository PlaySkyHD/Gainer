using Gainer.Api.Composition;
using Gainer.Contracts.Insights;
using Gainer.Core.Insights;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/insights")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class InsightsController(IInsightQueries queries, TimeProvider timeProvider) : ControllerBase
{
    [HttpGet("dashboard")]
    [ProducesResponseType<DashboardInsightsResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<DashboardInsightsResponse>> Dashboard(
        [FromQuery] DateOnly? through = null,
        [FromQuery] int days = 30,
        CancellationToken cancellationToken = default)
    {
        if (days is < 1 or > 365) return Validation("days", "Days must be between 1 and 365.");
        DateOnly end = through ?? DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime);
        return Ok(ToResponse(await queries.DashboardAsync(end, days, cancellationToken)));
    }

    [HttpGet("exercises/{exerciseId:guid}/progress")]
    [ProducesResponseType<ExerciseProgressResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<ExerciseProgressResponse>> ExerciseProgress(
        Guid exerciseId,
        [FromQuery] string window = "30",
        [FromQuery] string timeZone = "Europe/Berlin",
        CancellationToken cancellationToken = default)
    {
        int? windowDays = window.ToLowerInvariant() switch
        {
            "7" or "7d" => 7,
            "30" or "30d" => 30,
            "90" or "90d" => 90,
            "all" => null,
            _ => -1,
        };
        if (windowDays == -1) return Validation("window", "Window must be 7, 30, 90 or all.");
        TimeZoneInfo zone;
        try { zone = TimeZoneInfo.FindSystemTimeZoneById(timeZone); }
        catch (TimeZoneNotFoundException) { return Validation("timeZone", "The time zone is unknown."); }
        catch (InvalidTimeZoneException) { return Validation("timeZone", "The time zone is invalid."); }
        ExerciseProgressSnapshot result = await queries.ExerciseProgressAsync(
            exerciseId, windowDays, timeProvider.GetUtcNow().UtcDateTime, zone, cancellationToken);
        return Ok(new ExerciseProgressResponse(
            result.AsOfRevision,
            result.ExerciseId,
            result.WindowDays,
            result.FromUtc,
            result.ThroughUtc,
            result.Points.Select(item => new ExerciseProgressPointResponse(
                item.WorkoutId, item.CompletedAtUtc, item.VolumeKgRepetitions,
                item.BestWeightKg, item.BestRepetitions, item.EstimatedOneRepMaxKg)).ToList(),
            Best(result.BestSet)));
    }

    private ActionResult Validation(string key, string message)
    {
        ModelState.AddModelError(key, message);
        return ValidationProblem(ModelState);
    }

    private static DashboardInsightsResponse ToResponse(DashboardInsightSnapshot result) => new(
        result.AsOfRevision,
        result.From,
        result.Through,
        result.ActiveGoal is null ? null : new ActiveGoalInsightResponse(
            result.ActiveGoal.GoalId, result.ActiveGoal.Kind.ToString(), result.ActiveGoal.StartWeightKg,
            result.ActiveGoal.TargetWeightKg, result.ActiveGoal.StartDate, result.ActiveGoal.TargetDate),
        result.LatestWeight is null ? null : new WeightPointResponse(result.LatestWeight.Date, result.LatestWeight.WeightKg),
        result.WeightSeries.Select(item => new WeightPointResponse(item.Date, item.WeightKg)).ToList(),
        Weight(result.SevenDayWeight),
        Weight(result.Weight),
        new NutritionInsightsResponse(
            result.Nutrition.AlgorithmVersion, result.Nutrition.ExpectedDays, result.Nutrition.ObservedDays,
            result.Nutrition.Coverage, result.Nutrition.MealDiaryDays, result.Nutrition.LegacyCheckInDays,
            Metric(result.Nutrition.CaloriesKcal), Metric(result.Nutrition.ProteinGrams),
            Metric(result.Nutrition.CarbohydrateGrams), Metric(result.Nutrition.FatGrams)),
        new TrainingInsightsResponse(
            result.Training.VolumeAlgorithmVersion, result.Training.EstimatedOneRepMaxAlgorithmVersion,
            result.Training.VolumeUnit, result.Training.WorkoutCount, result.Training.VolumeKgRepetitions,
            Best(result.Training.BestSet)),
        result.WorkoutsLast7Days);

    private static WeightInsightsResponse Weight(WeightInsights value) => new(
            value.AverageAlgorithmVersion, value.TrendAlgorithmVersion, value.Unit,
            value.From, value.Through, value.ExpectedDays, value.ObservedDays,
            value.Coverage, value.AverageKg, value.TrendKgPerWeek);

    private static MetricAverageResponse Metric(MetricAverage value) => new(value.Value, value.ObservedDays);
    private static BestSetResponse? Best(BestSet? value) => value is null ? null : new(
        value.WorkoutId, value.ExerciseId, value.CompletedAtUtc, value.WeightKg,
        value.Repetitions, value.EstimatedOneRepMaxKg);
}
