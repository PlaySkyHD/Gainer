import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_controller.dart';

import 'rest_timer_test_support.dart';
import 'training_test_support.dart';

/// Antwortet auf die Berechtigungsabfrage erst, wenn der Test es erlaubt.
class _SlowPermissionNotifications extends FakeTimerNotifications {
  final answer = Completer<bool>();

  @override
  Future<bool> requestPermission() => answer.future;
}

/// Ohne Schutz wirft notifyListeners nach dem await einen FlutterError.
void main() {
  test('endRestTimer meldet nach dispose nichts mehr', () async {
    final harness = await TrainingHarness.create();
    final fixture = RestTimerFixture();
    final controller = activeWorkoutWithTimers(harness, fixture);
    try {
      final workout = await harness.seedWorkout(
        title: 'Push',
        start: DateTime.utc(2026, 10, 17, 8),
      );
      await controller.load();
      expect(controller.restTimer, isNotNull);

      final ending = controller.endRestTimer(workout.workoutId);
      controller.dispose();

      await expectLater(ending, completes);
    } finally {
      fixture.disposeControllers();
      await harness.dispose();
    }
  });

  test('selectSound meldet nach dispose nichts mehr', () async {
    final fixture = RestTimerFixture();
    final controller = fixture.controllerFor();
    await controller.load();

    final selecting = controller.selectSound('gong');
    controller.dispose();

    await expectLater(selecting, completes);
  });

  test('setAutoStart meldet nach dispose nichts mehr', () async {
    final fixture = RestTimerFixture();
    final controller = fixture.controllerFor();
    await controller.load();

    final setting = controller.setAutoStart(!controller.autoStartEnabled);
    controller.dispose();

    await expectLater(setting, completes);
  });

  test('Berechtigungsantwort nach dispose bleibt folgenlos', () async {
    final fixture = RestTimerFixture();
    final notifications = _SlowPermissionNotifications();
    final controller = RestTimerController(
      workoutId: restTimerWorkoutId,
      store: fixture.store,
      notifications: notifications,
      haptics: fixture.haptics,
      alerts: fixture.alerts,
      preferences: fixture.preferences,
      clock: fixture.clock.read,
      observeLifecycle: false,
    );
    await controller.load();

    final starting = controller.start();
    // Die Planung hängt jetzt an der Berechtigungsabfrage.
    await pumpEventQueue();
    controller.dispose();
    notifications.answer.complete(false);

    await expectLater(starting, completes);
    await pumpEventQueue();
  });
}
