import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/shell/mobile_tab_scaffold.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:gainer_mobile/ui/features/training/compact_training_bar.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

import 'rest_timer_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Trainingsscreen mit laufender Pausenleiste $name', (
      tester,
    ) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      final fixture = RestTimerFixture();
      final active = activeWorkoutWithTimers(harness, fixture);
      addTearDown(() => tester.runAsync(harness.dispose));
      final workout = await harness.seedWorkout(
        title: 'Push',
        start: DateTime.utc(2026, 10, 17, 8),
        blocks: [strengthBlock('Bankdrücken', 3, id: 'rest')],
      );
      await active.load();
      final timer = active.restTimer!;
      await timer.startShortcut(180);
      await timer.start();
      await advanceRestTimer(tester, fixture.clock, 30);

      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: WorkoutScreen(
            repository: harness.repository,
            activeWorkout: active,
            workoutId: workout.workoutId,
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('02:30'), findsOneWidget);
      await expectLater(
        find.byType(WorkoutScreen),
        matchesGoldenFile('goldens/workout_timer_running_$name.png'),
      );
      await tester.pumpWidget(const SizedBox());
      active.dispose();
    }, tags: ['golden']);

    testWidgets('minimierte Leiste zeigt Pausen-Restzeit $name', (
      tester,
    ) async {
      usePhoneSize(tester);
      final harness = await tester.runAsync(TrainingHarness.create);
      if (harness == null) throw StateError('Harness nicht erstellt.');
      final fixture = RestTimerFixture();
      final active = activeWorkoutWithTimers(harness, fixture);
      addTearDown(() => tester.runAsync(harness.dispose));
      await harness.seedWorkout(title: 'Push', start: _goldenBarStart);
      await active.load();
      final timer = active.restTimer!;
      await timer.startShortcut(180);
      await timer.start();
      await advanceRestTimer(tester, fixture.clock, 30);
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
              clock: () => _goldenBarNow,
            ),
            tabBuilder: (context, area) => const CupertinoPageScaffold(
              child: Center(child: Text('Heute-Inhalt')),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('02:30'), findsOneWidget);
      await expectLater(
        find.byType(MobileTabScaffold),
        matchesGoldenFile('goldens/compact_training_bar_rest_$name.png'),
      );
      await tester.pumpWidget(const SizedBox());
      active.dispose();
    }, tags: ['golden']);
  }
}

final _goldenBarStart = DateTime.utc(2026, 10, 17, 8);
final _goldenBarNow = _goldenBarStart.add(
  const Duration(minutes: 12, seconds: 34),
);
