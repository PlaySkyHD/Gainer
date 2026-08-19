using Gainer.Core.Security;

namespace Gainer.Core.Training;

public sealed class WorkoutRotation : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid? LastCompletedTemplateId { get; set; }
    public DateTime CreatedAtUtc { get; init; }
    public DateTime UpdatedAtUtc { get; set; }
    public long Version { get; set; }
}

public sealed class WorkoutRotationItem : UserOwnedEntity
{
    public Guid Id { get; init; }
    public Guid RotationId { get; init; }
    public Guid TemplateId { get; init; }
    public int Position { get; init; }
}
