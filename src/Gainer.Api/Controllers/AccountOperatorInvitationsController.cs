using Gainer.Api.Composition;
using Gainer.Api.Errors;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Core.Access;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

/// <summary>Creates identity-only invitations for manual sharing.</summary>
[ApiController]
[Authorize(Policy = AccountOperatorAuthorization.PolicyName)]
[Route(ApiConstants.Version1Route + "/account-operator/invitations")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class AccountOperatorInvitationsController(IAccountInvitationService invitations) : ControllerBase
{
    /// <summary>Creates or replaces a pending invitation and returns its activation path once.</summary>
    [HttpPost]
    [ProducesResponseType<InvitationResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict, "application/problem+json")]
    public async Task<ActionResult<InvitationResponse>> Create(
        CreateInvitationRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            IssuedAccountInvitation issued = await invitations.IssueAsync(request.Email, cancellationToken);
            string path = $"/accept-invitation?token={Uri.EscapeDataString(issued.Token)}";
            return StatusCode(StatusCodes.Status201Created, new InvitationResponse(path, issued.ExpiresAt));
        }
        catch (AccountInvitationCannotBeIssuedException)
        {
            var problem = new ProblemDetails
            {
                Status = StatusCodes.Status409Conflict,
                Title = "The invitation cannot be issued.",
                Type = ProblemDetailsConfiguration.GetTypeUri(StatusCodes.Status409Conflict),
            };
            ProblemDetailsConfiguration.AddStableExtensions(HttpContext, problem);
            problem.Extensions["code"] = "invitation_cannot_be_issued";
            return new ObjectResult(problem)
            {
                StatusCode = StatusCodes.Status409Conflict,
                ContentTypes = { "application/problem+json" },
            };
        }
    }
}
