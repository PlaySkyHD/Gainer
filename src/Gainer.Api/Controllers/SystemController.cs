using Gainer.Api.Composition;
using Gainer.Contracts.System;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

/// <summary>Exposes non-sensitive API contract metadata.</summary>
[ApiController]
[Route(ApiConstants.Version1Route + "/system")]
public sealed class SystemController : ControllerBase
{
    /// <summary>Returns the active API contract version.</summary>
    [HttpGet("status")]
    [Produces("application/json")]
    [ProducesResponseType<SystemStatusResponse>(StatusCodes.Status200OK)]
    public ActionResult<SystemStatusResponse> GetStatus()
    {
        return Ok(new SystemStatusResponse("ok", "v1"));
    }
}
