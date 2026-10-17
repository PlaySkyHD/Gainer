import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/timer/rest_timer_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/native/rest_timer_alert_port.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_shortcuts.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_controller.dart';

import 'training_test_support.dart';

const restTimerAccountId = '00000000-0000-4000-8000-000000000011';
const restTimerWorkoutId = '00000000-0000-4000-8000-000000000010';

/// Startzeit der Tests. Die Uhr läuft nur, wenn der Test sie verschiebt.
final restTimerStart = DateTime.utc(2026, 10, 17, 10);

class TestClock {
  TestClock([DateTime? start]) : now = start ?? restTimerStart;

  DateTime now;

  DateTime Function() get read =>
      () => now;
}

/// Speicher im Arbeitsspeicher mit derselben Generation-Regel wie der echte
/// [RestTimerStore]. Verhält sich wie ein Neustart, wenn ein neuer Controller
/// auf denselben Speicher zeigt.
/// Eine gemeinsame Datenbank für alle Fixtures, damit drift nicht warnt.
final _restTimerDatabase = LocalDatabase(NativeDatabase.memory());

class MemoryRestTimerStore extends RestTimerStore {
  MemoryRestTimerStore()
    : super(
        store: LocalSyncStore(
          database: _restTimerDatabase,
          accountId: restTimerAccountId,
        ),
      );

  final _timers = <String, RestTimerState>{};
  RestTimerShortcuts _shortcuts = RestTimerShortcuts.defaults;

  RestTimerState? timerFor(String workoutId) => _timers[workoutId];

  @override
  Future<RestTimerState> load(String workoutId, {required DateTime now}) async {
    final timer =
        _timers[workoutId] ?? RestTimerState.ready(workoutId: workoutId);
    return timer.expire(now: now);
  }

  @override
  Future<bool> save(RestTimerState state) async {
    final existing = _timers[state.workoutId];
    if (existing != null && state.generation <= existing.generation) {
      return false;
    }
    _timers[state.workoutId] = state;
    return true;
  }

  @override
  Future<RestTimerShortcuts> loadShortcuts() async => _shortcuts;

  @override
  Future<void> saveShortcuts(RestTimerShortcuts shortcuts) async {
    _shortcuts = shortcuts;
  }
}

class FakeTimerNotifications implements TimerNotificationPlatform {
  bool permission = true;
  int permissionRequests = 0;
  final scheduled = <({int generation, DateTime targetAtUtc})>[];
  int cancelCount = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<void> schedule({
    required String workoutId,
    required int generation,
    required DateTime targetAtUtc,
  }) async {
    scheduled.add((generation: generation, targetAtUtc: targetAtUtc));
  }

  @override
  Future<void> cancel(String workoutId) async {
    cancelCount++;
  }
}

class FakeHaptics implements HapticsPlatform {
  final intents = <HapticIntent>[];

  @override
  Future<void> perform(HapticIntent intent) async {
    intents.add(intent);
  }
}

class FakeRestTimerAlerts implements RestTimerAlertPort {
  int plays = 0;

  @override
  Future<void> playExpiry() async {
    plays++;
  }
}

/// Gemeinsame Fakes eines Tests. [controllerFor] baut einen Controller, der
/// denselben Speicher benutzt wie die übrigen Controller dieses Tests.
class RestTimerFixture {
  RestTimerFixture({DateTime? start})
    : clock = TestClock(start),
      store = MemoryRestTimerStore();

  final TestClock clock;
  final MemoryRestTimerStore store;
  final notifications = FakeTimerNotifications();
  final haptics = FakeHaptics();
  final alerts = FakeRestTimerAlerts();

  final _controllers = <RestTimerController>[];

  RestTimerController controllerFor({bool observeLifecycle = false}) {
    final controller = RestTimerController(
      workoutId: restTimerWorkoutId,
      store: store,
      notifications: notifications,
      haptics: haptics,
      alerts: alerts,
      clock: clock.read,
      observeLifecycle: observeLifecycle,
    );
    _controllers.add(controller);
    return controller;
  }

  /// Gibt alle Controller frei. Nötig, bevor der Test endet, weil ein laufender
  /// Ticker sonst als ausstehender Timer gilt.
  void disposeControllers() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers.clear();
  }
}

/// Führt einen Test aus und gibt danach alle Controller frei.
Future<void> runRestTimerTest(
  Future<void> Function(RestTimerFixture fixture) body,
) async {
  final fixture = RestTimerFixture();
  try {
    await body(fixture);
  } finally {
    fixture.disposeControllers();
  }
}

/// Verschiebt die Uhr und lässt den Ticker im selben Schritt laufen.
Future<void> advanceRestTimer(
  WidgetTester tester,
  TestClock clock,
  int seconds,
) async {
  clock.now = clock.now.add(Duration(seconds: seconds));
  await tester.pump(Duration(seconds: seconds));
}

/// Hülle für Widget-Tests: Hintergrund in der gewünschten Helligkeit.
Widget restTimerHost({required Widget child}) {
  return Align(alignment: Alignment.bottomCenter, child: child);
}

/// Aktives Training mit Pausentimern aus dem Fixture, so wie der `AccountScope`
/// sie in der App erzeugt.
ActiveWorkoutController activeWorkoutWithTimers(
  TrainingHarness harness,
  RestTimerFixture fixture,
) => ActiveWorkoutController(
  harness.repository,
  restTimerFactory: (workoutId) => RestTimerController(
    workoutId: workoutId,
    store: fixture.store,
    notifications: fixture.notifications,
    haptics: fixture.haptics,
    alerts: fixture.alerts,
    clock: fixture.clock.read,
    observeLifecycle: false,
  ),
);
