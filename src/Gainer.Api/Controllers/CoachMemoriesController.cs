using Gainer.Api.Composition;
using Gainer.Contracts.Coach;
using Gainer.Core.Coach;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

/// <summary>The user's coach memory. Only the user writes here; the coach can merely suggest entries.</summary>
[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/coach/memories")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class CoachMemoriesController(ICoachMemoryStore memories) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType<CoachMemoryListResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<CoachMemoryListResponse>> List(CancellationToken cancellationToken = default)
    {
        IReadOnlyList<CoachMemoryItem> items = await memories.ListAsync(cancellationToken);
        return Ok(new CoachMemoryListResponse(items.Select(ToResponse).ToList(), CoachMemoryRules.MaxEntriesPerUser));
    }

    /// <summary>
    /// Creates an entry, also to accept a suggestion. The same text again returns the existing entry with 200;
    /// a different category is applied to it.
    /// </summary>
    [HttpPost]
    [ProducesResponseType<CoachMemoryResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<CoachMemoryResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<CoachMemoryResponse>> Create(
        CoachMemoryRequest request,
        CancellationToken cancellationToken = default) =>
        HandleAsync(async () =>
        {
            CoachMemoryCreateResult result = await memories.CreateAsync(
                ParseCategory(request.Category), request.Text, cancellationToken);
            CoachMemoryResponse response = ToResponse(result.Item);
            return result.Created ? StatusCode(StatusCodes.Status201Created, response) : Ok(response);
        });

    /// <summary>Changes an entry; with <c>baseVersion</c> a newer stored version answers 409 <c>memory_conflict</c>.</summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType<CoachMemoryResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<CoachMemoryResponse>> Update(
        Guid id,
        CoachMemoryUpdateRequest request,
        CancellationToken cancellationToken = default) =>
        HandleAsync(async () => Ok(ToResponse(await memories.UpdateAsync(
            id, ParseCategory(request.Category), request.Text, request.BaseVersion, cancellationToken))));

    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken = default) =>
        await memories.DeleteAsync(id, cancellationToken)
            ? NoContent()
            : Failure(new CoachMemoryException(CoachMemoryException.NotFound, "The memory entry does not exist."));

    /// <summary>„Alles vergessen“: removes every entry of the current user.</summary>
    [HttpDelete]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> DeleteAll(CancellationToken cancellationToken = default)
    {
        await memories.DeleteAllAsync(cancellationToken);
        return NoContent();
    }

    private static CoachMemoryCategory ParseCategory(string value) =>
        CoachMemoryRules.TryParse(value, out CoachMemoryCategory category)
            ? category
            : throw new CoachMemoryException(CoachMemoryException.Invalid, "The memory category is unknown.");

    private async Task<ActionResult<CoachMemoryResponse>> HandleAsync(Func<Task<ActionResult<CoachMemoryResponse>>> action)
    {
        try
        {
            return await action();
        }
        catch (CoachMemoryException exception)
        {
            return Failure(exception);
        }
    }

    private ObjectResult Failure(CoachMemoryException exception)
    {
        int status = exception.Code switch
        {
            CoachMemoryException.NotFound => StatusCodes.Status404NotFound,
            CoachMemoryException.LimitReached or CoachMemoryException.Duplicate or CoachMemoryException.Conflict =>
                StatusCodes.Status409Conflict,
            _ => StatusCodes.Status400BadRequest,
        };
        var problem = new ProblemDetails
        {
            Status = status,
            Title = exception.Message,
            Type = $"https://gainer.local/problems/{exception.Code}",
        };
        problem.Extensions["code"] = exception.Code;
        return StatusCode(status, problem);
    }

    /// <summary>Wire form of an entry; the account export uses it too.</summary>
    internal static CoachMemoryResponse ToResponse(CoachMemoryItem item) => new(
        item.Id,
        CoachMemoryRules.ToWire(item.Category),
        item.Text,
        item.CreatedAtUtc,
        item.UpdatedAtUtc,
        item.Version);
}
