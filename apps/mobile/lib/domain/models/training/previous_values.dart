import 'workout_model.dart';
import 'workout_rules.dart';

/// Ermittelt die Vorwert-Sätze je Block des aktuellen Trainings.
///
/// [history] muss ausschließlich die Trainings des angemeldeten Kontos enthalten;
/// diese Funktion kennt keine Nutzer und prüft keine Eigentümerschaft.
///
/// Ergebnis: je Block-`workoutExerciseId` ein Eintrag je aktuellem Satz,
/// `null` wo kein Vorwert existiert. Zugeordnet wird die Position innerhalb
/// desselben Satztyps: der zweite Arbeitssatz erhält den zweiten Arbeitssatz der
/// Quelle, auch wenn davor unterschiedlich viele Aufwärmsätze stehen.
Map<String, List<LoggedSet?>> previousValuesFor(
  Workout current,
  List<Workout> history,
) {
  final candidates =
      history
          .where(
            (workout) =>
                workout.deletedAtUtc == null &&
                workout.startedAtUtc.isBefore(current.startedAtUtc),
          )
          .toList()
        ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));

  final occurrences = <String, int>{};
  final result = <String, List<LoggedSet?>>{};
  for (final block in current.exercises) {
    final occurrence = occurrences.update(
      block.sourceExerciseId,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    final source = _sourceBlock(
      current,
      candidates,
      block.sourceExerciseId,
      occurrence,
    );
    result[block.workoutExerciseId] = _matchBySetType(block.sets, source);
  }
  return result;
}

List<LoggedSet?> _matchBySetType(List<LoggedSet> sets, WorkoutBlock? source) {
  if (source == null) return List<LoggedSet?>.filled(sets.length, null);
  final sourceByType = <SetType, List<LoggedSet>>{};
  for (final set in source.sets) {
    sourceByType.putIfAbsent(set.setType, () => []).add(set);
  }
  final seen = <SetType, int>{};
  return [
    for (final set in sets)
      () {
        final index = seen.update(
          set.setType,
          (count) => count + 1,
          ifAbsent: () => 0,
        );
        final candidates = sourceByType[set.setType];
        return candidates != null && index < candidates.length
            ? candidates[index]
            : null;
      }(),
  ];
}

/// Füllt nur leere Gewichts- und Wiederholungsfelder aus dem Vorwert derselben
/// Position. Ohne Vorwert bleibt ein Feld leer; es wird nie 0 eingesetzt.
Workout applyPreviousValues(
  Workout workout,
  Map<String, List<LoggedSet?>> previous,
) => workout.copyWith(
  exercises: [
    for (final block in workout.exercises)
      block.copyWith(
        sets: [
          for (var i = 0; i < block.sets.length; i++)
            _fillEmptyFields(
              block.sets[i],
              _at(previous[block.workoutExerciseId], i),
            ),
        ],
      ),
  ],
);

LoggedSet _fillEmptyFields(LoggedSet set, LoggedSet? previous) {
  if (previous == null) return set;
  return set.copyWith(
    weightKg: () => set.weightKg ?? previous.weightKg,
    repetitions: () => set.repetitions ?? previous.repetitions,
  );
}

LoggedSet? _at(List<LoggedSet?>? sets, int index) =>
    sets == null || index >= sets.length ? null : sets[index];

WorkoutBlock? _sourceBlock(
  Workout current,
  List<Workout> candidates,
  String exerciseId,
  int occurrence,
) {
  if (current.previousValueSource == PreviousValueSource.workout) {
    final sourceId = current.sourceWorkoutId;
    final source = _firstWhereOrNull(
      candidates,
      (workout) => workout.workoutId == sourceId,
    );
    final block = source == null
        ? null
        : _pickBlock(source, exerciseId, occurrence);
    if (block != null) return block;
  }
  if (current.previousValueSource == PreviousValueSource.plan) {
    final planId = current.sourcePlanId;
    if (planId != null) {
      final block = _latestBlock(
        candidates,
        exerciseId,
        occurrence,
        (workout) => workout.sourcePlanId == planId,
      );
      if (block != null) return block;
    }
  }
  return _latestBlock(candidates, exerciseId, occurrence, (_) => true);
}

WorkoutBlock? _latestBlock(
  List<Workout> candidates,
  String exerciseId,
  int occurrence,
  bool Function(Workout workout) matches,
) {
  for (final workout in candidates) {
    if (!matches(workout)) continue;
    final block = _pickBlock(workout, exerciseId, occurrence);
    if (block != null) return block;
  }
  return null;
}

/// Das n-te Vorkommen trifft den n-ten geeigneten Block, sonst den ersten.
WorkoutBlock? _pickBlock(Workout workout, String exerciseId, int occurrence) {
  final eligible = [
    for (final block in workout.exercises)
      if (block.sourceExerciseId == exerciseId && _hasRecordedSet(block)) block,
  ];
  if (eligible.isEmpty) return null;
  return occurrence < eligible.length ? eligible[occurrence] : eligible.first;
}

/// Geeignet ist ein Block mit mindestens einem erfassten Satz. Bei Kraftübungen
/// genügen Wiederholungen größer 0, damit ein Gewicht ohne Wiederholungen nicht
/// als Vorwert gilt.
bool _hasRecordedSet(WorkoutBlock block) {
  if (block.exerciseTypeSnapshot == ExerciseKind.strength) {
    return block.sets.any((set) => (set.repetitions ?? 0) > 0);
  }
  return block.sets.any(
    (set) => isSetRecorded(set, block.exerciseTypeSnapshot),
  );
}

Workout? _firstWhereOrNull(
  List<Workout> workouts,
  bool Function(Workout workout) matches,
) {
  for (final workout in workouts) {
    if (matches(workout)) return workout;
  }
  return null;
}
