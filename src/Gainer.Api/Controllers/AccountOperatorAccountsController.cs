using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Core.Access;
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
    IAccountDirectoryService directory) : ControllerBase
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
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> SetStatus(
        Guid accountId,
        SetAccountStatusRequest request)
    {
        bool found = await accounts.SetActiveAsync(accountId, request.IsActive);
        return found ? NoContent() : NotFound();
    }
}
