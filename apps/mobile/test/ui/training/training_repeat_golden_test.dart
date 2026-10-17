import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/repeat_workout_sheet.dart';
import 'package:gainer_mobile/ui/features/training/training_home_screen.dart';

import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Wiederholen-Sheet $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      final source = await tester.runAsync(
        () => harness.seedWorkout(
          title: 'Push',
          start: DateTime(2026, 10, 9, 17).toUtc(),
          end: DateTime(2026, 10, 9, 18).toUtc(),
          blocks: [strengthBlock('Bankdrücken', 3, id: 'push')],
        ),
      );
      if (source == null) throw StateError('Training nicht angelegt.');

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => showRepeatWorkoutSheet(
                context,
                repository: harness.repository,
                activeWorkout: active,
                source: source.copyWith(sourcePlanId: () => testId(900)),
              ),
              child: const Text('Wiederholen'),
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Wiederholen'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/repeat_workout_sheet_$name.png'),
      );
    });

    testWidgets('Tagebuch-Kontextmenü $name', (tester) async {
      _phoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      addTearDown(() => tester.runAsync(harness.dispose));
      final active = ActiveWorkoutController(harness.repository);
      addTearDown(active.dispose);
      await tester.runAsync(() async {
        await harness.seedWorkout(
          title: 'Legs 2',
          start: DateTime(2026, 10, 15, 18).toUtc(),
          end: DateTime(2026, 10, 15, 20, 9).toUtc(),
          blocks: [
            strengthBlock('Beinbeuger', 2, id: 'legs-a'),
            strengthBlock('Beinstrecker', 3, id: 'legs-b'),
          ],
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
      await tester.longPress(find.text('Legs 2'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/training_diary_context_$name.png'),
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
