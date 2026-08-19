using Gainer.Api.Composition;
using Gainer.Contracts.Security;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

/// <summary>Bootstraps the double-token protection used by browser mutations.</summary>
[ApiController]
[Route(ApiConstants.Version1Route + "/auth/antiforgery")]
public sealed class RequestSecurityController(IAntiforgery antiforgery) : ControllerBase
{
    /// <summary>Issues a request token and its paired host-only cookie.</summary>
    [HttpGet]
    [ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
    [ProducesResponseType<AntiforgeryTokenResponse>(StatusCodes.Status200OK)]
    public ActionResult<AntiforgeryTokenResponse> GetToken()
    {
        AntiforgeryTokenSet tokens = antiforgery.GetAndStoreTokens(HttpContext);
        string requestToken = tokens.RequestToken
            ?? throw new InvalidOperationException("The antiforgery system did not issue a request token.");
        return Ok(new AntiforgeryTokenResponse(requestToken));
    }
}
