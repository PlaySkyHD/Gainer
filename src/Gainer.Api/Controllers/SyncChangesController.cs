using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Sync;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/sync/changes")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class SyncChangesController(ISyncChangeFeed feed, IUserContext userContext) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType<PullChangesResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict, "application/problem+json")]
    public async Task<ActionResult<PullChangesResponse>> Get(
        [FromQuery] long after = 0,
        [FromQuery] int limit = 200,
        CancellationToken cancellationToken = default)
    {
        if (SyncAccountIdentityGuard.Validate(Request.Headers, userContext) is { } identityProblem)
            return identityProblem;

        if (after < 0 || limit is < 1 or > SyncProtocol.MaximumBatchesPerPull)
        {
            ModelState.AddModelError("cursor", "Cursor or limit is outside the supported range.");
            return ValidationProblem(ModelState);
        }
        SyncChangeFeedPage page = await feed.GetAsync(after, limit, cancellationToken);
        return Ok(new PullChangesResponse(
            SyncProtocol.CurrentVersion,
            page.NextCursor,
            page.HasMore,
            page.Batches.Select(batch => new SyncChangeBatchResponse(
                batch.BatchId,
                batch.Revision,
                batch.OriginMutationId,
                batch.Changes.Select(change => new SyncChangeResponse(
                    change.ResourceType,
                    change.ResourceId,
                    change.Version,
                    change.IsTombstone,
                    change.Snapshot)).ToList())).ToList()));
    }
}
