using Gainer.Api.Composition;
using Gainer.Contracts.Training;
using Gainer.Core.Training;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/exercises")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class ExerciseCatalogController(IExerciseCatalogQueries queries) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType<ExerciseCatalogResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<ExerciseCatalogResponse>> Search(
        [FromQuery] string? search,
        [FromQuery] string? targetMuscle,
        [FromQuery] string? muscleGroup,
        [FromQuery] string? equipment,
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 50,
        CancellationToken cancellationToken = default)
    {
        if (offset < 0 || limit is < 1 or > 100 ||
            search?.Length > 100 || targetMuscle?.Length > 100 ||
            muscleGroup?.Length > 100 || equipment?.Length > 100)
        {
            ModelState.AddModelError("filter", "The catalog filter is outside the supported range.");
            return ValidationProblem(ModelState);
        }

        ExerciseCatalogPage page = await queries.SearchAsync(
            new ExerciseCatalogFilter(search, targetMuscle, muscleGroup, equipment, offset, limit),
            cancellationToken);
        return Ok(new ExerciseCatalogResponse(
            page.Items.Select(item => new ExerciseCatalogItemResponse(
                item.Id,
                item.Name,
                item.Description,
                item.TargetMuscle,
                item.MuscleGroup,
                item.Equipment,
                item.IsCustom,
                item.CatalogVersion,
                item.Version)).ToList(),
            page.Offset,
            page.Limit,
            page.Total));
    }
}
