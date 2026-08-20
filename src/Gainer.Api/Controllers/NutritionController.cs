using Gainer.Api.Composition;
using Gainer.Contracts.Nutrition;
using Gainer.Core.Nutrition;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/nutrition")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class NutritionController(
    INutritionQueries queries,
    ISmartNutritionQueries smartQueries,
    IMealEstimator mealEstimator) : ControllerBase
{
    [HttpGet("days/{localDate}")]
    [ProducesResponseType<NutritionDayResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<NutritionDayResponse>> Day(
        DateOnly localDate,
        CancellationToken cancellationToken = default)
    {
        NutritionDaySnapshot? day = await queries.GetDayAsync(localDate, cancellationToken);
        NutritionTargetVersionDraft? target = await smartQueries.GetEffectiveNutritionTargetAsync(localDate, cancellationToken);
        NutritionTotals totals = day?.Totals ?? NutritionTotals.Empty;
        return Ok(day is null
            ? new NutritionDayResponse(null, localDate, [], Totals(totals), null, null, 0, Progress(totals, target))
            : new NutritionDayResponse(
                day.NutritionDayId,
                day.LocalDate,
                day.Entries.Select(Entry).ToArray(),
                Totals(day.Totals),
                day.CreatedAtUtc,
                day.UpdatedAtUtc,
                day.Version,
                Progress(day.Totals, target)));
    }

    [HttpGet("recent")]
    [ProducesResponseType<RecentNutritionEntriesResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<RecentNutritionEntriesResponse>> Recent(
        [FromQuery] int limit = 20,
        CancellationToken cancellationToken = default)
    {
        if (limit is < 1 or > 50)
        {
            ModelState.AddModelError("limit", "Limit must be between 1 and 50.");
            return ValidationProblem(ModelState);
        }
        IReadOnlyList<NutritionEntrySnapshot> entries = await queries.GetRecentEntriesAsync(limit, cancellationToken);
        return Ok(new RecentNutritionEntriesResponse(entries.Select(Entry).ToArray()));
    }

    [HttpGet("reusable-meals")]
    [ProducesResponseType<ReusableMealsResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<ReusableMealsResponse>> ReusableMeals(
        [FromQuery] bool includeArchived = false,
        CancellationToken cancellationToken = default)
    {
        IReadOnlyList<ReusableMealSnapshot> meals = await smartQueries
            .GetReusableMealsAsync(includeArchived, cancellationToken);
        return Ok(new ReusableMealsResponse(meals.Select(ReusableMeal).ToArray()));
    }

    [HttpGet("reusable-meals/{reusableMealId:guid}")]
    [ProducesResponseType<ReusableMealResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ReusableMealResponse>> ReusableMealById(
        Guid reusableMealId,
        CancellationToken cancellationToken = default)
    {
        ReusableMealSnapshot? meal = await smartQueries.GetReusableMealAsync(reusableMealId, cancellationToken);
        return meal is null ? NotFound() : Ok(ReusableMeal(meal));
    }

    [HttpGet("targets/schedule")]
    [ProducesResponseType<NutritionTargetScheduleResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<NutritionTargetScheduleResponse>> TargetSchedule(
        CancellationToken cancellationToken = default)
    {
        NutritionTargetScheduleSnapshot? schedule = await smartQueries
            .GetNutritionTargetScheduleAsync(cancellationToken);
        return Ok(schedule is null
            ? new NutritionTargetScheduleResponse(null, [], null, null, 0)
            : new NutritionTargetScheduleResponse(
                schedule.NutritionTargetScheduleId,
                schedule.Versions.Select(TargetVersion).ToArray(),
                schedule.CreatedAtUtc,
                schedule.UpdatedAtUtc,
                schedule.Version));
    }

    [HttpGet("targets/effective/{localDate}")]
    [ProducesResponseType<EffectiveNutritionTargetResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<EffectiveNutritionTargetResponse>> EffectiveTarget(
        DateOnly localDate,
        CancellationToken cancellationToken = default)
    {
        NutritionTargetVersionDraft? target = await smartQueries
            .GetEffectiveNutritionTargetAsync(localDate, cancellationToken);
        return Ok(new EffectiveNutritionTargetResponse(localDate, target is null ? null : TargetVersion(target)));
    }

    [HttpPost("meal-estimates")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(9 * 1024 * 1024)]
    [ProducesResponseType<MealEstimateResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status429TooManyRequests)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<MealEstimateResponse>> EstimateMeal(
        [FromForm] string? text,
        [FromForm] IFormFile? image,
        [FromForm] bool imageConsent = false,
        CancellationToken cancellationToken = default)
    {
        byte[]? uploadedBytes = null;
        try
        {
            if (Request.HasFormContentType && (await Request.ReadFormAsync(cancellationToken)).Files.Count > 1)
                throw new MealEstimationException("too_many_images", "Exactly one image may be uploaded.");
            MealImageInput? imageInput = null;
            if (image is not null)
            {
                if (image.Length is <= 0 or > 8 * 1024 * 1024)
                    throw new MealEstimationException("invalid_image_size", "The image is empty or too large.");
                await using var stream = new MemoryStream(capacity: checked((int)image.Length));
                await image.CopyToAsync(stream, cancellationToken);
                uploadedBytes = stream.ToArray();
                imageInput = new MealImageInput(uploadedBytes, image.ContentType);
            }

            MealEstimateDraft draft = await mealEstimator.EstimateAsync(
                MealEstimationInput.Create(text, imageInput, imageConsent), cancellationToken);
            Response.Headers.CacheControl = "no-store, private";
            return Ok(new MealEstimateResponse(
                draft.Components.Select(item => new MealEstimateComponentResponse(
                    item.Name,
                    item.AmountGrams,
                    item.Kilocalories,
                    item.ProteinGrams,
                    item.CarbohydrateGrams,
                    item.FatGrams,
                    item.Confidence.ToString(),
                    item.DataGaps)).ToArray(),
                draft.Provider,
                draft.SchemaVersion,
                draft.EstimatedAtUtc));
        }
        catch (MealEstimationException exception)
        {
            var problem = new ProblemDetails
            {
                Status = exception.StatusCode,
                Title = "Meal estimation failed",
                Detail = exception.Message,
            };
            problem.Extensions["code"] = exception.Code;
            return StatusCode(exception.StatusCode, problem);
        }
        finally
        {
            if (uploadedBytes is not null) Array.Clear(uploadedBytes);
        }
    }

    private static NutritionEntryResponse Entry(NutritionEntrySnapshot entry) => new(
        entry.EntryId,
        entry.Meal.ToString(),
        entry.Position,
        entry.ProductName,
        entry.Brand,
        entry.AmountGrams,
        Totals(entry.Totals),
        new NutritionTotalsResponse(
            entry.Per100Grams.Kilocalories,
            entry.Per100Grams.ProteinGrams,
            entry.Per100Grams.CarbohydrateGrams,
            entry.Per100Grams.FatGrams),
        entry.Source is null ? null : new NutritionSourceResponse(
            entry.Source.Provider,
            entry.Source.Barcode,
            entry.Source.RetrievedAtUtc,
            entry.Source.BasisGrams));

    private static NutritionTotalsResponse Totals(NutritionTotals totals) => new(
        totals.Kilocalories,
        totals.ProteinGrams,
        totals.CarbohydrateGrams,
        totals.FatGrams);

    private static ReusableMealResponse ReusableMeal(ReusableMealSnapshot meal) => new(
        meal.ReusableMealId,
        meal.Name,
        meal.Description,
        meal.StandardPortion,
        meal.Status.ToString(),
        meal.Components.OrderBy(item => item.Position).Select(item => new ReusableMealComponentResponse(
            item.ComponentId,
            item.Position,
            item.Name,
            item.Brand,
            item.AmountGrams,
            Totals(item.Totals),
            new NutritionTotalsResponse(
                item.Per100Grams.Kilocalories,
                item.Per100Grams.ProteinGrams,
                item.Per100Grams.CarbohydrateGrams,
                item.Per100Grams.FatGrams),
            item.Source is null ? null : new NutritionSourceResponse(
                item.Source.Provider,
                item.Source.Barcode,
                item.Source.RetrievedAtUtc,
                item.Source.BasisGrams))).ToArray(),
        meal.CreatedAtUtc,
        meal.UpdatedAtUtc,
        meal.Version);

    private static NutritionTargetVersionResponse TargetVersion(NutritionTargetVersionDraft target) => new(
        target.TargetVersionId,
        target.Name,
        target.Category.ToString(),
        target.EffectiveFrom,
        target.EffectiveUntil,
        target.Kilocalories,
        target.InputMode.ToString(),
        target.ProteinGrams,
        target.CarbohydrateGrams,
        target.FatGrams,
        target.ProteinPercent,
        target.CarbohydratePercent,
        target.FatPercent,
        target.Origin.ToString(),
        target.AlgorithmVersion,
        target.Reason,
        target.MacroEnergyKilocalories,
        target.RequiresEnergyMismatchConfirmation);

    private static NutritionProgressResponse? Progress(NutritionTotals totals, NutritionTargetVersionDraft? target) =>
        target is null ? null : new NutritionProgressResponse(
            Nutrient(totals.Kilocalories, target.Kilocalories, true),
            Nutrient(totals.ProteinGrams, target.ProteinGrams),
            Nutrient(totals.CarbohydrateGrams, target.CarbohydrateGrams),
            Nutrient(totals.FatGrams, target.FatGrams));

    private static NutrientProgressResponse Nutrient(decimal? consumed, decimal target, bool complete = false)
    {
        decimal value = consumed ?? 0m;
        return new NutrientProgressResponse(
            value,
            target,
            target - value,
            decimal.Round(value / target, 4, MidpointRounding.AwayFromZero),
            complete || consumed is not null);
    }
}
