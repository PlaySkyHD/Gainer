namespace Gainer.Core.Training;

public sealed record PreviousSetPerformance(
    decimal WeightKg,
    int Repetitions,
    decimal? Rir,
    int Position);

public sealed record PreviousExercisePerformance(
    Guid SourceExerciseId,
    Guid WorkoutId,
    DateTime CompletedAtUtc,
    IReadOnlyList<PreviousSetPerformance> Sets);

public interface IPreviousPerformanceQueries
{
    Task<PreviousExercisePerformance?> GetAsync(
        Guid sourceExerciseId,
        DateTime beforeUtc,
        CancellationToken cancellationToken = default);
}
