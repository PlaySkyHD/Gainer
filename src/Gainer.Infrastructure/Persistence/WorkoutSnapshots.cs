using Gainer.Core.Training;

namespace Gainer.Infrastructure.Persistence;

internal static class WorkoutSnapshots
{
    internal static WorkoutSnapshot Create(
        Workout workout,
        IReadOnlyList<WorkoutExerciseValues> exercises) => new(
        workout.Id,
        workout.Title,
        workout.Notes,
        workout.StartedAtUtc,
        workout.EndedAtUtc,
        PreviousValueSources.ToStorageValue(workout.PreviousValueSource),
        workout.SourcePlanId,
        workout.SourceWorkoutId,
        exercises,
        workout.DeletedAtUtc,
        workout.CreatedAtUtc,
        workout.UpdatedAtUtc,
        workout.Version);

    internal static IReadOnlyList<WorkoutExerciseValues> ToExerciseValues(
        IReadOnlyList<WorkoutExercise> exercises,
        IReadOnlyList<WorkoutSet> sets) =>
        exercises.OrderBy(item => item.Position).Select(exercise =>
            new WorkoutExerciseValues(
                exercise.Id,
                exercise.SourceExerciseId,
                exercise.ExerciseNameSnapshot,
                ExerciseTypes.ToStorageValue(exercise.ExerciseTypeSnapshot),
                exercise.Notes,
                exercise.SupersetId,
                sets.Where(set => set.WorkoutExerciseId == exercise.Id)
                    .OrderBy(set => set.Position)
                    .Select(set => new WorkoutSetValues(
                        set.Id,
                        WorkoutSetTypes.ToStorageValue(set.SetType),
                        set.WeightKg,
                        set.Repetitions,
                        set.Rir,
                        set.Notes))
                    .ToList()))
            .ToList();
}
