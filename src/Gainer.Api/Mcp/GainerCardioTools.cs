using System.ComponentModel;
using Gainer.Core.Training;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace Gainer.Api.Mcp;

/// <summary>Recorded cardio sessions with their heart rate data.</summary>
[McpServerToolType]
public sealed class GainerCardioTools(ICardioSessionQueries cardio, TimeProvider timeProvider)
{
    private const int MaximumCardioDays = 366;

    [McpServerTool(Name = "list_cardio_sessions", Title = "Cardio-Einheiten", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("Cardio sessions that started on a range of local days, newest first: activity type, name of the " +
        "guided template (null for free sessions), start, end, duration in minutes, average and maximum heart rate " +
        "in bpm (from the recorded series, null without signal), distance in km, average power in watts, energy in " +
        "kcal and note. Defaults to the last 30 days; at most 366 days. Use get_cardio_session for the series.")]
    public async Task<CardioSessionListResult> ListCardioSessions(
        [Description("First local day (YYYY-MM-DD); default 30 days before through.")] DateOnly? from = null,
        [Description("Last local day (YYYY-MM-DD); default today.")] DateOnly? through = null,
        CancellationToken cancellationToken = default)
    {
        (DateOnly start, DateOnly end) = McpDates.Range(timeProvider, from, through, 30, MaximumCardioDays);
        IReadOnlyList<CardioSessionSummary> sessions = await cardio.ListAsync(start, end, McpDates.TimeZone, cancellationToken);
        return new CardioSessionListResult(start, end, sessions
            .Select(item => new CardioSessionListItemResult(
                item.SessionId,
                item.ActivityType,
                item.TemplateName,
                item.StartedAtUtc,
                item.EndedAtUtc,
                Minutes(item.StartedAtUtc, item.EndedAtUtc),
                item.AverageHeartRateBpm,
                item.MaxHeartRateBpm,
                item.DistanceKm,
                item.AveragePowerWatts,
                item.EnergyKcal,
                item.Notes))
            .ToList());
    }

    [McpServerTool(Name = "get_cardio_session", Title = "Cardio-Einheit", ReadOnly = true, Idempotent = true,
        OpenWorld = false, UseStructuredContent = true)]
    [Description("One cardio session in full: the fields of list_cardio_sessions plus the target heart rate zone, " +
        "the heart rate series in bpm (one value per sampleIntervalSeconds from the start; 0 means no signal), the " +
        "RR intervals in ms as recorded, the sensor name, the planned phases of a guided session (offset and " +
        "duration in seconds, name, zone) and the recovery heart rate at the end and one minute later.")]
    public async Task<CardioSessionResult> GetCardioSession(
        [Description("ID of the session from list_cardio_sessions.")] Guid sessionId,
        CancellationToken cancellationToken = default)
    {
        CardioSessionSnapshot session = await cardio.GetAsync(sessionId, cancellationToken)
            ?? throw new McpException("The cardio session was not found.");
        return new CardioSessionResult(
            session.SessionId,
            session.ActivityType,
            session.TemplateName,
            session.StartedAtUtc,
            session.EndedAtUtc,
            Minutes(session.StartedAtUtc, session.EndedAtUtc),
            CardioHeartRate.Average(session.HeartRateBpm),
            CardioHeartRate.Maximum(session.HeartRateBpm),
            session.DistanceKm,
            session.AveragePowerWatts,
            session.EnergyKcal,
            session.Notes,
            session.TargetZone is { } zone ? new CardioZoneResult(zone.LowBpm, zone.HighBpm) : null,
            session.SampleIntervalSeconds,
            session.HeartRateBpm,
            session.RrIntervalsMs,
            session.SensorName,
            (session.Phases ?? [])
                .Select(phase => new CardioPhaseResult(
                    phase.StartOffsetSeconds, phase.DurationSeconds, phase.Name, phase.LowBpm, phase.HighBpm))
                .ToList(),
            session.RecoveryStartBpm,
            session.RecoveryEndBpm);
    }

    private static int Minutes(DateTime startedAtUtc, DateTime endedAtUtc) =>
        (int)Math.Round((endedAtUtc - startedAtUtc).TotalMinutes, MidpointRounding.AwayFromZero);
}

public sealed record CardioSessionListResult(
    DateOnly From,
    DateOnly Through,
    IReadOnlyList<CardioSessionListItemResult> Sessions);

public sealed record CardioSessionListItemResult(
    Guid SessionId,
    string ActivityType,
    string? TemplateName,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    int DurationMinutes,
    int? AverageHeartRateBpm,
    int? MaxHeartRateBpm,
    decimal? DistanceKm,
    decimal? AveragePowerWatts,
    decimal? EnergyKcal,
    string? Notes);

public sealed record CardioSessionResult(
    Guid SessionId,
    string ActivityType,
    string? TemplateName,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    int DurationMinutes,
    int? AverageHeartRateBpm,
    int? MaxHeartRateBpm,
    decimal? DistanceKm,
    decimal? AveragePowerWatts,
    decimal? EnergyKcal,
    string? Notes,
    CardioZoneResult? TargetZone,
    int SampleIntervalSeconds,
    IReadOnlyList<int> HeartRateBpm,
    IReadOnlyList<int> RrIntervalsMs,
    string? SensorName,
    IReadOnlyList<CardioPhaseResult> Phases,
    int? RecoveryStartBpm,
    int? RecoveryEndBpm);

public sealed record CardioZoneResult(int LowBpm, int HighBpm);

public sealed record CardioPhaseResult(int StartOffsetSeconds, int DurationSeconds, string Name, int? LowBpm, int? HighBpm);
