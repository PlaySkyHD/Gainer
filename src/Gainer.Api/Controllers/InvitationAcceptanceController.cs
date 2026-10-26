using Gainer.Api.Composition;
using Gainer.Api.Errors;
using Gainer.Contracts.Security;
using Gainer.Core.Access;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Gainer.Api.Controllers;

/// <summary>Activates a pending account through a single-use invitation.</summary>
[ApiController]
[AllowAnonymous]
[Route(ApiConstants.Version1Route + "/auth/invitations")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class InvitationAcceptanceController(IAccountInvitationService invitations) : ControllerBase
{
    /// <summary>Consumes an invitation and sets the invited account's initial password.</summary>
    [HttpPost("accept")]
    [EnableRateLimiting(ApiConstants.InvitationAcceptRateLimitPolicy)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest, "application/problem+json")]
    public async Task<IActionResult> Accept(
        AcceptInvitationRequest request,
        CancellationToken cancellationToken)
    {
        AccountInvitationAcceptanceResult result = await invitations.AcceptAsync(
            request.Token,
            request.Password,
            cancellationToken);
        if (result == AccountInvitationAcceptanceResult.Accepted)
        {
            return NoContent();
        }

        return InvalidInvitation(result);
    }

    private ObjectResult InvalidInvitation(AccountInvitationAcceptanceResult result)
    {
        var problem = new ProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Title = result == AccountInvitationAcceptanceResult.InvalidPassword
                ? "The password does not meet the account requirements."
                : "The invitation is invalid.",
            Type = ProblemDetailsConfiguration.GetTypeUri(StatusCodes.Status400BadRequest),
        };
        ProblemDetailsConfiguration.AddStableExtensions(HttpContext, problem);
        problem.Extensions["code"] = result == AccountInvitationAcceptanceResult.InvalidPassword
            ? "password_invalid"
            : "invalid_invitation";
        return new ObjectResult(problem)
        {
            StatusCode = StatusCodes.Status400BadRequest,
            ContentTypes = { "application/problem+json" },
        };
    }
}
