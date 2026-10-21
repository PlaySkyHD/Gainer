using Gainer.Api.Composition;
using Gainer.Contracts.Integrations;
using Gainer.Core.Integrations;
using Gainer.Infrastructure.Integrations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/integrations/strava")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class StravaController(IStravaIntegrationService strava, IOptions<StravaOptions> options) : ControllerBase
{
    public const string CallbackPath = "/" + ApiConstants.Version1Route + "/integrations/strava/callback";

    [HttpGet]
    [ProducesResponseType<StravaStatusResponse>(StatusCodes.Status200OK)]
    public async Task<ActionResult<StravaStatusResponse>> GetStatus(CancellationToken cancellationToken = default) =>
        Ok(ToResponse(await strava.GetStatusAsync(cancellationToken)));

    /// <summary>Returns the Strava consent page the app opens in a browser sheet.</summary>
    [HttpPost("authorization")]
    [ProducesResponseType<StravaAuthorizationResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status503ServiceUnavailable)]
    public ActionResult<StravaAuthorizationResponse> BeginAuthorization() =>
        Handle<StravaAuthorizationResponse>(() => Ok(new StravaAuthorizationResponse(strava.BeginAuthorization(CallbackUrl()))));

    /// <summary>Strava redirects the browser here; the user comes from the protected state.</summary>
    [HttpGet("callback")]
    [AllowAnonymous]
    [EnableRateLimiting(ApiConstants.AuthenticationRateLimitPolicy)]
    [ProducesResponseType(StatusCodes.Status302Found)]
    public async Task<IActionResult> Callback(
        [FromQuery] string? state,
        [FromQuery] string? code,
        [FromQuery] string? scope,
        [FromQuery] string? error,
        CancellationToken cancellationToken = default)
    {
        StravaAuthorizationResult result = await strava.CompleteAuthorizationAsync(
            state,
            code,
            scope,
            error,
            CallbackUrl(),
            cancellationToken);
        string value = result switch
        {
            StravaAuthorizationResult.Connected => "connected",
            StravaAuthorizationResult.Denied => "denied",
            _ => "failed",
        };
        return Redirect($"{options.Value.AppRedirectUri}?result={value}");
    }

    [HttpPut("settings")]
    [ProducesResponseType<StravaStatusResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<StravaStatusResponse>> UpdateSettings(
        [FromBody] StravaSettingsRequest request,
        CancellationToken cancellationToken = default) =>
        HandleAsync<StravaStatusResponse>(async () => Ok(ToResponse(
            await strava.UpdateSettingsAsync(request.ExportCardio, request.ExportStrength, cancellationToken))));

    [HttpDelete]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Disconnect(CancellationToken cancellationToken = default)
    {
        await strava.DisconnectAsync(cancellationToken);
        return NoContent();
    }

    [HttpGet("exports/{kind}/{resourceId:guid}")]
    [ProducesResponseType<StravaExportResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<StravaExportResponse>> GetExport(
        string kind,
        Guid resourceId,
        CancellationToken cancellationToken = default)
    {
        if (!StravaExportNames.TryParseKind(kind, out StravaExportKind exportKind)) return NotFound();
        StravaExportState? state = await strava.GetExportAsync(exportKind, resourceId, cancellationToken);
        return state is null ? NotFound() : Ok(ToResponse(state));
    }

    /// <summary>Queues one record for Strava now, also when automatic export of its kind is off.</summary>
    [HttpPost("exports/{kind}/{resourceId:guid}")]
    [ProducesResponseType<StravaExportResponse>(StatusCodes.Status202Accepted)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<StravaExportResponse>> RequestExport(
        string kind,
        Guid resourceId,
        CancellationToken cancellationToken = default) =>
        HandleAsync<StravaExportResponse>(async () =>
        {
            if (!StravaExportNames.TryParseKind(kind, out StravaExportKind exportKind)) return NotFound();
            StravaExportState state = await strava.RequestExportAsync(exportKind, resourceId, cancellationToken);
            return Accepted(ToResponse(state));
        });

    private string CallbackUrl() =>
        options.Value.CallbackUrl is { Length: > 0 } configured
            ? configured
            : $"{Request.Scheme}://{Request.Host}{Request.PathBase}{CallbackPath}";

    private ActionResult<T> Handle<T>(Func<ActionResult<T>> action)
    {
        try
        {
            return action();
        }
        catch (StravaIntegrationException exception)
        {
            return Problem(exception);
        }
    }

    private async Task<ActionResult<T>> HandleAsync<T>(Func<Task<ActionResult<T>>> action)
    {
        try
        {
            return await action();
        }
        catch (StravaIntegrationException exception)
        {
            return Problem(exception);
        }
    }

    private ObjectResult Problem(StravaIntegrationException exception)
    {
        var problem = new ProblemDetails
        {
            Status = exception.StatusCode,
            Title = "Strava request failed",
            Detail = exception.Message,
        };
        problem.Extensions["code"] = exception.Code;
        return StatusCode(exception.StatusCode, problem);
    }

    private static StravaStatusResponse ToResponse(StravaStatus status) => new(
        status.Configured,
        status.Connected,
        status.NeedsReconnect,
        status.AthleteName,
        status.ExportCardio,
        status.ExportStrength);

    private static StravaExportResponse ToResponse(StravaExportState state) => new(
        StravaExportNames.ToWire(state.Kind),
        state.ResourceId,
        StravaExportNames.ToWire(state.Status),
        state.ActivityId,
        state.LastErrorCode,
        state.UpdatedAtUtc);
}
