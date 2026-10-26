using Gainer.Api.Composition;
using Gainer.Contracts.System;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Gainer.Api.Controllers;

/// <summary>
/// Exposes non-sensitive API contract metadata. Anonymous by design: clients read the contract
/// version before they sign in. The response holds no user data, and the endpoint is rate limited per client.
/// </summary>
[ApiController]
[Route(ApiConstants.Version1Route + "/system")]
[EnableRateLimiting(ApiConstants.SystemStatusRateLimitPolicy)]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class SystemController : ControllerBase
{
    /// <summary>Returns the active API contract version.</summary>
    [HttpGet("status")]
    [Produces("application/json")]
    [ProducesResponseType<SystemStatusResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status429TooManyRequests)]
    public ActionResult<SystemStatusResponse> GetStatus()
    {
        return Ok(new SystemStatusResponse("ok", "v1"));
    }
}
