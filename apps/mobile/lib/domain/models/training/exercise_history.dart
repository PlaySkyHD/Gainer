import 'workout_model.dart';
import 'workout_rules.dart';

/// Erfasste Sätze einer Übung in einem früheren Training.
class ExerciseHistoryEntry {
  const ExerciseHistoryEntry({
    required this.workout,
    required this.kind,
    required this.sets,
  });

  final Workout workout;
  final ExerciseKind kind;

  /// Nur erfasste Sätze in Reihenfolge; vollständig leere Sätze fehlen.
  final List<LoggedSet> sets;
}

/// Verlauf einer Übung aus den übrigen Trainings: neuestes zuerst. Trainings
/// ohne erfasste Sätze dieser Übung entfallen.
List<ExerciseHistoryEntry> exerciseHistoryFor({
  required Workout current,
  required String sourceExerciseId,
  required List<Workout> diary,
}) {
  final candidates =
      diary
          .where(
            (workout) =>
                workout.deletedAtUtc == null &&
                workout.workoutId != current.workoutId &&
                workout.startedAtUtc.isBefore(current.startedAtUtc),
          )
          .toList()
        ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));

  final entries = <ExerciseHistoryEntry>[];
  for (final workout in candidates) {
    ExerciseKind? kind;
    final sets = <LoggedSet>[];
    for (final block in workout.exercises) {
      if (block.sourceExerciseId != sourceExerciseId) continue;
      kind ??= block.exerciseTypeSnapshot;
      sets.addAll(
        block.sets.where(
          (set) => isSetRecorded(set, block.exerciseTypeSnapshot),
        ),
      );
    }
    if (kind != null && sets.isNotEmpty) {
      entries.add(
        ExerciseHistoryEntry(workout: workout, kind: kind, sets: sets),
      );
    }
  }
  return entries;
}
