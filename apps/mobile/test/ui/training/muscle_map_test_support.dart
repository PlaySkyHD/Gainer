import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/muscles.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/exercise_editor_screen.dart';

import 'exercise_catalog_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

typedef MuscleScenario = ({TrainingPlanModel push, TrainingPlanModel pull});

Future<CatalogExercise> _exercise(
  TrainingHarness harness,
  String name, {
  List<Muscle> primary = const [],
  List<Muscle> secondary = const [],
}) => harness.repository.createCustomExercise(
  CatalogExercise(
    id: harness.repository.newId(),
    name: name,
    exerciseType: ExerciseKind.strength,
    primaryMuscles: primary,
    secondaryMuscles: secondary,
    isBase: false,
  ),
);

WorkoutBlock _squatBlock(String id, String exerciseId) => WorkoutBlock(
  workoutExerciseId: id,
  sourceExerciseId: exerciseId,
  exerciseNameSnapshot: 'Kniebeuge',
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: [
    for (var i = 0; i < 2; i++)
      LoggedSet(
        setId: '$id-w$i',
        setType: SetType.warmup,
        weightKg: 60,
        repetitions: 5,
      ),
    for (var i = 0; i < 3; i++)
      LoggedSet(setId: '$id-s$i', weightKg: 100, repetitions: 5),
  ],
);

/// Push (Bankdrücken 4, Trizepsdrücken 3), Pull (Klimmzüge 3, Curls ohne
/// Muskeln 3), ein archivierter Beinplan und Kniebeugen vor 1, 5 und 20 Tagen.
/// Die Uhr steht danach wieder auf dem Startzeitpunkt des Harness.
Future<MuscleScenario> seedMuscleScenario(TrainingHarness harness) async {
  final now = harness.now;
  final bench = await _exercise(
    harness,
    'Bankdrücken',
    primary: [Muscle.chest],
    secondary: [Muscle.triceps],
  );
  final pushdown = await _exercise(
    harness,
    'Trizepsdrücken',
    primary: [Muscle.triceps],
  );
  final pullUp = await _exercise(
    harness,
    'Klimmzüge',
    primary: [Muscle.lats],
    secondary: [Muscle.biceps],
  );
  final squat = await _exercise(harness, 'Kniebeuge', primary: [Muscle.quads]);
  final curl = await _exercise(harness, 'Curls');

  final push = await seedPlan(
    harness,
    name: 'Push',
    entries: [
      planEntry(harness, exerciseId: bench.id, warmupSets: 2, workingSets: 4),
      planEntry(harness, exerciseId: pushdown.id),
    ],
  );
  final pull = await seedPlan(
    harness,
    name: 'Pull',
    entries: [
      planEntry(harness, exerciseId: pullUp.id),
      planEntry(harness, exerciseId: curl.id),
    ],
  );
  final legs = await seedPlan(
    harness,
    name: 'Beine alt',
    entries: [planEntry(harness, exerciseId: squat.id, workingSets: 5)],
  );
  await harness.repository.archivePlan(legs.planId);

  for (final (index, days) in [1, 5, 20].indexed) {
    final start = now.subtract(Duration(days: days));
    await harness.seedWorkout(
      title: 'Beine',
      start: start,
      end: start.add(const Duration(hours: 1)),
      blocks: [_squatBlock('squat-$index', squat.id)],
    );
  }
  harness.now = now;
  return (push: push, pull: pull);
}

/// Öffnet den Übungseditor über eine Host-Seite, damit Speichern zurückkehrt.
Future<void> openEditorFor(
  WidgetTester tester,
  TrainingHarness harness,
  CatalogExercise exercise,
) async {
  usePhoneSize(tester);
  await tester.pumpWidget(
    catalogHost(
      buildRoute: (_) => ExerciseEditorScreen(
        repository: harness.repository,
        exercise: exercise,
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-under-test')));
  await settle(tester);
}
