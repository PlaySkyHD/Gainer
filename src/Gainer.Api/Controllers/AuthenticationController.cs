using Gainer.Api.Composition;
using Gainer.Api.Errors;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

/// <summary>Manages sessions for privately provisioned accounts.</summary>
[ApiController]
[Route(ApiConstants.Version1Route + "/auth")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class AuthenticationController(
    SignInManager<AppUser> signInManager,
    UserManager<AppUser> userManager) : ControllerBase
{
    /// <summary>Creates a browser session for valid existing credentials.</summary>
    [AllowAnonymous]
    [HttpPost("login")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status401Unauthorized, "application/problem+json")]
    public async Task<IActionResult> Login(LoginRequest request)
    {
        Microsoft.AspNetCore.Identity.SignInResult result = await signInManager.PasswordSignInAsync(
            request.Email.Trim(),
            request.Password,
            isPersistent: false,
            lockoutOnFailure: true);

        if (!result.Succeeded)
        {
            return InvalidCredentials();
        }

        return NoContent();
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

    /// <summary>Invalidates the current browser session.</summary>
    [Authorize]
    [HttpPost("logout")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status401Unauthorized, "application/problem+json")]
    public async Task<IActionResult> Logout()
    {
        await signInManager.SignOutAsync();
        return NoContent();
    }

    private ObjectResult InvalidCredentials()
    {
        var problemDetails = new ProblemDetails
        {
            Status = StatusCodes.Status401Unauthorized,
            Title = "Authentication failed.",
            Type = ProblemDetailsConfiguration.GetTypeUri(StatusCodes.Status401Unauthorized),
        };
        ProblemDetailsConfiguration.AddStableExtensions(HttpContext, problemDetails);
        problemDetails.Extensions["code"] = "invalid_credentials";

        return new ObjectResult(problemDetails)
        {
            StatusCode = StatusCodes.Status401Unauthorized,
            ContentTypes = { "application/problem+json" },
        };
    }
}
