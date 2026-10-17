import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/workout_summary_screen.dart';

import 'training_test_support.dart';
import 'workout_flow_test_support.dart';

WorkoutBlock _squat(List<LoggedSet> sets) => WorkoutBlock(
  workoutExerciseId: 'squat',
  sourceExerciseId: 'squat-source',
  exerciseNameSnapshot: 'Kniebeuge',
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: sets,
);

/// Vorjahr-Training mit Kniebeuge 100 × 8 und 100 × 7 als Vorwerte.
Future<void> _seedPrevious(WidgetTester tester, TrainingHarness harness) {
  return tester.runAsync(
    () => harness.seedWorkout(
      title: 'Beine A',
      start: DateTime.utc(2026, 10, 10, 8),
      end: DateTime.utc(2026, 10, 10, 9),
      blocks: [
        WorkoutBlock(
          workoutExerciseId: 'old-squat',
          sourceExerciseId: 'squat-source',
          exerciseNameSnapshot: 'Kniebeuge',
          exerciseTypeSnapshot: ExerciseKind.strength,
          sets: const [
            LoggedSet(setId: 'o1', weightKg: 100, repetitions: 8),
            LoggedSet(setId: 'o2', weightKg: 100, repetitions: 7),
          ],
        ),
      ],
    ),
  );
}

void main() {
  late TrainingHarness harness;
  late ActiveWorkoutController active;

  setUp(() async {
    harness = await TrainingHarness.create();
    active = ActiveWorkoutController(harness.repository);
  });

  tearDown(() async {
    active.dispose();
    await harness.dispose();
  });

  Future<void> tapFinish(WidgetTester tester) async {
    await tester.tap(find.text('Beenden'));
    await settle(tester);
  }

  testWidgets('Beenden mit fehlenden Werten fragt mit drei Aktionen nach', (
    tester,
  ) async {
    await _seedPrevious(tester, harness);
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [
        _squat(const [LoggedSet(setId: 's1')]),
      ],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tapFinish(tester);

    expect(find.text('Gewicht oder Wiederholungen fehlen'), findsOneWidget);
    expect(find.text('Ja, Vorwerte verwenden'), findsOneWidget);
    expect(find.text('Trotzdem beenden'), findsOneWidget);
    expect(find.text('Weitertrainieren'), findsOneWidget);
  });

  testWidgets('Vorwerte übernehmen füllt nur leere Felder und beendet', (
    tester,
  ) async {
    await _seedPrevious(tester, harness);
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [
        _squat(const [
          LoggedSet(setId: 's1', weightKg: 90),
          LoggedSet(setId: 's2'),
        ]),
      ],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tapFinish(tester);
    await tester.tap(find.text('Ja, Vorwerte verwenden'));
    await settle(tester);

    final stored = (await storedWorkout(tester, harness, id))!;
    final sets = stored.exercises.single.sets;
    expect(sets[0].weightKg, 90);
    expect(sets[0].repetitions, 8);
    expect(sets[1].weightKg, 100);
    expect(sets[1].repetitions, 7);
    expect(stored.endedAtUtc, isNotNull);
    expect(find.byType(WorkoutSummaryScreen), findsOneWidget);
  });

  testWidgets('Trotzdem beenden lässt die fehlenden Werte leer', (
    tester,
  ) async {
    await _seedPrevious(tester, harness);
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [
        _squat(const [LoggedSet(setId: 's1')]),
      ],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tapFinish(tester);
    await tester.tap(find.text('Trotzdem beenden'));
    await settle(tester);

    final stored = (await storedWorkout(tester, harness, id))!;
    expect(stored.exercises.single.sets.single.weightKg, isNull);
    expect(stored.exercises.single.sets.single.repetitions, isNull);
    expect(stored.endedAtUtc, isNotNull);
    expect(find.byType(WorkoutSummaryScreen), findsOneWidget);
  });

  testWidgets('Weitertrainieren lässt das Training aktiv und unverändert', (
    tester,
  ) async {
    await _seedPrevious(tester, harness);
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [
        _squat(const [LoggedSet(setId: 's1')]),
      ],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tapFinish(tester);
    await tester.tap(find.text('Weitertrainieren'));
    await settle(tester);

    final stored = (await storedWorkout(tester, harness, id))!;
    expect(stored.endedAtUtc, isNull);
    expect(stored.exercises.single.sets.single.weightKg, isNull);
    expect(find.text('Beenden'), findsOneWidget);
    expect(find.byType(WorkoutSummaryScreen), findsNothing);
  });

  testWidgets('ohne fehlende Werte gibt es keinen Dialog', (tester) async {
    final id = await startActiveWorkout(
      tester,
      harness,
      active,
      blocks: [
        _squat(const [LoggedSet(setId: 's1', weightKg: 100, repetitions: 5)]),
      ],
    );
    await pumpWorkoutFromHost(tester, harness, active, id);

    await tapFinish(tester);

    expect(find.text('Gewicht oder Wiederholungen fehlen'), findsNothing);
    expect((await storedWorkout(tester, harness, id))!.endedAtUtc, isNotNull);
    expect(find.byType(WorkoutSummaryScreen), findsOneWidget);
  });
}
