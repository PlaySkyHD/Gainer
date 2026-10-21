namespace Gainer.Core.Mutations;

/// <summary>Identifies one synchronizable aggregate without carrying an owner identifier.</summary>
public sealed record ResourceKey
{
    private ResourceKey(ResourceKind kind, Guid resourceId)
    {
        Kind = kind;
        ResourceId = resourceId;
    }

    public ResourceKind Kind { get; }
    public Guid ResourceId { get; }

    /// <summary>Creates a validated resource key.</summary>
    public static ResourceKey Create(ResourceKind kind, Guid resourceId)
    {
        if (!Enum.IsDefined(kind))
        {
            throw new ArgumentOutOfRangeException(nameof(kind));
        }

        return resourceId != Guid.Empty
            ? new ResourceKey(kind, resourceId)
            : throw new ArgumentException("A resource identifier cannot be empty.", nameof(resourceId));
    }
}

/// <summary>Lists the aggregate categories accepted by typed mutations.</summary>
public enum ResourceKind
{
    BodyGoal = 1,
    DailyCheckIn = 2,
    CustomExercise = 3,
    TrainingPlan = 4,
    Workout = 6,
    NutritionDay = 7,
    ReusableMeal = 8,
    NutritionTargetSchedule = 9,
    ExerciseCategory = 10,
    CardioSession = 11,

    /// <summary>Replaces the removed workout rotation (formerly 5, which stays unused).</summary>
    TrainingSchedule = 12,
}
