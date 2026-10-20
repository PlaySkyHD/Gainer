import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/warmup.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/exercise_editor_screen.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

import 'exercise_catalog_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';
import 'workout_flow_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    Future<void> openWorkout(WidgetTester tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      final workout = await tester.runAsync(() async {
        await harness.repository.preferences.update(
          (v) => v.copyWith(
            warmup: const WarmupSettings(
              showRepetitions: true,
              steps: [
                WarmupStep(percent: 50, repetitions: 8),
                WarmupStep(percent: 80, repetitions: 3),
              ],
            ),
          ),
        );
        await harness.seedWorkout(
          title: 'Push A',
          start: DateTime.utc(2026, 10, 10, 8),
          end: DateTime.utc(2026, 10, 10, 9),
          blocks: [
            WorkoutBlock(
              workoutExerciseId: 'old',
              sourceExerciseId: 'bench',
              exerciseNameSnapshot: 'Bankdrücken',
              exerciseTypeSnapshot: ExerciseKind.strength,
              sets: const [
                LoggedSet(setId: 'o1', weightKg: 100, repetitions: 8),
                LoggedSet(setId: 'o2', weightKg: 100, repetitions: 7),
              ],
            ),
          ],
        );
        return harness.seedWorkout(
          title: 'Push B',
          start: DateTime.utc(2026, 10, 17, 8),
          blocks: [
            WorkoutBlock(
              workoutExerciseId: 'bench',
              sourceExerciseId: 'bench',
              exerciseNameSnapshot: 'Bankdrücken',
              exerciseTypeSnapshot: ExerciseKind.strength,
              sets: const [
                LoggedSet(setId: 'b1'),
                LoggedSet(setId: 'b2'),
              ],
            ),
          ],
        );
      });
      await tester.runAsync(active.load);
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: WorkoutScreen(
            repository: harness.repository,
            activeWorkout: active,
            workoutId: workout!.workoutId,
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('Übungskarte mit Aufwärmhinweis $name', (tester) async {
      await openWorkout(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(WorkoutScreen),
        matchesGoldenFile('goldens/warmup_hint_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('Einstellungs-Sheet Aufwärmhinweis $name', (tester) async {
      await openWorkout(tester);
      await tester.tap(labelled('Weitere Aktionen'));
      await settle(tester);
      await tester.tap(find.text('Aufwärmhinweis'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/warmup_settings_sheet_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('Übungseditor mit Abschnitt Aufwärmen $name', (tester) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(CatalogHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final exercise = await tester.runAsync(() async {
        final own = await seedOwnExercise(harness, name: 'Schrägbankdrücken');
        await harness.repository.preferences.update(
          (v) => v.copyWith(
            warmupOverrides: {
              own.id: ExerciseWarmupOverride(
                exerciseId: own.id,
                steps: const [
                  WarmupStep(percent: 40, repetitions: 10),
                  WarmupStep(percent: 70, repetitions: 5),
                ],
                rounding: 1.25,
              ),
            },
          ),
        );
        return own;
      });
      await tester.pumpWidget(
        catalogHost(
          brightness: brightness,
          buildRoute: (_) => ExerciseEditorScreen(
            repository: harness.repository,
            exercise: exercise,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-under-test')));
      await settle(tester);
      await scrollIntoView(
        tester,
        find.byKey(const ValueKey('warmup-rounding')),
      );

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/exercise_editor_warmup_$name.png'),
      );
    }, tags: ['golden']);
  }
}
