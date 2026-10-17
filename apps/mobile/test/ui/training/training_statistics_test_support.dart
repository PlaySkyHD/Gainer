import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

import 'training_test_support.dart';

const kneeExerciseId = 'stat-src-squat';
const benchExerciseId = 'stat-src-bench';
const pressExerciseId = 'stat-src-press';
const pushupExerciseId = 'stat-src-pushup';

WorkoutBlock statBlock({
  required String exerciseId,
  required String name,
  required List<LoggedSet> sets,
  ExerciseKind kind = ExerciseKind.strength,
}) => WorkoutBlock(
  workoutExerciseId: 'we-$exerciseId-${sets.length}',
  sourceExerciseId: exerciseId,
  exerciseNameSnapshot: name,
  exerciseTypeSnapshot: kind,
  sets: sets,
);

LoggedSet statSet(
  String id, {
  double? kg,
  int? reps,
  SetType type = SetType.normal,
}) =>
    LoggedSet(setId: 'set-$id', setType: type, weightKg: kg, repetitions: reps);

/// Szenario mit drei beendeten Trainings für Kniebeuge und einem für Bankdrücken.
/// Dazu ein gelöschtes und ein laufendes Training mit besonders schweren Sätzen,
/// die nicht in die Statistik fließen dürfen.
Future<void> seedSquatScenario(TrainingHarness harness) async {
  await harness.seedWorkout(
    title: 'Beine A',
    start: DateTime(2026, 10, 1, 18).toUtc(),
    end: DateTime(2026, 10, 1, 19).toUtc(),
    blocks: [
      statBlock(
        exerciseId: kneeExerciseId,
        name: 'Kniebeuge',
        sets: [
          statSet('1a', kg: 100, reps: 8),
          statSet('1b', kg: 80, reps: 10),
        ],
      ),
    ],
  );
  await harness.seedWorkout(
    title: 'Oberkörper',
    start: DateTime(2026, 10, 5, 18).toUtc(),
    end: DateTime(2026, 10, 5, 19).toUtc(),
    blocks: [
      statBlock(
        exerciseId: benchExerciseId,
        name: 'Bankdrücken',
        sets: [statSet('2a', kg: 60, reps: 5)],
      ),
      statBlock(
        exerciseId: kneeExerciseId,
        name: 'Kniebeuge',
        sets: [statSet('2b', kg: 110, reps: 5)],
      ),
    ],
  );
  await harness.seedWorkout(
    title: 'Beine B',
    start: DateTime(2026, 10, 9, 18).toUtc(),
    end: DateTime(2026, 10, 9, 19).toUtc(),
    blocks: [
      statBlock(
        exerciseId: kneeExerciseId,
        name: 'Kniebeuge',
        sets: [
          statSet('3a', kg: 110, reps: 5),
          statSet('3b', kg: 110, reps: 5),
        ],
      ),
    ],
  );
  final deleted = await harness.seedWorkout(
    title: 'Gelöscht',
    start: DateTime(2026, 10, 3, 18).toUtc(),
    end: DateTime(2026, 10, 3, 19).toUtc(),
    blocks: [
      statBlock(
        exerciseId: kneeExerciseId,
        name: 'Kniebeuge',
        sets: [statSet('x1', kg: 200, reps: 1)],
      ),
      statBlock(
        exerciseId: 'stat-src-ghost',
        name: 'Geheimübung',
        sets: [statSet('x2', kg: 90, reps: 3)],
      ),
    ],
  );
  await harness.repository.deleteWorkout(deleted.workoutId);
  await harness.seedWorkout(
    title: 'Laufend',
    start: DateTime(2026, 10, 12, 18).toUtc(),
    blocks: [
      statBlock(
        exerciseId: kneeExerciseId,
        name: 'Kniebeuge',
        sets: [statSet('y1', kg: 150, reps: 3)],
      ),
    ],
  );
}

/// Eine Übung mit genau einem Satz 100 kg × 8.
Future<void> seedSingleSquatSet(TrainingHarness harness) => harness.seedWorkout(
  title: 'Beine',
  start: DateTime(2026, 10, 1, 18).toUtc(),
  end: DateTime(2026, 10, 1, 19).toUtc(),
  blocks: [
    statBlock(
      exerciseId: kneeExerciseId,
      name: 'Kniebeuge',
      sets: [statSet('single', kg: 100, reps: 8)],
    ),
  ],
);

Future<void> saveWeightCheckIn(
  TrainingHarness harness, {
  required String localDate,
  required double weightKg,
}) async {
  final body = BodyRepository(store: harness.store, clock: () => harness.now);
  await body.saveCheckIn(
    localDate: localDate,
    weightKg: weightKg,
    caloriesKcal: null,
    proteinGrams: null,
    carbohydrateGrams: null,
    fatGrams: null,
    steps: null,
    sleepMinutes: null,
  );
}
