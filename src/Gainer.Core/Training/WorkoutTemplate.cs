using Gainer.Core.Security;

namespace Gainer.Core.Training;

public sealed class WorkoutTemplate : UserOwnedEntity
{
    public Guid Id { get; init; }
    public string Name { get; set; } = string.Empty;
    public bool IsArchived { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}

public sealed class WorkoutTemplateItem : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid TemplateId { get; init; }
    public Guid ExerciseId { get; set; }
    public int Position { get; set; }
    public int PlannedSets { get; set; }
    public int MinimumRepetitions { get; set; }
    public int MaximumRepetitions { get; set; }
    public decimal? TargetRir { get; set; }
    public int? RestSeconds { get; set; }
    public string? Notes { get; set; }
}
