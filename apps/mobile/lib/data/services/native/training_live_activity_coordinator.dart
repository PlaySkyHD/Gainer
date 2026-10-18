import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../data/repositories/training/training_preferences.dart';
import '../../../domain/models/timer/rest_timer_state.dart';
import '../../../domain/models/training/previous_values.dart';
import '../../../domain/models/training/workout_input.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_rules.dart';
import '../../../ui/features/training/active_workout_controller.dart';
import '../../../ui/features/training/rest_timer_controller.dart';
import '../platform/platform_ports.dart';

/// Hält genau eine Live Activity für das aktive Training des Kontos. Sie zeigt
/// Trainingszeit, Pausenstatus und bei Freigabe Titel, Übung, Satzposition und
/// den Zielwert des nächsten Satzes aus dem Vorwert. Erfasste Werte erscheinen
/// nie.
///
/// Die Activity wird nur bei Änderungen des Zustands aktualisiert, nicht jede
/// Sekunde: die Zeiten rendert das System aus den Zielzeitpunkten. Ist Live
/// Activities deaktiviert, meldet die Plattform `false`; danach bleibt die
/// Activity dieses Kontos aus, und der In-App-Timer läuft unverändert weiter.
class TrainingLiveActivityCoordinator {
  TrainingLiveActivityCoordinator({
    required this.activeWorkout,
    required this.platform,
    required this.preferences,
    required this.isSessionActive,
    this.enabled = true,
    DateTime Function()? clock,
    this.readHistory,
  }) : _clock = clock ?? DateTime.now;

  /// Gültigkeit ohne Pause: iOS markiert die Activity danach als veraltet.
  static const _trainingValidity = Duration(hours: 8);
  static const _retryDelay = Duration(seconds: 30);

  final ActiveWorkoutController activeWorkout;
  final LiveActivityPlatform platform;
  final bool Function() isSessionActive;

  /// Trainingseinstellungen des Kontos. Die Detailfreigabe und die Gewichtseinheit
  /// kommen von dort und werden bei Änderungen sofort übernommen.
  final TrainingPreferences preferences;

  /// Konfigurationsflag. `false` schaltet die Integration vollständig ab.
  final bool enabled;
  final DateTime Function() _clock;

  /// Liefert das Tagebuch des Kontos für die Vorwerte. Fehlt es, gibt es keinen
  /// Zielwert.
  final Future<List<Workout>> Function()? readHistory;

  /// Tagebuch ohne das aktive Training, einmal je Training geladen.
  String? _historyWorkoutId;
  List<Workout> _history = const [];

  RestTimerController? _timer;
  bool _activated = false;
  bool _disposed = false;

  /// Nach einem fehlgeschlagenen Start wird erst ab diesem Zeitpunkt erneut
  /// versucht, damit Timer-Ticks die Plattform nicht dauernd anfragen.
  DateTime? _retryNotBefore;
  AppLifecycleListener? _lifecycle;
  bool _cleanupPending = false;
  int _requestSeq = 0;
  Future<void> _queue = Future<void>.value();

  /// Activity des Trainings, das zuletzt gestartet wurde, und ihr Zustand.
  String? _sessionId;
  LiveActivityState? _sent;

  /// Startet die Beobachtung. Aufrufen, nachdem das aktive Training geladen wurde,
  /// damit die Bereinigung veralteter Activities kein gültiges Training trifft.
  /// Liest vorher die Detailfreigabe; schlägt das Lesen fehl, gilt „aus“.
  Future<void> activate() async {
    if (!enabled || _disposed || _activated) return;
    _activated = true;
    _cleanupPending = activeWorkout.lastLoadError == null;
    try {
      await preferences.read();
    } catch (_) {}
    if (_disposed) return;
    activeWorkout.addListener(_onChanged);
    preferences.liveActivityDetails.addListener(_onChanged);
    preferences.weightUnit.addListener(_onChanged);
    _attachTimer();
    _lifecycle = AppLifecycleListener(onResume: resync);
    activeWorkout.openLiveActivitySettings = () => _call(platform.openSettings);
    _request();
    unawaited(_refreshEnabled());
  }

  /// Liest, ob Live Activities erlaubt sind, und meldet es dem Training. Ein
  /// Lesefehler gilt als erlaubt, damit kein falscher Hinweis erscheint.
  Future<void> _refreshEnabled() async {
    var enabled = true;
    try {
      enabled = await platform.isEnabled();
    } catch (_) {}
    if (_disposed) return;
    activeWorkout.liveActivitiesOff.value = !enabled;
  }

  /// Gleicht die Activity erneut ab, etwa wenn die App wieder in den
  /// Vordergrund kommt: iOS kann sie inzwischen beendet haben, z. B. nach einem
  /// App-Update, und ein früherer Startfehler soll nicht dauerhaft gelten.
  void resync() {
    if (_disposed || !_activated) return;
    _retryNotBefore = null;
    _sent = null;
    _request();
    unawaited(_refreshEnabled());
  }

  void _onChanged() {
    _attachTimer();
    _request();
  }

  /// Der Pausentimer wird je Training neu gebaut; dem neuen Timer folgen wir.
  void _attachTimer() {
    final timer = activeWorkout.restTimer;
    if (identical(timer, _timer)) return;
    _timer?.removeListener(_onChanged);
    _timer = timer;
    timer?.addListener(_onChanged);
  }

  /// Serialisiert Plattformaufrufe. Eine ältere Anfrage wird verworfen, sobald
  /// eine neuere existiert; die neuere liest den aktuellen Zustand selbst.
  void _request() {
    if (_disposed) return;
    final request = ++_requestSeq;
    _queue = _queue.then((_) => _apply(request)).catchError((Object _) {});
  }

  Future<void> _apply(int request) async {
    if (_disposed || request != _requestSeq) return;
    final retryAt = _retryNotBefore;
    if (retryAt != null && _clock().isBefore(retryAt)) return;
    if (!isSessionActive()) return;

    final workout = activeWorkout.active;
    if (workout == null || !workout.isActive) {
      if (_sessionId != null) {
        await _endOwned();
      } else if (_cleanupPending) {
        _cleanupPending = false;
        await _call(platform.endAll);
      }
      return;
    }

    if (_sessionId != null && _sessionId != workout.workoutId) {
      await _endOwned();
    }
    if (preferences.liveActivityDetails.value) {
      await _loadHistory(workout.workoutId);
      if (_disposed) return;
    }
    final state = _stateFor(workout);
    if (state == _sent) return;
    await _push(state);
  }

  /// Lädt das Tagebuch genau einmal je Training. Ein Lesefehler gilt als leer.
  Future<void> _loadHistory(String workoutId) async {
    final read = readHistory;
    if (read == null || _historyWorkoutId == workoutId) return;
    try {
      _history = [
        for (final candidate in await read())
          if (candidate.workoutId != workoutId) candidate,
      ];
    } catch (_) {
      _history = const [];
    }
    _historyWorkoutId = workoutId;
  }

  LiveActivityState _stateFor(Workout workout) {
    final timer = _timer;
    final timerState = timer?.state;
    final phase = timerState?.phase ?? RestTimerPhase.ready;
    final now = _clock().toUtc();
    final targetAt = phase == RestTimerPhase.running
        ? timerState?.targetAtUtc
        : null;
    // Läuft die Pause, ist sie nach ihrem Ende überholt. Sonst gilt die
    // Trainingsgültigkeit, auch im pausierten und abgelaufenen Zustand.
    final staleAt = targetAt != null && targetAt.isAfter(now)
        ? targetAt
        : now.add(_trainingValidity);
    return LiveActivityState(
      sessionId: workout.workoutId,
      timerPhase: phase,
      startedAtUtc: workout.startedAtUtc.toUtc(),
      timerTargetAtUtc: targetAt,
      pausedRemainingSeconds: phase == RestTimerPhase.paused
          ? timerState?.pausedRemainingSeconds
          : null,
      restDurationSeconds: timerState == null
          ? null
          : _restDurationFor(timerState, phase, now),
      staleAtUtc: staleAt,
      detail: preferences.liveActivityDetails.value
          ? _detailFor(workout)
          : null,
    );
  }

  /// Dauer der Pause für den Fortschrittsbalken; ohne laufende oder pausierte
  /// Pause `null`. Nie kürzer als die Basisdauer.
  int? _restDurationFor(
    RestTimerState timer,
    RestTimerPhase phase,
    DateTime now,
  ) => switch (phase) {
    RestTimerPhase.running => math.max(
      timer.baseDurationSeconds,
      timer.remainingSecondsAt(now),
    ),
    RestTimerPhase.paused => math.max(
      timer.baseDurationSeconds,
      timer.pausedRemainingSeconds ?? 0,
    ),
    _ => null,
  };

  /// Erste Übung mit unvollständigen Sätzen; sind alle vollständig, die letzte.
  LiveActivityDetail? _detailFor(Workout workout) {
    final blocks = workout.exercises;
    if (blocks.isEmpty) return null;
    final found = blocks.indexWhere((block) => !isBlockComplete(block));
    final blockIndex = found >= 0 ? found : blocks.length - 1;
    final block = blocks[blockIndex];
    final unrecorded = block.sets.indexWhere(
      (set) => !isSetRecorded(set, block.exerciseTypeSnapshot),
    );
    final position = unrecorded >= 0 ? unrecorded + 1 : block.sets.length;
    final setIndex = math.max(position, 1);
    return LiveActivityDetail(
      title: workout.title,
      exerciseName: block.exerciseNameSnapshot,
      setIndex: setIndex,
      setCount: math.max(block.sets.length, 1),
      exerciseIndex: blockIndex + 1,
      exerciseCount: blocks.length,
      targetText: _targetText(workout, block, setIndex),
    );
  }

  /// Zielwert des Satzes [setIndex] aus dem Vorwert; ohne Vorwert `null`.
  String? _targetText(Workout workout, WorkoutBlock block, int setIndex) {
    final previous = previousValuesFor(
      workout,
      _history,
    )[block.workoutExerciseId];
    final index = setIndex - 1;
    if (previous == null || index < 0 || index >= previous.length) return null;
    final set = previous[index];
    if (set == null) return null;
    final unit = preferences.weightUnit.value;
    final weight = set.weightKg == null
        ? null
        : '${formatWeight(set.weightKg!, unit)} ${unit.label}';
    final reps = set.repetitions;
    if (weight != null && reps != null) return 'Ziel $weight × $reps';
    if (weight != null) return 'Ziel $weight';
    if (reps != null) return 'Ziel $reps Wdh.';
    return null;
  }

  Future<void> _push(LiveActivityState state) async {
    final sessionId = _sessionId;
    await _call(() async {
      var ok = sessionId == null
          ? await platform.start(state: state)
          : await platform.update(state: state);
      // Die Activity kann vom Nutzer oder vom System entfernt worden sein.
      if (!ok && sessionId != null) {
        ok = await platform.start(state: state);
      }
      if (!ok) {
        _sent = null;
        _retryNotBefore = _clock().add(_retryDelay);
        return;
      }
      _retryNotBefore = null;
      _sessionId = state.sessionId;
      _sent = state;
    });
  }

  Future<void> _endOwned() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    _sessionId = null;
    _sent = null;
    await _call(() => platform.end(sessionId));
  }

  /// Fehler der Plattform sind optional: der nächste Zustandswechsel versucht es erneut.
  Future<void> _call(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  /// Beendet die Activity beim Abmelden oder Kontowechsel. `endAll` räumt auch
  /// Activities auf, die dieser Lauf nicht kennt, etwa nach einem Prozessende.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    activeWorkout.removeListener(_onChanged);
    preferences.liveActivityDetails.removeListener(_onChanged);
    preferences.weightUnit.removeListener(_onChanged);
    _timer?.removeListener(_onChanged);
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    await _queue;
    if (!_activated) return;
    _sessionId = null;
    _sent = null;
    await _call(platform.endAll);
  }
}
