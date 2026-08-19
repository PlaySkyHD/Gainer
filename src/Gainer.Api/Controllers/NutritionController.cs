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
public sealed class NutritionController(INutritionQueries queries) : ControllerBase
{
    [HttpGet("days/{localDate}")]
    [ProducesResponseType<NutritionDayResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<NutritionDayResponse>> Day(
        DateOnly localDate,
        CancellationToken cancellationToken = default)
    {
        NutritionDaySnapshot? day = await queries.GetDayAsync(localDate, cancellationToken);
        return Ok(day is null
            ? new NutritionDayResponse(null, localDate, [], Totals(NutritionTotals.Empty), null, null, 0)
            : new NutritionDayResponse(
                day.NutritionDayId,
                day.LocalDate,
                day.Entries.Select(Entry).ToArray(),
                Totals(day.Totals),
                day.CreatedAtUtc,
                day.UpdatedAtUtc,
                day.Version));
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
}
