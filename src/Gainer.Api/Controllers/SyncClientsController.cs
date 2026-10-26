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
[Route(ApiConstants.Version1Route + "/sync/clients")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class SyncClientsController(ISyncClientRegistry registry, IUserContext userContext) : ControllerBase
{
    [HttpPut("{clientId:guid}")]
    [ProducesResponseType<SyncClientResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
    public async Task<ActionResult<SyncClientResponse>> Register(
        Guid clientId,
        RegisterSyncClientRequest request,
        CancellationToken cancellationToken)
    {
        if (SyncAccountIdentityGuard.Validate(HttpContext, userContext, request.ProtocolVersion) is { } identityProblem)
            return identityProblem;

        if (clientId == Guid.Empty || request.ClientId != clientId)
            return Problem(StatusCodes.Status422UnprocessableEntity, "invalid_client_id", "Route and body client ids must match.");
        try
        {
            RegisteredSyncClient client = await registry.RegisterAsync(new RegisterSyncClientCommand(
                clientId,
                request.DisplayName,
                request.ProtocolVersion,
                request.TakeOverWriting), cancellationToken);
            return Ok(new SyncClientResponse(
                client.ClientId,
                client.DisplayName,
                client.ProtocolVersion,
                client.IsActiveWriter,
                client.RegisteredAtUtc,
                client.LastSeenAtUtc));
        }
        catch (SyncUpgradeRequiredException exception)
        {
            return Problem(StatusCodes.Status409Conflict, exception.Code, exception.Message);
        }
        catch (SyncMutationConflictException exception)
        {
            return Problem(StatusCodes.Status409Conflict, exception.Code, exception.Message);
        }
        catch (SyncMutationValidationException exception)
        {
            return Problem(StatusCodes.Status422UnprocessableEntity, exception.Code, exception.Message);
        }
    }

    private ObjectResult Problem(int status, string code, string title) =>
        SyncProblemResults.Create(HttpContext, status, code, title);
}
