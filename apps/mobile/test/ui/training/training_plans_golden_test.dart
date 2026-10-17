import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/exercise_picker_sheet.dart';
import 'package:gainer_mobile/ui/features/training/plan_editor_screen.dart';
import 'package:gainer_mobile/ui/features/training/training_plans_section.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Planliste mit Rotationsvorschlag $name', (tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      await tester.runAsync(() async {
        final bench = await seedExercise(harness, name: 'Bankdrücken');
        final row = await seedExercise(harness, name: 'Rudern');
        final squat = await seedExercise(harness, name: 'Kniebeuge');
        final push = await seedPlan(
          harness,
          name: 'Push',
          entries: [
            planEntry(harness, exerciseId: bench.id, warmupSets: 2),
            planEntry(harness, exerciseId: bench.id),
          ],
        );
        final pull = await seedPlan(
          harness,
          name: 'Pull',
          entries: [planEntry(harness, exerciseId: row.id)],
        );
        final legs = await seedPlan(
          harness,
          name: 'Beine',
          entries: [planEntry(harness, exerciseId: squat.id)],
        );
        await harness.repository.saveRotation([
          push.planId,
          pull.planId,
          legs.planId,
        ]);
        await seedFinishedFromPlan(
          harness,
          push,
          DateTime.utc(2026, 10, 14, 18),
        );
      });
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: GainerScaffold(
            title: 'Training',
            children: [
              TrainingPlansSection(
                repository: harness.repository,
                activeWorkout: active,
              ),
            ],
          ),
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(CupertinoPageScaffold),
        matchesGoldenFile('goldens/training_plans_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('Planeditor $name', (tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      final plan = await tester.runAsync(() async {
        final bench = await seedExercise(harness, name: 'Bankdrücken');
        final press = await seedExercise(harness, name: 'Schulterdrücken');
        final fly = await seedExercise(harness, name: 'Cable Fly');
        return seedPlan(
          harness,
          name: 'Push',
          entries: [
            planEntry(
              harness,
              exerciseId: bench.id,
              warmupSets: 2,
              supersetId: 'superset-a',
            ),
            planEntry(harness, exerciseId: press.id, supersetId: 'superset-a'),
            planEntry(harness, exerciseId: fly.id, workingSets: 4),
          ],
        );
      });
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: PlanEditorScreen(
            repository: harness.repository,
            activeWorkout: active,
            planId: plan!.planId,
          ),
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(CupertinoPageScaffold),
        matchesGoldenFile('goldens/plan_editor_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('Übungsauswahl Kategorien $name', (tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      await tester.runAsync(() async {
        final legs = await seedCategory(harness, 'Beine');
        final back = await seedCategory(harness, 'Rücken');
        await seedCategory(harness, 'Brust');
        await seedExercise(harness, name: 'Kniebeuge', categoryIds: [legs.id]);
        await seedExercise(harness, name: 'Rudern', categoryIds: [back.id]);
      });
      await _pumpPickerHost(tester, harness, brightness: brightness);

      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/exercise_picker_categories_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('Übungsauswahl Suchtreffer im Supersatz-Modus $name', (
      tester,
    ) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      await tester.runAsync(() async {
        final legs = await seedCategory(harness, 'Beine');
        await seedExercise(harness, name: 'Kniebeuge', categoryIds: [legs.id]);
        await seedExercise(
          harness,
          name: 'Bulgarische Kniebeuge',
          categoryIds: [legs.id],
        );
        await seedExercise(harness, name: 'Beinpresse', categoryIds: [legs.id]);
      });
      await _pumpPickerHost(tester, harness, brightness: brightness);

      await tester.tap(find.text('Supersatz'));
      await settle(tester);
      await tester.enterText(find.byType(CupertinoSearchTextField), 'kniebeu');
      await settle(tester);
      await tester.tap(pickerRow('Kniebeuge'));
      await settle(tester);

      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/exercise_picker_superset_search_$name.png'),
      );
    }, tags: ['golden']);
  }
}

/// Öffnet die Übungsauswahl über einen Knopf, damit das Sheet wie im Alltag erscheint.
Future<void> _pumpPickerHost(
  WidgetTester tester,
  TrainingHarness harness, {
  required Brightness brightness,
}) async {
  await tester.pumpWidget(
    trainingTestApp(
      brightness: brightness,
      home: Builder(
        builder: (context) => Center(
          child: CupertinoButton(
            onPressed: () =>
                showExercisePicker(context, repository: harness.repository),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  await tester.tap(find.text('Öffnen'));
  await settle(tester);
}
