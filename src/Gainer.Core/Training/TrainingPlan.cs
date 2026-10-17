using Gainer.Core.Security;

namespace Gainer.Core.Training;

public sealed class TrainingPlan : UserOwnedEntity
{
    public Guid Id { get; init; }
    public string Name { get; set; } = string.Empty;
    public string? Notes { get; set; }
    public PreviousValueSource PreviousValueSource { get; set; }
    public int SortOrder { get; set; }
    public bool IsArchived { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}

public sealed class TrainingPlanEntry : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid PlanId { get; init; }
    public int Position { get; set; }
    public Guid ExerciseId { get; set; }
    public int WarmupSets { get; set; }
    public int WorkingSets { get; set; }
    public string? Notes { get; set; }
    public Guid? SupersetId { get; set; }
}
