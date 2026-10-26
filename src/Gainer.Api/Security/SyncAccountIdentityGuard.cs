using Gainer.Api.Controllers;
using Gainer.Contracts.Sync;
using Gainer.Core.Security;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Security;

/// <summary>
/// Binds a scoped sync request to the account the client expects. Clients that declare
/// <see cref="SyncProtocol.AccountHeaderRequiredVersion"/> or newer must send the header;
/// older or unversioned clients may omit it. When present it is checked against the
/// authenticated identity attached to this same HTTP request.
/// </summary>
internal static class SyncAccountIdentityGuard
{
    internal const string HeaderName = "X-Gainer-Account-Id";

    internal static ObjectResult? Validate(
        HttpContext httpContext,
        IUserContext userContext,
        int? clientProtocolVersion = null)
    {
        if (!httpContext.Request.Headers.TryGetValue(HeaderName, out var values))
        {
            return clientProtocolVersion >= SyncProtocol.AccountHeaderRequiredVersion
                ? SyncProblemResults.Create(
                    httpContext,
                    StatusCodes.Status422UnprocessableEntity,
                    "account_header_required",
                    "The account header is required for this protocol version.")
                : null;
        }

        string? value = values.Count == 1 ? values[0] : null;
        if (!Guid.TryParseExact(value, "D", out Guid expectedUserId) ||
            expectedUserId == Guid.Empty ||
            userContext.UserId is not Guid authenticatedUserId ||
            authenticatedUserId != expectedUserId)
        {
            return SyncProblemResults.Create(
                httpContext,
                StatusCodes.Status409Conflict,
                "account_changed",
                "The authenticated account does not match this sync profile.");
        }

        return null;
    }
}
