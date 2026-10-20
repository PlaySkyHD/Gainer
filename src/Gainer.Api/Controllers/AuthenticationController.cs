using System.Security.Claims;
using Gainer.Api.Composition;
using Gainer.Api.Errors;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Core.Access;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Gainer.Api.Controllers;

/// <summary>Manages device sessions for privately provisioned accounts.</summary>
[ApiController]
[Route(ApiConstants.Version1Route + "/auth")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class AuthenticationController(
    SignInManager<AppUser> signInManager,
    UserManager<AppUser> userManager,
    IDeviceSessionService deviceSessions,
    DeviceSignIn deviceSignIn) : ControllerBase
{
    /// <summary>Starts a device session for valid existing credentials.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [HttpPost("login")]
    [ProducesResponseType<TokenResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status401Unauthorized, "application/problem+json")]
    public async Task<ActionResult<TokenResponse>> Login(LoginRequest request, CancellationToken cancellationToken)
    {
        AppUser? user = await userManager.FindByNameAsync(request.Email.Trim());
        if (user is null)
        {
            return Failure("invalid_credentials");
        }

        Microsoft.AspNetCore.Identity.SignInResult result = await signInManager.CheckPasswordSignInAsync(
            user,
            request.Password,
            lockoutOnFailure: true);
        if (!result.Succeeded)
        {
            return Failure("invalid_credentials");
        }

        return Ok(await deviceSignIn.StartAsync(user, request.DeviceName, cancellationToken));
    }

    /// <summary>Rotates the refresh token of a device session and issues a new access token.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [HttpPost("refresh")]
    [ProducesResponseType<TokenResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status401Unauthorized, "application/problem+json")]
    public async Task<ActionResult<TokenResponse>> Refresh(
        RefreshTokenRequest request,
        CancellationToken cancellationToken)
    {
        DeviceSessionRefreshResult result = await deviceSessions.RefreshAsync(request.RefreshToken, cancellationToken);
        if (result is not { Status: DeviceSessionRefreshStatus.Refreshed, Session: IssuedDeviceSession session })
        {
            return Failure("invalid_refresh_token");
        }

        AppUser? user = await userManager.FindByIdAsync(session.UserId.ToString());
        if (user is null)
        {
            return Failure("invalid_refresh_token");
        }

        return Ok(await deviceSignIn.TokensAsync(user, session));
    }

    /// <summary>Returns the currently authenticated account.</summary>
    [Authorize]
    [HttpGet("session")]
    [ProducesResponseType<SessionResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status401Unauthorized, "application/problem+json")]
    public async Task<ActionResult<SessionResponse>> GetSession()
    {
        AppUser? user = await userManager.GetUserAsync(User);
        if (user is null)
        {
            return Unauthorized();
        }

        string email = user.Email ?? user.UserName
            ?? throw new InvalidOperationException("An authenticated user has no account identifier.");
        bool isAccountOperator = await userManager.IsInRoleAsync(
            user,
            AccountOperatorAuthorization.RoleName);
        return Ok(new SessionResponse(user.Id, email, isAccountOperator));
    }

    /// <summary>Revokes the current device session.</summary>
    [Authorize]
    [HttpPost("logout")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status401Unauthorized, "application/problem+json")]
    public async Task<IActionResult> Logout(CancellationToken cancellationToken)
    {
        if (Guid.TryParse(User.FindFirstValue(GainerIdentityOptions.DeviceSessionClaimType), out Guid sessionId)
            && Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out Guid userId))
        {
            await deviceSessions.RevokeAsync(sessionId, userId, cancellationToken);
        }

        return NoContent();
    }

    private ObjectResult Failure(string code) => AuthenticationProblems.Unauthorized(HttpContext, code);
}
