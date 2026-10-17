import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/save_workout_as_plan.dart';

import 'training_test_support.dart';

WorkoutBlock _block(String name, List<LoggedSet> sets) => WorkoutBlock(
  workoutExerciseId: '$name-block',
  sourceExerciseId: '$name-source',
  exerciseNameSnapshot: name,
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: sets,
);

const _beinSets = [
  LoggedSet(setId: 'w', setType: SetType.warmup, weightKg: 60, repetitions: 10),
  LoggedSet(setId: 'n1', weightKg: 100, repetitions: 8),
  LoggedSet(setId: 'n2', weightKg: 100, repetitions: 7),
  LoggedSet(setId: 'd', setType: SetType.dropset, weightKg: 80, repetitions: 6),
];

void main() {
  late TrainingHarness harness;

  setUp(() async {
    harness = await TrainingHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  Widget host(Workout workout) => Builder(
    builder: (context) => CupertinoButton(
      onPressed: () => saveWorkoutAsPlanFlow(
        context,
        repository: harness.repository,
        workout: workout,
      ),
      child: const Text('Als Plan speichern öffnen'),
    ),
  );

  Future<void> pumpHost(WidgetTester tester, Workout workout) async {
    await tester.pumpWidget(trainingTestApp(home: host(workout)));
    await settle(tester);
    await tester.tap(find.text('Als Plan speichern öffnen'));
    await settle(tester);
  }

  Future<Workout> seed(String title, List<LoggedSet> sets, String blockName) =>
      harness.seedWorkout(
        title: title,
        start: DateTime.utc(2026, 10, 16, 18),
        end: DateTime.utc(2026, 10, 16, 19),
        blocks: [_block(blockName, sets)],
      );

  testWidgets('neuer Plan aus Training: Aufwärm- und Arbeitssätze zählen', (
    tester,
  ) async {
    final workout = (await tester.runAsync(
      () => seed('Beine', _beinSets, 'Kniebeuge'),
    ))!;
    await pumpHost(tester, workout);

    expect(find.text('Plan gespeichert'), findsOneWidget);
    await tester.tap(_inStacked('OK'));
    await settle(tester);

    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans, hasLength(1));
    final plan = plans!.single;
    expect(plan.name, 'Beine');
    expect(plan.entries.single.warmupSets, 1);
    expect(plan.entries.single.workingSets, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gleichnamiger Plan wird nach Überschreiben ersetzt', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await harness.repository.createPlan(
        TrainingPlanModel(
          planId: testId(500),
          name: 'push',
          previousValueSource: PreviousValueSource.exercise,
          entries: [
            PlanEntry(
              entryId: testId(501),
              exerciseId: 'alt-source',
              workingSets: 5,
            ),
          ],
        ),
      );
    });
    final workout = (await tester.runAsync(
      () => seed('Push', const [
        LoggedSet(setId: 'a', weightKg: 100, repetitions: 8),
        LoggedSet(setId: 'b', weightKg: 100, repetitions: 8),
        LoggedSet(setId: 'c', weightKg: 100, repetitions: 8),
      ], 'Bankdrücken'),
    ))!;
    await pumpHost(tester, workout);

    expect(find.text('Plan „push“ existiert bereits'), findsOneWidget);
    await tester.tap(find.text('Überschreiben'));
    await settle(tester);
    await tester.tap(_inStacked('OK'));
    await settle(tester);

    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans, hasLength(1));
    expect(plans!.single.planId, testId(500));
    expect(plans.single.entries.single.exerciseId, 'Bankdrücken-source');
    expect(plans.single.entries.single.workingSets, 3);
  });

  testWidgets('Als neuen Plan speichern legt einen zweiten Plan an', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await harness.repository.createPlan(
        TrainingPlanModel(
          planId: testId(500),
          name: 'push',
          previousValueSource: PreviousValueSource.exercise,
        ),
      );
    });
    final workout = (await tester.runAsync(
      () => seed('Push', _beinSets, 'Bankdrücken'),
    ))!;
    await pumpHost(tester, workout);

    await tester.tap(find.text('Als neuen Plan speichern'));
    await settle(tester);
    await tester.tap(_inStacked('OK'));
    await settle(tester);

    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans, hasLength(2));
  });

  testWidgets('Abbrechen speichert keinen Plan', (tester) async {
    await tester.runAsync(() async {
      await harness.repository.createPlan(
        TrainingPlanModel(
          planId: testId(500),
          name: 'Push',
          previousValueSource: PreviousValueSource.exercise,
        ),
      );
    });
    final workout = (await tester.runAsync(
      () => seed('Push', _beinSets, 'Bankdrücken'),
    ))!;
    await pumpHost(tester, workout);

    await tester.tap(find.text('Abbrechen'));
    await settle(tester);

    expect(find.text('Plan gespeichert'), findsNothing);
    final plans = await tester.runAsync(harness.repository.readPlans);
    expect(plans, hasLength(1));
  });
}

Finder _inStacked(String label) => find.descendant(
  of: find.byType(GainerStackedDialog<bool>),
  matching: find.text(label),
);
