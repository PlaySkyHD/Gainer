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
public sealed class MuscleSuggestionsController(IMuscleSuggester muscleSuggester) : ControllerBase
{
    /// <summary>Asks the AI assistant for the muscles of an exercise; it may answer with one follow-up question.</summary>
    [HttpPost("muscle-suggestions")]
    [ProducesResponseType<MuscleSuggestionResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status429TooManyRequests)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<MuscleSuggestionResponse>> SuggestMuscles(
        [FromBody] MuscleSuggestionRequest request,
        CancellationToken cancellationToken = default)
    {
        try
        {
            MuscleSuggestionInput input = MuscleSuggestionInput.Create(
                request.Name,
                request.ExerciseType,
                request.Notes,
                request.Turns?.Select(turn => new MuscleSuggestionTurn(turn.Question, turn.Answer)).ToArray());
            MuscleSuggestionResult result = await muscleSuggester.SuggestAsync(input, cancellationToken);
            Response.Headers.CacheControl = "no-store, private";
            return Ok(new MuscleSuggestionResponse(
                result.IsQuestion ? "question" : "suggestion",
                result.Question,
                result.Options,
                result.PrimaryMuscles,
                result.SecondaryMuscles,
                result.Explanation));
        }
        catch (MuscleSuggestionException exception)
        {
            var problem = new ProblemDetails
            {
                Status = exception.StatusCode,
                Title = "Muscle suggestion failed",
                Detail = exception.Message,
            };
            problem.Extensions["code"] = exception.Code;
            return StatusCode(exception.StatusCode, problem);
        }
    }
}
