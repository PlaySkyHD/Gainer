using System.Security.Claims;
using Gainer.Core.Access;
using Microsoft.AspNetCore.Authentication;

namespace Gainer.Api.Security;

/// <summary>
/// Treats access tokens whose device session was revoked, expired, or belongs to a deactivated
/// account as absent, so revocation takes effect on the next request rather than at token expiry.
/// Protected endpoints then answer 401; anonymous ones such as sign-in keep working.
/// </summary>
internal sealed class DeviceSessionValidationMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        AuthenticateResult? authentication = context.Features.Get<IAuthenticateResultFeature>()?.AuthenticateResult;
        if (authentication?.Ticket?.AuthenticationScheme == GainerIdentityOptions.AuthenticationScheme
            && !await HasActiveDeviceSessionAsync(context, authentication.Ticket.Principal))
        {
            context.User = new ClaimsPrincipal(new ClaimsIdentity());
            context.Features.Set<IAuthenticateResultFeature>(new RejectedAuthentication());
        }

        await next(context);
    }

    private static async Task<bool> HasActiveDeviceSessionAsync(HttpContext context, ClaimsPrincipal principal)
    {
        if (!Guid.TryParse(principal.FindFirstValue(GainerIdentityOptions.DeviceSessionClaimType), out Guid sessionId)
            || !Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out Guid userId))
        {
            return false;
        }

        IDeviceSessionService deviceSessions = context.RequestServices.GetRequiredService<IDeviceSessionService>();
        return await deviceSessions.IsActiveAsync(sessionId, userId, context.RequestAborted);
    }

    private sealed class RejectedAuthentication : IAuthenticateResultFeature
    {
        public AuthenticateResult? AuthenticateResult { get; set; } = AuthenticateResult.NoResult();
    }
}
