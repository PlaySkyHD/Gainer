using Gainer.Core.Mutations;

namespace Gainer.Core.Training;

public sealed record CardioTargetZone(int LowBpm, int HighBpm);

/// <summary>One planned phase of a guided session, positioned by its offset from the session start.</summary>
public sealed record CardioPhaseValues(
    int StartOffsetSeconds,
    int DurationSeconds,
    string Name,
    int? LowBpm,
    int? HighBpm);

/// <summary>Complete editable state of a cardio session; the client builds it and the server validates it.</summary>
public sealed record CardioSessionValues(
    Guid SessionId,
    string ActivityType,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    CardioTargetZone? TargetZone,
    int SampleIntervalSeconds,
    IReadOnlyList<int> HeartRateBpm,
    IReadOnlyList<int> RrIntervalsMs,
    string? SensorName,
    decimal? DistanceKm,
    decimal? AveragePowerWatts,
    decimal? EnergyKcal,
    string? Notes,
    int? RecoveryStartBpm = null,
    int? RecoveryEndBpm = null,
    string? TemplateName = null,
    IReadOnlyList<CardioPhaseValues>? Phases = null);

public sealed record SaveCardioSessionMutation : ITypedMutation<CardioSessionSnapshot>
{
    private SaveCardioSessionMutation(MutationMetadata metadata, long baseVersion, CardioSessionValues session)
    {
        Metadata = metadata;
        BaseVersion = baseVersion;
        Session = session;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.CardioSession, session.SessionId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }

    /// <summary>Zero creates the session; a positive value updates it.</summary>
    public long BaseVersion { get; }
    public CardioSessionValues Session { get; }

    public static SaveCardioSessionMutation Create(MutationMetadata metadata, long baseVersion, CardioSessionValues session)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        ArgumentNullException.ThrowIfNull(session);
        if (session.SessionId == Guid.Empty)
        {
            throw new ArgumentException("The session identifier cannot be empty.", nameof(session));
        }
        ArgumentOutOfRangeException.ThrowIfNegative(baseVersion);
        return new(metadata, baseVersion, session);
    }
}

public sealed record DeleteCardioSessionMutation : ITypedMutation<long>
{
    private DeleteCardioSessionMutation(MutationMetadata metadata, Guid sessionId, long baseVersion)
    {
        Metadata = metadata;
        SessionId = sessionId;
        BaseVersion = baseVersion;
        Scope = AtomicMutationScope.Create(ResourceVersionExpectation.Create(
            ResourceKey.Create(ResourceKind.CardioSession, sessionId), baseVersion));
    }

    public MutationMetadata Metadata { get; }
    public AtomicMutationScope Scope { get; }
    public Guid SessionId { get; }
    public long BaseVersion { get; }

    public static DeleteCardioSessionMutation Create(MutationMetadata metadata, Guid sessionId, long baseVersion)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (sessionId == Guid.Empty)
        {
            throw new ArgumentException("The session identifier cannot be empty.", nameof(sessionId));
        }
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(baseVersion);
        return new(metadata, sessionId, baseVersion);
    }
}

/// <summary>Flat pull snapshot: the session fields plus server metadata.</summary>
public sealed record CardioSessionSnapshot(
    Guid SessionId,
    string ActivityType,
    DateTime StartedAtUtc,
    DateTime EndedAtUtc,
    CardioTargetZone? TargetZone,
    int SampleIntervalSeconds,
    IReadOnlyList<int> HeartRateBpm,
    IReadOnlyList<int> RrIntervalsMs,
    string? SensorName,
    decimal? DistanceKm,
    decimal? AveragePowerWatts,
    decimal? EnergyKcal,
    string? Notes,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long Version,
    int? RecoveryStartBpm = null,
    int? RecoveryEndBpm = null,
    string? TemplateName = null,
    IReadOnlyList<CardioPhaseValues>? Phases = null) : IResourceSnapshot
{
    public ResourceKey Resource => ResourceKey.Create(ResourceKind.CardioSession, SessionId);
}

public interface ICardioSessionMutationHandler
{
    Task<CardioSessionSnapshot> SaveAsync(SaveCardioSessionMutation mutation, CancellationToken cancellationToken = default);
    Task<long> DeleteAsync(DeleteCardioSessionMutation mutation, CancellationToken cancellationToken = default);
}

public sealed class CardioSessionValidationException(IReadOnlyDictionary<string, string> errors)
    : Exception("The cardio session is invalid.")
{
    public IReadOnlyDictionary<string, string> Errors { get; } = errors;
}

public sealed class CardioSessionConflictException(string message) : Exception(message);

public sealed class CardioSessionNotFoundException : Exception;
