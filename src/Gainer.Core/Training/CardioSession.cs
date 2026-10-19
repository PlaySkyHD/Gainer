using Gainer.Core.Security;

namespace Gainer.Core.Training;

/// <summary>Known cardio activity types; stored as the exact string values below.</summary>
public static class CardioActivityTypes
{
    public const string IndoorCycling = "IndoorCycling";

    public static IReadOnlyList<string> Known { get; } = [IndoorCycling];

    public static bool IsKnown(string? value) => value is not null && Known.Contains(value, StringComparer.Ordinal);
}

/// <summary>One recorded cardio session with a heart rate time series.</summary>
public sealed class CardioSession : UserOwnedEntity
{
    public Guid Id { get; init; }
    public string ActivityType { get; set; } = CardioActivityTypes.IndoorCycling;
    public DateTime StartedAtUtc { get; set; }
    public DateTime EndedAtUtc { get; set; }
    public int? TargetZoneLowBpm { get; set; }
    public int? TargetZoneHighBpm { get; set; }
    public int SampleIntervalSeconds { get; set; }

    /// <summary>One value per sample interval; 0 means no signal.</summary>
    public int[] HeartRateBpm { get; set; } = [];
    public int[] RrIntervalsMs { get; set; } = [];
    public string? SensorName { get; set; }
    public decimal? DistanceKm { get; set; }
    public decimal? AveragePowerWatts { get; set; }
    public decimal? EnergyKcal { get; set; }
    public string? Notes { get; set; }
    public int? RecoveryStartBpm { get; set; }
    public int? RecoveryEndBpm { get; set; }
    public string? TemplateName { get; set; }

    /// <summary>Planned phases of a guided session; stored as jsonb. Null when the session was free.</summary>
    public IReadOnlyList<CardioPhaseValues>? Phases { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}
