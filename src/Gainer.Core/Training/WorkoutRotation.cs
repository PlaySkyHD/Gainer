using Gainer.Core.Security;

namespace Gainer.Core.Training;

public sealed class WorkoutRotation : UserOwnedEntity
{
    public Guid Id { get; init; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}

public sealed class WorkoutRotationItem : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid RotationId { get; init; }
    public Guid PlanId { get; init; }
    public int Position { get; init; }
}

/// <summary>Derives the next plan of a rotation from the last finished rotation workout; nothing is stored.</summary>
public static class WorkoutRotationSuggestion
{
    /// <param name="rotationPlanIds">Plans in rotation order.</param>
    /// <param name="archivedPlanIds">Archived plans, which are skipped.</param>
    /// <param name="lastFinishedRotationPlanId">Plan of the most recent finished, not deleted workout within the rotation.</param>
    public static Guid? Next(
        IReadOnlyList<Guid> rotationPlanIds,
        IReadOnlyCollection<Guid> archivedPlanIds,
        Guid? lastFinishedRotationPlanId)
    {
        ArgumentNullException.ThrowIfNull(rotationPlanIds);
        ArgumentNullException.ThrowIfNull(archivedPlanIds);
        if (rotationPlanIds.Count == 0 || rotationPlanIds.All(id => archivedPlanIds.Contains(id)))
        {
            return null;
        }

        int lastIndex = lastFinishedRotationPlanId is { } last ? rotationPlanIds.ToList().IndexOf(last) : -1;
        for (int offset = 1; offset <= rotationPlanIds.Count; offset++)
        {
            Guid candidate = rotationPlanIds[(lastIndex + offset + rotationPlanIds.Count) % rotationPlanIds.Count];
            if (!archivedPlanIds.Contains(candidate))
            {
                return candidate;
            }
        }

        return null;
    }
}
