using Gainer.Api.Composition;
using Gainer.Api.Errors;
using Gainer.Api.Security;
using Gainer.Contracts.Sync;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/sync/handovers")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class SyncHandoversController(ISyncHandoverService service, IUserContext userContext) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<BeginSyncHandoverResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict, "application/problem+json")]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity, "application/problem+json")]
    public async Task<ActionResult<BeginSyncHandoverResponse>> Begin(
        BeginSyncHandoverRequest request,
        CancellationToken cancellationToken)
    {
        if (SyncAccountIdentityGuard.Validate(Request.Headers, userContext) is { } identityProblem)
            return identityProblem;

        try
        {
            BeginSyncHandoverResult result = await service.BeginAsync(
                new BeginSyncHandoverCommand(request.RequestId, request.SourceClientId, request.ExpectedRevision),
                cancellationToken);
            return Ok(new BeginSyncHandoverResponse(
                result.HandoverId, result.OneTimeCode, result.FrozenRevision, result.ExpiresAtUtc));
        }
        catch (SyncHandoverException exception)
        {
            return HandoverProblem(exception);
        }
    }

    [HttpPost("{handoverId:guid}/complete")]
    [ProducesResponseType<CompleteSyncHandoverResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound, "application/problem+json")]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict, "application/problem+json")]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity, "application/problem+json")]
    public async Task<ActionResult<CompleteSyncHandoverResponse>> Complete(
        Guid handoverId,
        CompleteSyncHandoverRequest request,
        CancellationToken cancellationToken)
    {
        if (SyncAccountIdentityGuard.Validate(Request.Headers, userContext) is { } identityProblem)
            return identityProblem;

        try
        {
            CompleteSyncHandoverResult result = await service.CompleteAsync(
                new CompleteSyncHandoverCommand(
                    handoverId, request.OneTimeCode, request.TargetClientId, request.CaughtUpRevision),
                cancellationToken);
            return Ok(new CompleteSyncHandoverResponse(
                result.HandoverId,
                result.TargetClientId,
                result.FrozenRevision,
                result.IsActiveWriter,
                result.CompletedAtUtc));
        }
        catch (SyncHandoverException exception)
        {
            return HandoverProblem(exception);
        }
    }

    [HttpPost("{handoverId:guid}/cancel")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound, "application/problem+json")]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict, "application/problem+json")]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity, "application/problem+json")]
    public async Task<IActionResult> Cancel(
        Guid handoverId,
        CancelSyncHandoverRequest request,
        CancellationToken cancellationToken)
    {
        if (SyncAccountIdentityGuard.Validate(Request.Headers, userContext) is { } identityProblem)
            return identityProblem;

        try
        {
            await service.CancelAsync(
                new CancelSyncHandoverCommand(handoverId, request.SourceClientId),
                cancellationToken);
            return NoContent();
        }
        catch (SyncHandoverException exception)
        {
            return HandoverProblem(exception);
        }
    }

    private ObjectResult HandoverProblem(SyncHandoverException exception)
    {
        var problem = new ProblemDetails
        {
            Status = exception.StatusCode,
            Title = ProblemTitle(exception.StatusCode),
            Type = $"https://gainer.local/problems/{exception.Code}",
        };
        ProblemDetailsConfiguration.AddStableExtensions(HttpContext, problem);
        problem.Extensions["code"] = exception.Code;
        return StatusCode(exception.StatusCode, problem);
    }

    private static string ProblemTitle(int statusCode) => statusCode switch
    {
        StatusCodes.Status404NotFound => "The requested handover was not found.",
        StatusCodes.Status422UnprocessableEntity => "The handover request is invalid.",
        _ => "The handover conflicts with the current state.",
    };
}
