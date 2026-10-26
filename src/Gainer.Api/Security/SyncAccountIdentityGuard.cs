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
        IHeaderDictionary headers,
        IUserContext userContext,
        int? clientProtocolVersion = null)
    {
        if (!headers.TryGetValue(HeaderName, out var values))
        {
            if (clientProtocolVersion >= SyncProtocol.AccountHeaderRequiredVersion)
            {
                var missing = new ProblemDetails
                {
                    Status = StatusCodes.Status422UnprocessableEntity,
                    Title = "The account header is required for this protocol version.",
                    Type = "https://gainer.local/problems/account_header_required",
                };
                missing.Extensions["code"] = "account_header_required";
                return new ObjectResult(missing)
                {
                    StatusCode = StatusCodes.Status422UnprocessableEntity,
                    ContentTypes = { "application/problem+json" },
                };
            }

            return null;
        }

        string? value = values.Count == 1 ? values[0] : null;
        if (!Guid.TryParseExact(value, "D", out Guid expectedUserId) ||
            expectedUserId == Guid.Empty ||
            userContext.UserId is not Guid authenticatedUserId ||
            authenticatedUserId != expectedUserId)
        {
            var problem = new ProblemDetails
            {
                Status = StatusCodes.Status409Conflict,
                Title = "The authenticated account does not match this sync profile.",
                Type = "https://gainer.local/problems/account_changed",
            };
            problem.Extensions["code"] = "account_changed";
            return new ObjectResult(problem)
            {
                StatusCode = StatusCodes.Status409Conflict,
                ContentTypes = { "application/problem+json" },
            };
        }

        return null;
    }
}
