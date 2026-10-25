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
        [FromQuery] int? protocolVersion = null,
        CancellationToken cancellationToken = default)
    {
        if (SyncAccountIdentityGuard.Validate(Request.Headers, userContext) is { } identityProblem)
            return identityProblem;

        if (after < 0 || limit is < 1 or > SyncProtocol.MaximumBatchesPerPull)
        {
            ModelState.AddModelError("cursor", "Cursor or limit is outside the supported range.");
            return ValidationProblem(ModelState);
        }
        // Apps before protocol 4 send no version and compare the response version with 3.
        int clientProtocol = protocolVersion ?? SyncProtocol.UnversionedPullVersion;
        if (clientProtocol > SyncProtocol.CurrentVersion)
        {
            ModelState.AddModelError(nameof(protocolVersion), "The protocol version is newer than this server.");
            return ValidationProblem(ModelState);
        }
        if (clientProtocol < SyncProtocol.PreviousVersion) return UpgradeRequired();

        SyncChangeFeedPage page = await feed.GetAsync(after, limit, clientProtocol, cancellationToken);
        // Nothing the client can apply before the next unknown resource: it must update, its cursor stays.
        if (page.UpgradeRequired && page.Batches.Count == 0) return UpgradeRequired();
        return Ok(new PullChangesResponse(
            clientProtocol,
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

    private static ObjectResult UpgradeRequired()
    {
        var upgrade = new SyncUpgradeRequiredException();
        return SyncProblemResults.Create(StatusCodes.Status409Conflict, upgrade.Code, upgrade.Message);
    }
}
