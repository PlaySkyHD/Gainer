using Gainer.Core.Training;

namespace Gainer.Infrastructure.Persistence;

/// <summary>Maps stored plans and cardio sessions to their snapshots; shared by mutation handlers and queries.</summary>
internal static class TrainingSnapshots
{
    internal static TrainingPlanSnapshot Plan(TrainingPlan plan, IReadOnlyList<TrainingPlanEntryValues> entries) => new(
        plan.Id,
        plan.Name,
        plan.Notes,
        PreviousValueSources.ToStorageValue(plan.PreviousValueSource),
        entries,
        plan.SortOrder,
        plan.IsArchived,
        plan.CreatedAtUtc,
        plan.UpdatedAtUtc,
        plan.Version);

    internal static TrainingPlanEntryValues PlanEntry(TrainingPlanEntry entry) => new(
        entry.Id, entry.ExerciseId, entry.WarmupSets, entry.WorkingSets, entry.Notes, entry.SupersetId);

    internal static CardioSessionSnapshot Cardio(CardioSession session) => new(
        session.Id,
        session.ActivityType,
        session.StartedAtUtc,
        session.EndedAtUtc,
        session.TargetZoneLowBpm is { } low && session.TargetZoneHighBpm is { } high
            ? new CardioTargetZone(low, high)
            : null,
        session.SampleIntervalSeconds,
        session.HeartRateBpm.ToArray(),
        session.RrIntervalsMs.ToArray(),
        session.SensorName,
        session.DistanceKm,
        session.AveragePowerWatts,
        session.EnergyKcal,
        session.Notes,
        session.CreatedAtUtc,
        session.UpdatedAtUtc,
        session.Version,
        session.RecoveryStartBpm,
        session.RecoveryEndBpm,
        session.TemplateName,
        session.Phases?.ToArray());
}
