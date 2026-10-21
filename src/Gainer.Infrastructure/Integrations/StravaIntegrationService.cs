using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Gainer.Core.Integrations;
using Gainer.Core.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Npgsql;

namespace Gainer.Infrastructure.Integrations;

public sealed class StravaIntegrationService(
    AppDbContext context,
    IUserContext userContext,
    BackgroundUserScope backgroundUser,
    IStravaApiClient strava,
    StravaTokenVault tokens,
    StravaExportSignal signal,
    IDataProtectionProvider dataProtection,
    IMemoryCache usedStates,
    IOptions<StravaOptions> options,
    TimeProvider timeProvider,
    ILogger<StravaIntegrationService> logger) : IStravaIntegrationService
{
    /// <summary>Uploads and reading the athlete's name; nothing else.</summary>
    public const string RequiredScope = "activity:write";
    private const string RequestedScope = "read,activity:write";
    private static readonly TimeSpan StateLifetime = TimeSpan.FromMinutes(10);
    private readonly StravaOptions settings = options.Value;

    private ITimeLimitedDataProtector StateProtector =>
        dataProtection.CreateProtector("Gainer.Strava.AuthorizationState.v1").ToTimeLimitedDataProtector();

    public async Task<StravaStatus> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        _ = CurrentUserId();
        StravaConnection? connection = await context.StravaConnections.SingleOrDefaultAsync(cancellationToken);
        return ToStatus(connection);
    }

    public string BeginAuthorization(string callbackUrl)
    {
        Guid userId = CurrentUserId();
        EnsureConfigured();
        string payload = JsonSerializer.Serialize(new StatePayload(userId, Convert.ToHexString(RandomNumberGenerator.GetBytes(16))));
        string state = StateProtector.Protect(payload, StateLifetime);
        var query = new Dictionary<string, string>
        {
            ["client_id"] = settings.ClientId,
            ["redirect_uri"] = callbackUrl,
            ["response_type"] = "code",
            ["approval_prompt"] = "auto",
            ["scope"] = RequestedScope,
            ["state"] = state,
        };
        string queryString = string.Join('&', query.Select(pair => $"{pair.Key}={Uri.EscapeDataString(pair.Value)}"));
        return new Uri(new Uri(settings.OAuthBaseUrl), "oauth/mobile/authorize").AbsoluteUri + "?" + queryString;
    }

    public async Task<StravaAuthorizationResult> CompleteAuthorizationAsync(
        string? state,
        string? code,
        string? scope,
        string? error,
        string callbackUrl,
        CancellationToken cancellationToken = default)
    {
        if (!settings.IsConfigured || !TryConsumeState(state, out Guid userId))
        {
            return StravaAuthorizationResult.Failed;
        }
        if (!string.IsNullOrEmpty(error) || string.IsNullOrEmpty(code))
        {
            return StravaAuthorizationResult.Denied;
        }
        string[] granted = (scope ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (!granted.Contains(RequiredScope, StringComparer.Ordinal))
        {
            return StravaAuthorizationResult.Denied;
        }

        StravaTokens issued;
        try
        {
            issued = await strava.ExchangeCodeAsync(code, cancellationToken);
        }
        catch (StravaApiException exception)
        {
            logger.LogWarning("Strava code exchange failed with {Failure} ({Status}).", exception.Failure, exception.StatusCode);
            return StravaAuthorizationResult.Failed;
        }
        if (issued.AthleteId is not { } athleteId || athleteId <= 0)
        {
            return StravaAuthorizationResult.Failed;
        }

        // The anonymous redirect carries no session; the protected state names the user.
        backgroundUser.Enter(userId);
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        StravaConnection? connection = await context.StravaConnections.SingleOrDefaultAsync(cancellationToken);
        if (connection is null)
        {
            connection = new StravaConnection
            {
                CardioExportSinceUtc = utcNow,
                ConnectedAtUtc = utcNow,
            };
            context.StravaConnections.Add(connection);
        }
        connection.AthleteId = athleteId;
        connection.AthleteName = issued.AthleteName is { Length: > 200 } name ? name[..200] : issued.AthleteName;
        connection.Scope = string.Join(',', granted);
        connection.NeedsReconnect = false;
        connection.PausedUntilUtc = null;
        connection.UpdatedAtUtc = utcNow;
        tokens.Store(connection, issued);
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            // A parallel callback of the same user stored the connection first.
            return StravaAuthorizationResult.Connected;
        }
        signal.Notify();
        return StravaAuthorizationResult.Connected;
    }

    public async Task<StravaStatus> UpdateSettingsAsync(bool exportCardio, bool exportStrength, CancellationToken cancellationToken = default)
    {
        StravaConnection connection = await RequireConnectionAsync(allowReconnect: true, cancellationToken);
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        connection.CardioExportSinceUtc = exportCardio ? connection.CardioExportSinceUtc ?? utcNow : null;
        connection.StrengthExportSinceUtc = exportStrength ? connection.StrengthExportSinceUtc ?? utcNow : null;
        connection.UpdatedAtUtc = utcNow;
        await context.SaveChangesAsync(cancellationToken);
        return ToStatus(connection);
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        _ = CurrentUserId();
        StravaConnection? connection = await context.StravaConnections.SingleOrDefaultAsync(cancellationToken);
        if (connection is null) return;
        if (tokens.CurrentAccessToken(connection) is { } accessToken)
        {
            try
            {
                await strava.DeauthorizeAsync(accessToken, cancellationToken);
            }
            catch (StravaApiException exception)
            {
                // Best effort: the tokens are deleted anyway; the user can also remove Gainer in Strava.
                logger.LogInformation("Strava deauthorization failed with {Failure}.", exception.Failure);
            }
        }
        context.StravaConnections.Remove(connection);
        await context.SaveChangesAsync(cancellationToken);
    }

    public async Task<StravaExportState?> GetExportAsync(StravaExportKind kind, Guid resourceId, CancellationToken cancellationToken = default)
    {
        _ = CurrentUserId();
        StravaConnection? connection = await context.StravaConnections.AsNoTracking().SingleOrDefaultAsync(cancellationToken);
        if (connection is null) return null;
        StravaExport? export = await context.StravaExports.AsNoTracking().SingleOrDefaultAsync(
            item => item.Kind == kind && item.ResourceId == resourceId && item.AthleteId == connection.AthleteId,
            cancellationToken);
        return export is null ? null : ToState(export);
    }

    public async Task<StravaExportState> RequestExportAsync(StravaExportKind kind, Guid resourceId, CancellationToken cancellationToken = default)
    {
        StravaConnection connection = await RequireConnectionAsync(allowReconnect: false, cancellationToken);
        await EnsureExportableAsync(kind, resourceId, cancellationToken);
        DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
        StravaExport? export = await FindExportAsync(kind, resourceId, connection.AthleteId, cancellationToken);
        if (export is null)
        {
            export = new StravaExport
            {
                Id = Guid.NewGuid(),
                Kind = kind,
                ResourceId = resourceId,
                AthleteId = connection.AthleteId,
                Status = StravaExportStatus.Pending,
                NextAttemptAtUtc = utcNow,
                CreatedAtUtc = utcNow,
                UpdatedAtUtc = utcNow,
            };
            context.StravaExports.Add(export);
        }
        else if (export.Status is StravaExportStatus.Failed or StravaExportStatus.Pending)
        {
            export.Status = StravaExportStatus.Pending;
            export.Attempts = 0;
            export.LastErrorCode = null;
            export.NextAttemptAtUtc = utcNow;
            export.UpdatedAtUtc = utcNow;
        }
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            // The worker queued the same record at the same moment.
            context.ChangeTracker.Clear();
            export = await FindExportAsync(kind, resourceId, connection.AthleteId, cancellationToken)
                ?? throw new InvalidOperationException("The export entry disappeared after a conflict.");
        }
        signal.Notify();
        return ToState(export);
    }

    private Task<StravaExport?> FindExportAsync(StravaExportKind kind, Guid resourceId, long athleteId, CancellationToken cancellationToken) =>
        context.StravaExports.SingleOrDefaultAsync(
            item => item.Kind == kind && item.ResourceId == resourceId && item.AthleteId == athleteId,
            cancellationToken);

    private async Task EnsureExportableAsync(StravaExportKind kind, Guid resourceId, CancellationToken cancellationToken)
    {
        bool exists;
        bool finished;
        if (kind == StravaExportKind.Cardio)
        {
            exists = await context.CardioSessions.AnyAsync(item => item.Id == resourceId, cancellationToken);
            finished = exists;
        }
        else
        {
            var workout = await context.Workouts
                .Where(item => item.Id == resourceId && item.DeletedAtUtc == null)
                .Select(item => new { item.EndedAtUtc })
                .SingleOrDefaultAsync(cancellationToken);
            exists = workout is not null;
            finished = workout?.EndedAtUtc is not null;
        }
        if (!exists)
        {
            throw new StravaIntegrationException(StravaIntegrationException.ResourceNotFound, "The record does not exist.", 404);
        }
        if (!finished)
        {
            throw new StravaIntegrationException(StravaIntegrationException.ResourceNotFinished, "The workout has not ended yet.", 409);
        }
    }

    private async Task<StravaConnection> RequireConnectionAsync(bool allowReconnect, CancellationToken cancellationToken)
    {
        _ = CurrentUserId();
        EnsureConfigured();
        StravaConnection connection = await context.StravaConnections.SingleOrDefaultAsync(cancellationToken)
            ?? throw new StravaIntegrationException(StravaIntegrationException.NotConnected, "Strava is not connected.", 409);
        if (!allowReconnect && connection.NeedsReconnect)
        {
            throw new StravaIntegrationException(StravaIntegrationException.NeedsReconnect, "Strava has to be connected again.", 409);
        }
        return connection;
    }

    private void EnsureConfigured()
    {
        if (!settings.IsConfigured)
        {
            throw new StravaIntegrationException(StravaIntegrationException.NotConfigured, "Strava is not configured on this server.", 503);
        }
    }

    private bool TryConsumeState(string? state, out Guid userId)
    {
        userId = Guid.Empty;
        if (string.IsNullOrEmpty(state) || state.Length > 4_000) return false;
        StatePayload? payload;
        try
        {
            payload = JsonSerializer.Deserialize<StatePayload>(StateProtector.Unprotect(state));
        }
        catch (Exception exception) when (exception is CryptographicException or JsonException or FormatException)
        {
            return false;
        }
        if (payload is null || payload.UserId == Guid.Empty) return false;

        string key = "strava-state:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(state)));
        lock (usedStates)
        {
            if (usedStates.TryGetValue(key, out _)) return false;
            usedStates.Set(key, true, StateLifetime);
        }
        userId = payload.UserId;
        return true;
    }

    private StravaStatus ToStatus(StravaConnection? connection) => new(
        settings.IsConfigured,
        connection is not null,
        connection?.NeedsReconnect ?? false,
        connection?.AthleteName,
        connection?.CardioExportSinceUtc is not null,
        connection?.StrengthExportSinceUtc is not null);

    internal static StravaExportState ToState(StravaExport export) => new(
        export.Kind,
        export.ResourceId,
        export.Status,
        export.ActivityId,
        export.LastErrorCode,
        export.UpdatedAtUtc);

    private Guid CurrentUserId() =>
        userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");

    private sealed record StatePayload(Guid UserId, string Nonce);
}
