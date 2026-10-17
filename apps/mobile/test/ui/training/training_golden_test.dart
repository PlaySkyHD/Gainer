import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/shell/mobile_tab_scaffold.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/compact_training_bar.dart';
import 'package:gainer_mobile/ui/features/training/training_home_screen.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Tagebuch mit Trainings $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      await tester.runAsync(() async {
        await harness.seedWorkout(
          title: 'Push',
          start: DateTime(2026, 10, 2, 7).toUtc(),
          end: DateTime(2026, 10, 2, 8, 2).toUtc(),
          blocks: [strengthBlock('Bankdrücken', 3, id: 'push')],
        );
        await harness.seedWorkout(
          title: 'Legs 2',
          start: DateTime(2026, 10, 15, 18).toUtc(),
          end: DateTime(2026, 10, 15, 20, 9).toUtc(),
          blocks: [
            strengthBlock('Beinbeuger', 2, id: 'legs-a'),
            strengthBlock('Beinstrecker', 3, id: 'legs-b'),
          ],
        );
        await harness.seedWorkout(
          title: 'Ganzkörper',
          start: DateTime(2026, 9, 28, 17).toUtc(),
          end: DateTime(2026, 9, 28, 18).toUtc(),
          blocks: [strengthBlock('Kniebeuge', 4, id: 'full')],
        );
        await active.load();
      });

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: TrainingHomeScreen(
            repository: harness.repository,
            activeWorkout: active,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TrainingHomeScreen),
        matchesGoldenFile('goldens/training_diary_$name.png'),
      );
    });

    testWidgets('Tagebuch leer $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: TrainingHomeScreen(
            repository: harness.repository,
            activeWorkout: active,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TrainingHomeScreen),
        matchesGoldenFile('goldens/training_diary_empty_$name.png'),
      );
    });

    for (final (variant, scale) in const [
      ('active', 1.0),
      ('historic', 1.0),
      ('active', 1.3),
    ]) {
      final label = scale == 1.0 ? variant : '${variant}_scale13';
      testWidgets('Trainingskopf $label $name', (tester) async {
        _phoneSize(tester);
        final harness = await tester.runAsync(TrainingHarness.create);
        if (harness == null) throw StateError('Harness nicht erstellt.');
        addTearDown(() => tester.runAsync(harness.dispose));
        final active = ActiveWorkoutController(harness.repository);
        addTearDown(active.dispose);
        final workout = await tester.runAsync(
          () => harness.seedWorkout(
            title: variant == 'active' ? 'Push' : 'Legs 2',
            start: DateTime(2026, 10, 16, 18).toUtc(),
            end: variant == 'active'
                ? null
                : DateTime(2026, 10, 16, 19, 10).toUtc(),
            blocks: [
              strengthBlock('Bankdrücken', 3, id: 'head'),
              strengthBlock('Beinbeuger', 2, id: 'head-b'),
            ],
          ),
        );
        if (workout == null) throw StateError('Training nicht angelegt.');
        await tester.runAsync(active.load);

        await tester.pumpWidget(
          trainingTestApp(
            brightness: brightness,
            textScale: scale,
            home: WorkoutScreen(
              repository: harness.repository,
              activeWorkout: active,
              workoutId: workout.workoutId,
            ),
          ),
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(WorkoutScreen),
          matchesGoldenFile('goldens/workout_${label}_$name.png'),
        );
      });
    }

    testWidgets('kompakte Trainingsleiste über der Tableiste $name', (
      tester,
    ) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      await tester.runAsync(() async {
        await harness.seedWorkout(
          title: 'Push',
          start: DateTime.now().toUtc().subtract(
            const Duration(minutes: 12, seconds: 34),
          ),
        );
        await active.load();
      });
      final model = MobileShellViewModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: MobileTabScaffold(
            model: model,
            compactTrainingBar: CompactTrainingBar(
              activeWorkout: active,
              repository: harness.repository,
            ),
            tabBuilder: (context, area) => const CupertinoPageScaffold(
              child: Center(child: Text('Heute-Inhalt')),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MobileTabScaffold),
        matchesGoldenFile('goldens/compact_training_bar_$name.png'),
      );
    });
  }
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
