namespace Gainer.Core.Integrations;

/// <summary>Connection state shown in the app; never carries tokens.</summary>
public sealed record StravaStatus(
    bool Configured,
    bool Connected,
    bool NeedsReconnect,
    string? AthleteName,
    bool ExportCardio,
    bool ExportStrength);

public sealed record StravaExportState(
    StravaExportKind Kind,
    Guid ResourceId,
    StravaExportStatus Status,
    long? ActivityId,
    string? LastErrorCode,
    DateTime UpdatedAtUtc);

/// <summary>Outcome of the Strava redirect; the app receives it as <c>result</c>.</summary>
public enum StravaAuthorizationResult
{
    Connected,

    /// <summary>The user declined or removed the upload permission.</summary>
    Denied,
    Failed,
}

/// <summary>Strava features of the signed-in user.</summary>
public interface IStravaIntegrationService
{
    Task<StravaStatus> GetStatusAsync(CancellationToken cancellationToken = default);

    /// <summary>Returns the Strava consent URL with a protected, single-use state for the current user.</summary>
    string BeginAuthorization(string callbackUrl);

    /// <summary>Handles the anonymous redirect; the user comes from the protected state.</summary>
    Task<StravaAuthorizationResult> CompleteAuthorizationAsync(
        string? state,
        string? code,
        string? scope,
        string? error,
        string callbackUrl,
        CancellationToken cancellationToken = default);

    Task<StravaStatus> UpdateSettingsAsync(bool exportCardio, bool exportStrength, CancellationToken cancellationToken = default);

    Task DisconnectAsync(CancellationToken cancellationToken = default);

    /// <summary>Null when the record has no export entry for the connected athlete.</summary>
    Task<StravaExportState?> GetExportAsync(StravaExportKind kind, Guid resourceId, CancellationToken cancellationToken = default);

    /// <summary>Queues the record for export now, also when its kind is switched off.</summary>
    Task<StravaExportState> RequestExportAsync(StravaExportKind kind, Guid resourceId, CancellationToken cancellationToken = default);
}

/// <summary>Stable error codes for the app.</summary>
public sealed class StravaIntegrationException(string code, string message, int statusCode) : Exception(message)
{
    public const string NotConfigured = "strava_not_configured";
    public const string NotConnected = "strava_not_connected";
    public const string NeedsReconnect = "strava_needs_reconnect";
    public const string ResourceNotFound = "strava_resource_not_found";
    public const string ResourceNotFinished = "strava_resource_not_finished";

    public string Code { get; } = code;
    public int StatusCode { get; } = statusCode;
}
