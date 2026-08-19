using Gainer.Api.Composition;
using Gainer.Api.Errors;
using Gainer.Contracts.Nutrition;
using Gainer.Core.Nutrition;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/foods")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class FoodCatalogController(IExternalFoodCatalog catalog) : ControllerBase
{
    [HttpGet("barcode/{barcode}")]
    [ProducesResponseType<FoodCatalogProductResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status429TooManyRequests)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<FoodCatalogProductResponse>> Barcode(
        string barcode,
        CancellationToken cancellationToken = default)
    {
        if (barcode.Length is < 4 or > 32 || barcode.Any(character => !char.IsAsciiDigit(character)))
            return Validation("barcode", "Barcode must contain 4 to 32 digits.");
        try
        {
            return Ok(ToResponse(await catalog.GetByBarcodeAsync(barcode, cancellationToken)));
        }
        catch (FoodCatalogException exception)
        {
            return ProviderProblem(exception);
        }
    }

    [HttpGet("search")]
    [ProducesResponseType<FoodCatalogSearchResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status429TooManyRequests)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<FoodCatalogSearchResponse>> Search(
        [FromQuery] string query,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        CancellationToken cancellationToken = default)
    {
        string normalized = query?.Trim() ?? string.Empty;
        if (normalized.Length is < 2 or > 100) return Validation("query", "Query must contain 2 to 100 characters.");
        if (page is < 1 or > 100) return Validation("page", "Page must be between 1 and 100.");
        if (pageSize is < 1 or > 20) return Validation("pageSize", "Page size must be between 1 and 20.");
        try
        {
            FoodCatalogSearchResult result = await catalog.SearchAsync(normalized, page, pageSize, cancellationToken);
            return Ok(new FoodCatalogSearchResponse(result.Products.Select(ToResponse).ToArray(), result.Page, result.HasMore));
        }
        catch (FoodCatalogException exception)
        {
            return ProviderProblem(exception);
        }
    }

    private ActionResult Validation(string key, string message)
    {
        ModelState.AddModelError(key, message);
        return ValidationProblem(ModelState);
    }

    private ObjectResult ProviderProblem(FoodCatalogException exception)
    {
        int status = exception.Code == "product_not_found" ? StatusCodes.Status404NotFound
            : exception.Code == "provider_rate_limited" ? StatusCodes.Status429TooManyRequests
            : exception.IsTemporary ? StatusCodes.Status503ServiceUnavailable
            : StatusCodes.Status422UnprocessableEntity;
        var problem = new ProblemDetails
        {
            Status = status,
            Title = ProblemDetailsConfiguration.GetTitle(status),
            Type = ProblemDetailsConfiguration.GetTypeUri(status),
        };
        ProblemDetailsConfiguration.AddStableExtensions(HttpContext, problem);
        problem.Extensions["code"] = exception.Code;
        return StatusCode(status, problem);
    }

    private static FoodCatalogProductResponse ToResponse(FoodCatalogProduct product) => new(
        product.Barcode,
        product.ProductName,
        product.Brand,
        product.BasisGrams,
        product.NutrientsPer100Grams.Kilocalories,
        product.NutrientsPer100Grams.ProteinGrams,
        product.NutrientsPer100Grams.CarbohydrateGrams,
        product.NutrientsPer100Grams.FatGrams,
        product.QualityIndicators,
        product.RetrievedAtUtc,
        product.IsStale,
        product.Source);
}
