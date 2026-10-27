using Gainer.Core.Security;

namespace Gainer.Core.Integrations;

/// <summary>The Strava account a user connected, with encrypted tokens and export settings.</summary>
public sealed class StravaConnection : UserOwnedEntity
{
    public long AthleteId { get; set; }
    public string? AthleteName { get; set; }
    public string Scope { get; set; } = string.Empty;

    /// <summary>Data-protected access and refresh tokens; never sent to clients.</summary>
    public string ProtectedAccessToken { get; set; } = string.Empty;
    public string ProtectedRefreshToken { get; set; } = string.Empty;
    public DateTime AccessTokenExpiresAtUtc { get; set; }

    /// <summary>When cardio export was switched on; null while it is off.</summary>
    public DateTime? CardioExportSinceUtc { get; set; }

    /// <summary>When strength export was switched on; null while it is off.</summary>
    public DateTime? StrengthExportSinceUtc { get; set; }

    /// <summary>Strava rejected the tokens; exports wait until the user connects again.</summary>
    public bool NeedsReconnect { get; set; }

    /// <summary>Strava rate-limited this user; no request before this time.</summary>
    public DateTime? PausedUntilUtc { get; set; }
    public DateTime ConnectedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
}

/// <summary>What kind of Gainer record an export carries.</summary>
public enum StravaExportKind
{
    Cardio,
    Strength,
}

public enum StravaExportStatus
{
    /// <summary>Waiting to be sent; <see cref="StravaExport.NextAttemptAtUtc" /> says when.</summary>
    Pending,

    /// <summary>Uploaded; Strava is still processing the file.</summary>
    Processing,
    Completed,

    /// <summary>Given up; a manual request queues it again.</summary>
    Failed,
}

/// <summary>Ledger entry: at most one Strava activity per record and athlete.</summary>
public sealed class StravaExport : UserOwnedEntity
{
    public Guid Id { get; init; }
    public StravaExportKind Kind { get; init; }
    public Guid ResourceId { get; init; }
    public long AthleteId { get; init; }
    public StravaExportStatus Status { get; set; }
    public long? UploadId { get; set; }
    public long? ActivityId { get; set; }
    public int Attempts { get; set; }
    public DateTime NextAttemptAtUtc { get; set; }
    public string? LastErrorCode { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
}

/// <summary>Stable string values of export kinds and states in the HTTP contract.</summary>
public static class StravaExportNames
{
    public static string ToWire(StravaExportKind kind) => kind switch
    {
        StravaExportKind.Cardio => "cardio",
        StravaExportKind.Strength => "strength",
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unknown export kind."),
    };

    public static string ToWire(StravaExportStatus status) => status switch
    {
        StravaExportStatus.Pending => "pending",
        StravaExportStatus.Processing => "processing",
        StravaExportStatus.Completed => "completed",
        StravaExportStatus.Failed => "failed",
        _ => throw new ArgumentOutOfRangeException(nameof(status), status, "Unknown export status."),
    };

    public static bool TryParseKind(string? value, out StravaExportKind kind)
    {
        switch (value)
        {
            case "cardio":
                kind = StravaExportKind.Cardio;
                return true;
            case "strength":
                kind = StravaExportKind.Strength;
                return true;
            default:
                kind = default;
                return false;
        }
    }
}
