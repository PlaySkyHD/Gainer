using System.Security.Claims;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.BearerToken;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;

namespace Gainer.Api.Security;

/// <summary>Creates short-lived bearer access tokens bound to one device session.</summary>
public sealed class AccessTokenIssuer(
    SignInManager<AppUser> signInManager,
    IOptionsMonitor<BearerTokenOptions> bearerOptions,
    TimeProvider timeProvider)
{
    /// <summary>Issues a token for the user's current roles and the given device session.</summary>
    public async Task<string> IssueAsync(AppUser user, Guid deviceSessionId)
    {
        ClaimsPrincipal principal = await signInManager.CreateUserPrincipalAsync(user);
        var identity = (ClaimsIdentity)principal.Identity!;
        identity.AddClaim(new Claim(GainerIdentityOptions.DeviceSessionClaimType, deviceSessionId.ToString("D")));

        BearerTokenOptions options = bearerOptions.Get(GainerIdentityOptions.AuthenticationScheme);
        DateTimeOffset now = timeProvider.GetUtcNow();
        var properties = new AuthenticationProperties
        {
            IssuedUtc = now,
            ExpiresUtc = now + options.BearerTokenExpiration,
        };
        var ticket = new AuthenticationTicket(principal, properties, GainerIdentityOptions.AuthenticationScheme);
        return options.BearerTokenProtector.Protect(ticket);
    }

    /// <summary>Lifetime of issued tokens in seconds.</summary>
    public int LifetimeSeconds =>
        (int)bearerOptions.Get(GainerIdentityOptions.AuthenticationScheme).BearerTokenExpiration.TotalSeconds;
}
