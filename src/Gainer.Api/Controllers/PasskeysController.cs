using Gainer.Api.Composition;
using Gainer.Api.Errors;
using Gainer.Api.Security;
using System.Security.Claims;
using Gainer.Contracts.Security;
using Gainer.Core.Access;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.WebUtilities;

namespace Gainer.Api.Controllers;

/// <summary>Registers passkeys for signed-in accounts and signs devices in with them.</summary>
[ApiController]
[Route(ApiConstants.Version1Route + "/auth/passkeys")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class PasskeysController(
    IPasskeyHandler<AppUser> passkeys,
    PasskeyCeremonyProtector ceremonies,
    SignInManager<AppUser> signInManager,
    UserManager<AppUser> userManager,
    DeviceSignIn deviceSignIn,
    IDeviceSessionService deviceSessions,
    TimeProvider timeProvider) : ControllerBase
{
    private const string DefaultPasskeyName = "iPhone";

    /// <summary>How long after signing in a passkey can be added without entering the password again.</summary>
    public static readonly TimeSpan RecentSignInWindow = TimeSpan.FromMinutes(5);

    /// <summary>Lists the passkeys of the signed-in account.</summary>
    [Authorize]
    [HttpGet]
    [ProducesResponseType<IReadOnlyList<PasskeySummaryResponse>>(StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<PasskeySummaryResponse>>> List()
    {
        AppUser? user = await userManager.GetUserAsync(User);
        if (user is null)
        {
            return Unauthorized();
        }

        IList<UserPasskeyInfo> stored = await userManager.GetPasskeysAsync(user);
        return Ok(stored
            .OrderBy(passkey => passkey.CreatedAt)
            .Select(Summary)
            .ToList());
    }

    /// <summary>Starts creating a passkey for the signed-in account.</summary>
    [Authorize]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [HttpPost("creation-options")]
    [ProducesResponseType<PasskeyOptionsResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status403Forbidden, "application/problem+json")]
    public async Task<ActionResult<PasskeyOptionsResponse>> CreationOptions(
        [FromBody(EmptyBodyBehavior = EmptyBodyBehavior.Allow)] PasskeyCreationOptionsRequest? request,
        CancellationToken cancellationToken)
    {
        AppUser? user = await userManager.GetUserAsync(User);
        if (user is null)
        {
            return Unauthorized();
        }

        // A passkey outlives every device session, so a stolen access token alone must not add one.
        if (!await SignedInRecentlyAsync(user, cancellationToken)
            && (string.IsNullOrEmpty(request?.Password)
                || !(await signInManager.CheckPasswordSignInAsync(user, request.Password, lockoutOnFailure: true)).Succeeded))
        {
            return AuthenticationProblems.Forbidden(
                HttpContext,
                "Confirm your password to add a passkey.",
                "reauthentication_required");
        }

        string name = user.Email ?? user.UserName ?? user.Id.ToString();
        PasskeyCreationOptionsResult options = await passkeys.MakeCreationOptionsAsync(
            new PasskeyUserEntity { Id = user.Id.ToString(), Name = name, DisplayName = name },
            HttpContext);
        return Ok(new PasskeyOptionsResponse(
            options.CreationOptionsJson,
            ceremonies.Protect(PasskeyCeremony.Registration, user.Id, options.AttestationState ?? string.Empty)));
    }

    /// <summary>Stores the passkey the authenticator created.</summary>
    [Authorize]
    [HttpPost]
    [ProducesResponseType<PasskeySummaryResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest, "application/problem+json")]
    public async Task<ActionResult<PasskeySummaryResponse>> Register(RegisterPasskeyRequest request)
    {
        AppUser? user = await userManager.GetUserAsync(User);
        if (user is null)
        {
            return Unauthorized();
        }

        if (!ceremonies.TryConsume(PasskeyCeremony.Registration, user.Id, request.State, out string state))
        {
            return Rejected();
        }

        PasskeyAttestationResult attestation = await passkeys.PerformAttestationAsync(new PasskeyAttestationContext
        {
            HttpContext = HttpContext,
            CredentialJson = request.CredentialJson,
            AttestationState = state,
        });
        if (!attestation.Succeeded || attestation.UserEntity.Id != user.Id.ToString())
        {
            return Rejected();
        }

        UserPasskeyInfo passkey = attestation.Passkey;
        passkey.Name = string.IsNullOrWhiteSpace(request.Name) ? DefaultPasskeyName : request.Name.Trim();
        IdentityResult stored = await userManager.AddOrUpdatePasskeyAsync(user, passkey);
        if (!stored.Succeeded)
        {
            return Rejected();
        }

        PasskeySummaryResponse summary = Summary(passkey);
        return Created($"/{ApiConstants.Version1Route}/auth/passkeys/{summary.Id}", summary);
    }

    /// <summary>Removes one passkey of the signed-in account.</summary>
    [Authorize]
    [HttpDelete("{id}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete(string id)
    {
        AppUser? user = await userManager.GetUserAsync(User);
        if (user is null)
        {
            return Unauthorized();
        }

        byte[] credentialId;
        try
        {
            credentialId = WebEncoders.Base64UrlDecode(id);
        }
        catch (FormatException)
        {
            return NotFound();
        }

        if (await userManager.GetPasskeyAsync(user, credentialId) is null)
        {
            return NotFound();
        }

        IdentityResult removed = await userManager.RemovePasskeyAsync(user, credentialId);
        return removed.Succeeded ? NoContent() : NotFound();
    }

    /// <summary>Starts a passkey sign-in; any passkey of this server may answer.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [HttpPost("request-options")]
    [ProducesResponseType<PasskeyOptionsResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<PasskeyOptionsResponse>> RequestOptions()
    {
        PasskeyRequestOptionsResult options = await passkeys.MakeRequestOptionsAsync(null, HttpContext);
        return Ok(new PasskeyOptionsResponse(
            options.RequestOptionsJson,
            ceremonies.Protect(PasskeyCeremony.SignIn, null, options.AssertionState ?? string.Empty)));
    }

    /// <summary>Verifies a passkey assertion and starts a device session.</summary>
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [HttpPost("login")]
    [ProducesResponseType<TokenResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status401Unauthorized, "application/problem+json")]
    public async Task<ActionResult<TokenResponse>> Login(PasskeyLoginRequest request, CancellationToken cancellationToken)
    {
        if (!ceremonies.TryConsume(PasskeyCeremony.SignIn, null, request.State, out string state))
        {
            return InvalidPasskey();
        }

        PasskeyAssertionResult<AppUser> assertion = await passkeys.PerformAssertionAsync(new PasskeyAssertionContext
        {
            HttpContext = HttpContext,
            CredentialJson = request.CredentialJson,
            AssertionState = state,
        });
        // The password lockout is deliberately not applied: a passkey cannot be guessed, and
        // honouring it would let anyone who knows the email address block passkey sign-in.
        if (!assertion.Succeeded || !await signInManager.CanSignInAsync(assertion.User))
        {
            return InvalidPasskey();
        }

        // Keeps the signature counter and backup flags current.
        await userManager.AddOrUpdatePasskeyAsync(assertion.User, assertion.Passkey);
        return Ok(await deviceSignIn.StartAsync(assertion.User, request.DeviceName, cancellationToken));
    }

    private async Task<bool> SignedInRecentlyAsync(AppUser user, CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(User.FindFirstValue(GainerIdentityOptions.DeviceSessionClaimType), out Guid sessionId))
        {
            return false;
        }

        DateTimeOffset? signedInAt = await deviceSessions.GetSignedInAtAsync(sessionId, user.Id, cancellationToken);
        return signedInAt is DateTimeOffset at && timeProvider.GetUtcNow() - at <= RecentSignInWindow;
    }

    private static PasskeySummaryResponse Summary(UserPasskeyInfo passkey) => new(
        WebEncoders.Base64UrlEncode(passkey.CredentialId),
        passkey.Name ?? DefaultPasskeyName,
        passkey.CreatedAt);

    private ObjectResult Rejected() =>
        AuthenticationProblems.BadRequest(HttpContext, "The passkey could not be registered.", "passkey_rejected");

    private ObjectResult InvalidPasskey() => AuthenticationProblems.Unauthorized(HttpContext, "invalid_passkey");
}
