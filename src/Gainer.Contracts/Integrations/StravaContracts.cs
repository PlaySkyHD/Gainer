namespace Gainer.Contracts.Integrations;

/// <summary>Strava connection of the signed-in user; never contains tokens.</summary>
public sealed record StravaStatusResponse(
    bool Configured,
    bool Connected,
    bool NeedsReconnect,
    string? AthleteName,
    bool ExportCardio,
    bool ExportStrength);

public sealed record StravaAuthorizationResponse(string AuthorizationUrl);

public sealed record StravaSettingsRequest(bool ExportCardio, bool ExportStrength);

/// <summary><c>kind</c> is <c>cardio</c> or <c>strength</c>; <c>status</c> is <c>pending</c>, <c>processing</c>, <c>completed</c> or <c>failed</c>.</summary>
public sealed record StravaExportResponse(
    string Kind,
    Guid ResourceId,
    string Status,
    long? ActivityId,
    string? ErrorCode,
    DateTime UpdatedAtUtc);
