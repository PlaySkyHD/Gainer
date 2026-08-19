using Gainer.Api.Composition;
using Gainer.Contracts.Coach;
using Gainer.Core.Coach;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[EnableRateLimiting("coach")]
[Route(ApiConstants.Version1Route + "/coach/responses")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class CoachController(ICoachService coach) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<CoachResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status429TooManyRequests)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status502BadGateway)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<CoachResponse>> Create(
        CoachResponseRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            CoachAnswer answer = await coach.AnswerAsync(request.Question, cancellationToken);
            return Ok(new CoachResponse(
                answer.Summary,
                answer.Observations.Select(item => new CoachObservationResponse(item.Text, item.FactIds)).ToList(),
                answer.Facts.Select(item => new CoachFactResponse(
                    item.FactId, item.Kind, item.Label, item.NumericValue, item.TextValue,
                    item.Unit, item.Period, item.AlgorithmVersion)).ToList(),
                answer.DataGaps,
                answer.Suggestions,
                answer.AsOfRevision));
        }
        catch (OpenAiProviderException exception)
        {
            int status = exception.StatusCode == StatusCodes.Status429TooManyRequests
                ? StatusCodes.Status429TooManyRequests : StatusCodes.Status503ServiceUnavailable;
            return Failure(status, exception.Code, exception.Message);
        }
        catch (CoachResponseValidationException exception)
        {
            return Failure(StatusCodes.Status502BadGateway, "invalid_provider_response", exception.Message);
        }
    }

    private ObjectResult Failure(int status, string code, string title)
    {
        var problem = new ProblemDetails
        {
            Status = status,
            Title = title,
            Type = $"https://gainer.local/problems/{code}",
        };
        problem.Extensions["code"] = code;
        return StatusCode(status, problem);
    }
}
