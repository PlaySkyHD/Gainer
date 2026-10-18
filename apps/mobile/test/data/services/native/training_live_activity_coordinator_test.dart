import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/data/services/native/training_live_activity_coordinator.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';
import 'package:gainer_mobile/domain/models/training/workout_input.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_controller.dart';

import '../../../ui/training/rest_timer_test_support.dart';
import '../../../ui/training/training_test_support.dart';

final _now = DateTime.utc(2026, 10, 17, 9);

class _FakeLiveActivityPlatform implements LiveActivityPlatform {
  /// `start`, `update`, `end:<id>` oder `endAll` in Aufrufreihenfolge.
  final calls = <String>[];
  final states = <LiveActivityState>[];

  /// `false` simuliert deaktivierte Live Activities.
  bool available = true;

  /// Hält `update` an, bis der Test den Completer auflöst.
  Completer<void>? gate;
  Object? error;

  @override
  Future<bool> start({required LiveActivityState state}) async {
    calls.add('start');
    states.add(state);
    _maybeThrow();
    return available;
  }

  @override
  Future<bool> update({required LiveActivityState state}) async {
    calls.add('update');
    states.add(state);
    await gate?.future;
    _maybeThrow();
    return available;
  }

  @override
  Future<void> end(String sessionId) async => calls.add('end:$sessionId');

  @override
  Future<void> endAll() async => calls.add('endAll');

  void _maybeThrow() {
    final failure = error;
    if (failure != null) throw failure;
  }
}

/// Wartet, bis die gestarteten Plattformaufrufe und Benachrichtigungen abgelaufen sind.
Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

WorkoutBlock _block(String name, {int sets = 3, int recorded = 0}) =>
    WorkoutBlock(
      workoutExerciseId: 'block-$name',
      sourceExerciseId: 'source-$name',
      exerciseNameSnapshot: name,
      exerciseTypeSnapshot: ExerciseKind.strength,
      sets: [
        for (var i = 0; i < sets; i++)
          i < recorded
              ? LoggedSet(setId: '$name-$i', weightKg: 40, repetitions: 10)
              : LoggedSet(setId: '$name-$i'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TrainingHarness harness;
  late RestTimerFixture fixture;
  late ActiveWorkoutController active;
  late _FakeLiveActivityPlatform platform;
  late TrainingLiveActivityCoordinator coordinator;

  setUp(() async {
    harness = await TrainingHarness.create(now: _now);
    fixture = RestTimerFixture(start: _now);
    platform = _FakeLiveActivityPlatform();
    active = ActiveWorkoutController(
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
    coordinator = TrainingLiveActivityCoordinator(
      activeWorkout: active,
      platform: platform,
      isSessionActive: () => true,
      preferences: harness.repository.preferences,
      clock: fixture.clock.read,
      readHistory: () => harness.repository.readDiary(),
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    active.dispose();
    await harness.dispose();
  });

  /// Startet ein Training, lädt es und aktiviert die Live Activity.
  /// Schaltet die Detailfreigabe des Kontos und lässt die Activity nachziehen.
  Future<void> setDetails(bool enabled) async {
    await harness.repository.preferences.write(
      TrainingPreferenceValues(liveActivityDetails: enabled),
    );
    await _flush();
  }

  Future<Workout> startTraining({List<WorkoutBlock> blocks = const []}) async {
    final workout = await harness.seedWorkout(
      title: 'Pull',
      start: _now.subtract(const Duration(hours: 1)),
      blocks: blocks,
    );
    await active.load();
    await coordinator.activate();
    await _flush();
    return workout;
  }

  test('startet die Activity, sobald ein aktives Training existiert', () async {
    final workout = await startTraining();

    expect(platform.calls, ['start']);
    final state = platform.states.single;
    expect(state.sessionId, workout.workoutId);
    expect(state.startedAtUtc, workout.startedAtUtc);
    expect(state.timerPhase, RestTimerPhase.ready);
    expect(state.staleAtUtc, _now.add(const Duration(hours: 8)));
  });

  test('ohne Pause enthält der Content-State keinen Countdown', () async {
    await startTraining();

    final state = platform.states.single;
    expect(state.timerTargetAtUtc, isNull);
    expect(state.pausedRemainingSeconds, isNull);
    expect(state.expired, isFalse);
  });

  test('laufende Pause nennt den Zielzeitpunkt als Countdown', () async {
    await startTraining();

    await active.restTimer!.start();
    await _flush();

    final state = platform.states.last;
    expect(state.timerPhase, RestTimerPhase.running);
    expect(state.timerTargetAtUtc, _now.add(const Duration(seconds: 180)));
    expect(state.staleAtUtc, state.timerTargetAtUtc);
    expect(state.pausedRemainingSeconds, isNull);
  });

  test('pausierte Pause nennt die Restzeit statt eines Ziels', () async {
    await startTraining();
    await active.restTimer!.start();
    fixture.clock.now = _now.add(const Duration(seconds: 30));
    await active.restTimer!.stop();
    await _flush();

    final state = platform.states.last;
    expect(state.timerPhase, RestTimerPhase.paused);
    expect(state.pausedRemainingSeconds, 150);
    expect(state.timerTargetAtUtc, isNull);
    expect(state.staleAtUtc, fixture.clock.now.add(const Duration(hours: 8)));
  });

  test('Ablauf setzt expired und entfernt das Ziel', () async {
    await startTraining();
    await active.restTimer!.start();
    await active.restTimer!.adjust(-180);
    await _flush();

    final state = platform.states.last;
    expect(state.timerPhase, RestTimerPhase.expired);
    expect(state.expired, isTrue);
    expect(state.timerTargetAtUtc, isNull);
  });

  test('Umschalten aus auf an sendet das detail sofort', () async {
    await setDetails(false);
    await startTraining(blocks: [_block('Latzug')]);
    expect(platform.states.last.detail, isNull);

    await setDetails(true);

    expect(platform.calls.last, 'update');
    final detail = platform.states.last.detail!;
    expect(detail.exerciseName, 'Latzug');
    expect(detail.setIndex, 1);
  });

  test('Umschalten an auf aus entfernt das detail sofort', () async {
    await setDetails(true);
    await startTraining(blocks: [_block('Latzug')]);
    expect(platform.states.last.detail, isNotNull);

    await setDetails(false);

    expect(platform.calls.last, 'update');
    expect(platform.states.last.detail, isNull);
    expect(platform.states.last.timerPhase, RestTimerPhase.ready);
  });

  test('ohne Detailfreigabe gibt es kein detail', () async {
    await setDetails(false);
    await startTraining(blocks: [_block('Latzug')]);

    expect(platform.states.single.detail, isNull);
  });

  test(
    'mit Detailfreigabe stehen Titel, Übung und Satzposition im Zustand',
    () async {
      await setDetails(true);
      await startTraining(blocks: [_block('Latzug')]);

      final detail = platform.states.single.detail!;
      expect(detail.title, 'Pull');
      expect(detail.exerciseName, 'Latzug');
      expect(detail.setIndex, 1);
      expect(detail.setCount, 3);
    },
  );

  test('erfasster Satz verschiebt die Satzposition', () async {
    await setDetails(true);
    final workout = await startTraining(blocks: [_block('Latzug')]);
    expect(platform.states.last.detail!.setIndex, 1);

    final block = _block('Latzug', recorded: 1);
    await harness.repository.saveWorkout(workout.copyWith(exercises: [block]));
    await active.load();
    await _flush();

    expect(platform.states.last.detail!.setIndex, 2);
    expect(platform.calls.last, 'update');
  });

  test(
    'Standard zeigt Übung und Satz auch während und nach der Pause',
    () async {
      await startTraining(blocks: [_block('Latzug')]);
      expect(platform.states.last.detail!.exerciseName, 'Latzug');

      await active.restTimer!.start();
      await _flush();
      expect(platform.states.last.detail!.setIndex, 1);
      expect(platform.states.last.timerTargetAtUtc, isNotNull);

      await active.restTimer!.adjust(-180);
      await _flush();
      expect(platform.states.last.expired, isTrue);
      expect(platform.states.last.detail!.exerciseName, 'Latzug');
    },
  );

  test(
    'Satz während laufender Pause aktualisiert Activity mit nächstem Satz',
    () async {
      final workout = await startTraining(blocks: [_block('Latzug')]);
      await active.restTimer!.start();
      await _flush();
      final callsBefore = platform.calls.length;

      final block = _block('Latzug', recorded: 1);
      await harness.repository.saveWorkout(
        workout.copyWith(exercises: [block]),
      );
      await active.load();
      await _flush();

      expect(platform.calls.length, greaterThan(callsBefore));
      final state = platform.states.last;
      expect(state.timerPhase, RestTimerPhase.running);
      expect(state.timerTargetAtUtc, isNotNull);
      expect(state.detail!.setIndex, 2);
      expect(state.detail!.exerciseName, 'Latzug');
    },
  );

  test('Titeländerung aktualisiert die Activity', () async {
    await setDetails(true);
    final workout = await startTraining(blocks: [_block('Latzug')]);

    await harness.repository.saveWorkout(workout.copyWith(title: 'Rücken'));
    await active.load();
    await _flush();

    expect(platform.states.last.detail!.title, 'Rücken');
  });

  test('Beenden beendet die Activity dieses Trainings', () async {
    final workout = await startTraining();

    harness.now = _now;
    await harness.repository.finishWorkout(workout.workoutId);
    await active.load();
    await _flush();

    expect(platform.calls.last, 'end:${workout.workoutId}');
  });

  test('Löschen beendet die Activity', () async {
    final workout = await startTraining();

    await harness.repository.deleteWorkout(workout.workoutId);
    await active.load();
    await _flush();

    expect(platform.calls.last, 'end:${workout.workoutId}');
  });

  test('Abmelden oder Kontowechsel beendet alle Activities', () async {
    await startTraining();

    await coordinator.dispose();

    expect(platform.calls.last, 'endAll');
  });

  test(
    'veraltete Activities werden beim Start ohne Training bereinigt',
    () async {
      coordinator.activate();
      await _flush();

      expect(platform.calls, ['endAll']);
      expect(platform.states, isEmpty);
    },
  );

  test('deaktivierte Integration ruft die Plattform nicht auf', () async {
    coordinator = TrainingLiveActivityCoordinator(
      activeWorkout: active,
      platform: platform,
      preferences: harness.repository.preferences,
      isSessionActive: () => true,
      clock: fixture.clock.read,
      enabled: false,
    );
    await startTraining();
    await active.restTimer!.start();
    await coordinator.dispose();

    expect(platform.calls, isEmpty);
  });

  test('nicht verfügbare Live Activities bleiben ohne Fehler stumm', () async {
    platform.available = false;
    await startTraining();
    await active.restTimer!.start();
    await active.restTimer!.stop();
    await _flush();

    expect(platform.calls, ['start']);
    expect(active.restTimer!.phase, RestTimerPhase.paused);
  });

  test(
    'nach einem Startfehler wird nach kurzer Wartezeit erneut gestartet',
    () async {
      platform.available = false;
      await startTraining();
      expect(platform.calls, ['start']);

      platform.available = true;
      await active.restTimer!.start();
      await _flush();
      expect(platform.calls, [
        'start',
      ], reason: 'innerhalb der Wartezeit kein neuer Versuch');

      fixture.clock.now = fixture.clock.now.add(const Duration(seconds: 31));
      await active.restTimer!.stop();
      await _flush();
      expect(platform.calls, ['start', 'start']);
      expect(platform.states.last.timerPhase, RestTimerPhase.paused);
    },
  );

  test('Rückkehr in die App startet eine beendete Activity neu', () async {
    await startTraining();
    expect(platform.calls, ['start']);

    // iOS hat die Activity beendet, z. B. durch ein App-Update.
    platform.available = false;
    coordinator.resync();
    await _flush();
    expect(platform.calls, ['start', 'update', 'start']);

    platform.available = true;
    coordinator.resync();
    await _flush();
    // Nach dem Fehlschlag gilt keine Wartezeit, der Abgleich sendet sofort.
    expect(platform.calls, ['start', 'update', 'start', 'update']);
  });

  test(
    'Plattformfehler werden geschluckt und die Pause läuft weiter',
    () async {
      platform.error = StateError('Activity nicht verfügbar');
      await startTraining();
      await active.restTimer!.start();
      await _flush();

      expect(active.restTimer!.phase, RestTimerPhase.running);
      expect(platform.calls, everyElement('start'));
      expect(platform.states, hasLength(platform.calls.length));
    },
  );

  test(
    'veraltete Zustände werden verworfen, nur der neueste wird gesendet',
    () async {
      await startTraining();
      platform.gate = Completer<void>();

      await active.restTimer!.start();
      await active.restTimer!.stop();
      fixture.clock.now = _now.add(const Duration(seconds: 10));
      await active.restTimer!.adjust(15);
      await _flush();

      platform.gate!.complete();
      await _flush();

      final updates = platform.states.skip(1).toList();
      expect(updates, hasLength(2));
      expect(updates.first.timerPhase, RestTimerPhase.running);
      expect(updates.last.timerPhase, RestTimerPhase.paused);
      expect(updates.last.pausedRemainingSeconds, 195);
    },
  );

  /// Abgeschlossenes Training vor dem aktiven; es liefert die Vorwerte.
  Future<void> seedPreviousWorkout(List<WorkoutBlock> blocks) async {
    final start = _now.subtract(const Duration(days: 2));
    await harness.seedWorkout(
      title: 'Pull',
      start: start,
      end: start.add(const Duration(hours: 1)),
      blocks: blocks,
    );
  }

  group('Zielwert, Übungsposition und Pausendauer', () {
    test(
      'Zielwert des nächsten Satzes stammt aus dem letzten Training in kg',
      () async {
        await setDetails(true);
        await seedPreviousWorkout([_block('Latzug', recorded: 3)]);
        await startTraining(blocks: [_block('Latzug')]);

        expect(platform.states.last.detail!.targetText, 'Ziel 40 kg × 10');
      },
    );

    test('Gewichtseinheit lbs rechnet den Zielwert um', () async {
      await harness.repository.preferences.write(
        const TrainingPreferenceValues(
          liveActivityDetails: true,
          weightUnit: WeightUnit.lbs,
        ),
      );
      await seedPreviousWorkout([_block('Latzug', recorded: 3)]);
      await startTraining(blocks: [_block('Latzug')]);

      expect(platform.states.last.detail!.targetText, 'Ziel 88,18 lbs × 10');
    });

    test('ohne Vorwert gibt es keinen Zielwert', () async {
      await setDetails(true);
      await startTraining(blocks: [_block('Latzug')]);

      final detail = platform.states.last.detail!;
      expect(detail.targetText, isNull);
      expect(detail.exerciseIndex, 1);
      expect(detail.exerciseCount, 1);
    });

    test('Übungsposition zählt die Übungen des Trainings', () async {
      await setDetails(true);
      final workout = await startTraining(
        blocks: [_block('Latzug'), _block('Rudern')],
      );
      expect(platform.states.last.detail!.exerciseIndex, 1);
      expect(platform.states.last.detail!.exerciseCount, 2);

      await harness.repository.saveWorkout(
        workout.copyWith(
          exercises: [_block('Latzug', recorded: 3), _block('Rudern')],
        ),
      );
      await active.load();
      await _flush();

      expect(platform.states.last.detail!.exerciseIndex, 2);
      expect(platform.states.last.detail!.exerciseCount, 2);
    });

    test(
      'Pausendauer ist mindestens die Basisdauer und folgt verlängerten Pausen',
      () async {
        await startTraining();
        expect(platform.states.last.restDurationSeconds, isNull);

        await active.restTimer!.start();
        await _flush();
        expect(platform.states.last.restDurationSeconds, 180);

        await active.restTimer!.adjust(60);
        await _flush();
        expect(platform.states.last.restDurationSeconds, 240);

        await active.restTimer!.stop();
        await _flush();
        expect(platform.states.last.timerPhase, RestTimerPhase.paused);
        expect(platform.states.last.restDurationSeconds, 240);
      },
    );
  });
}
