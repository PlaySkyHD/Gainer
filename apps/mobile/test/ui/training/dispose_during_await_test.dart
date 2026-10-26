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

/// Zählt Meldungen nach dispose. Die Planung fängt Fehler ab, deshalb würde
/// der FlutterError von notifyListeners sonst verschluckt.
class _SpyRestTimerController extends RestTimerController {
  _SpyRestTimerController({
    required super.workoutId,
    required super.store,
    required super.notifications,
    required super.haptics,
    required super.alerts,
    super.preferences,
    super.clock,
    super.observeLifecycle,
  });

  bool _gone = false;
  int notifiedAfterDispose = 0;

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_gone) notifiedAfterDispose++;
    super.notifyListeners();
  }
}

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

      // Ohne Prüfung wirft notifyListeners nach dem await einen FlutterError.
      await expectLater(ending, completes);
    } finally {
      fixture.disposeControllers();
      await harness.dispose();
    }
  });

  test('Berechtigungsantwort nach dispose meldet nichts mehr', () async {
    final fixture = RestTimerFixture();
    final notifications = _SlowPermissionNotifications();
    final controller = _SpyRestTimerController(
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
    expect(controller.notifiedAfterDispose, 0);
  });
}
