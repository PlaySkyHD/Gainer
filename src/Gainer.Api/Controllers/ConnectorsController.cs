using System.Security.Claims;
using Gainer.Api.Composition;
using Gainer.Contracts.Security;
using Gainer.Core.Access;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

/// <summary>Lists and revokes assistants connected to the signed-in account.</summary>
[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/auth/connectors")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class ConnectorsController(IDeviceSessionService deviceSessions) : ControllerBase
{
    /// <summary>Active connected assistants, newest first.</summary>
    [HttpGet]
    [ProducesResponseType<IReadOnlyList<ConnectorSessionResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<ConnectorSessionResponse>>> List(CancellationToken cancellationToken)
    {
        if (!TryGetUserId(out Guid userId))
        {
            return Unauthorized();
        }

        IReadOnlyList<ConnectorSessionSummary> sessions = await deviceSessions.ListConnectorsAsync(userId, cancellationToken);
        return Ok(sessions
            .Select(item => new ConnectorSessionResponse(item.SessionId, item.Name, item.CreatedAt, item.LastUsedAt))
            .ToList());
    }

    /// <summary>Disconnects one assistant; its tokens stop working with the next request.</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Revoke(Guid id, CancellationToken cancellationToken)
    {
        if (!TryGetUserId(out Guid userId))
        {
            return Unauthorized();
        }

        return await deviceSessions.RevokeConnectorAsync(id, userId, cancellationToken) ? NoContent() : NotFound();
    }

    private bool TryGetUserId(out Guid userId) =>
        Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);
}
