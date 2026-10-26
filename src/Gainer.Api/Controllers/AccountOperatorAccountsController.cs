using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Core.Access;
using Gainer.Core.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

/// <summary>Manages account availability without exposing fitness data.</summary>
[ApiController]
[Authorize(Policy = AccountOperatorAuthorization.PolicyName)]
[Route(ApiConstants.Version1Route + "/account-operator/accounts")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class AccountOperatorAccountsController(
    IAccountStatusService accounts,
    IAccountDirectoryService directory,
    IUserContext userContext) : ControllerBase
{
    /// <summary>Lists only the Identity metadata required for account management.</summary>
    [HttpGet]
    [ProducesResponseType<IReadOnlyList<AccountSummaryResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<AccountSummaryResponse>>> List(
        CancellationToken cancellationToken)
    {
        IReadOnlyList<AccountIdentitySummary> items = await directory.ListAsync(cancellationToken);
        return Ok(items.Select(item => new AccountSummaryResponse(
            item.AccountId,
            item.Email,
            item.IsActive)));
    }

    /// <summary>Activates or deactivates an account and revokes its existing sessions.</summary>
    [HttpPut("{accountId:guid}/status")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound, "application/problem+json")]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict, "application/problem+json")]
    public async Task<IActionResult> SetStatus(
        Guid accountId,
        SetAccountStatusRequest request,
        CancellationToken cancellationToken)
    {
        // An operator who deactivates their own account would lock out the only operator.
        if (!request.IsActive && userContext.UserId == accountId)
        {
            return SyncProblemResults.Create(
                HttpContext,
                StatusCodes.Status409Conflict,
                "operator_self_deactivation",
                "An operator cannot deactivate their own account.");
        }

        bool found = await accounts.SetActiveAsync(accountId, request.IsActive, cancellationToken);
        return found ? NoContent() : NotFound();
    }
}
