import 'dart:math' as math;

import '../../../data/repositories/training/training_preferences.dart';
import '../../../domain/models/timer/rest_timer_state.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_rules.dart';
import '../../../ui/features/training/active_workout_controller.dart';
import '../../../ui/features/training/rest_timer_controller.dart';
import '../platform/platform_ports.dart';

/// Hält genau eine Live Activity für das aktive Training des Kontos. Sie zeigt
/// Trainingszeit, Pausenstatus und bei Freigabe Titel, Übung und Satzposition.
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
  }) : _clock = clock ?? DateTime.now;

  /// Gültigkeit ohne Pause: iOS markiert die Activity danach als veraltet.
  static const _trainingValidity = Duration(hours: 8);

  final ActiveWorkoutController activeWorkout;
  final LiveActivityPlatform platform;
  final bool Function() isSessionActive;

  /// Trainingseinstellungen des Kontos. Die Detailfreigabe kommt von dort und
  /// wird bei Änderungen sofort übernommen. Gewichte und Wiederholungen bleiben
  /// unabhängig davon immer außen vor.
  final TrainingPreferences preferences;

  /// Konfigurationsflag. `false` schaltet die Integration vollständig ab.
  final bool enabled;
  final DateTime Function() _clock;

  RestTimerController? _timer;
  bool _activated = false;
  bool _disposed = false;
  bool _unavailable = false;
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
    _attachTimer();
    _request();
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
    if (_disposed || _unavailable || request != _requestSeq) return;
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
    final state = _stateFor(workout);
    if (state == _sent) return;
    await _push(state);
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
      staleAtUtc: staleAt,
      detail: preferences.liveActivityDetails.value
          ? _detailFor(workout)
          : null,
    );
  }

  /// Erste Übung mit unvollständigen Sätzen; sind alle vollständig, die letzte.
  LiveActivityDetail? _detailFor(Workout workout) {
    final blocks = workout.exercises;
    if (blocks.isEmpty) return null;
    final block = blocks.firstWhere(
      (block) => !isBlockComplete(block),
      orElse: () => blocks.last,
    );
    final unrecorded = block.sets.indexWhere(
      (set) => !isSetRecorded(set, block.exerciseTypeSnapshot),
    );
    final position = unrecorded >= 0 ? unrecorded + 1 : block.sets.length;
    return LiveActivityDetail(
      title: workout.title,
      exerciseName: block.exerciseNameSnapshot,
      setIndex: math.max(position, 1),
      setCount: math.max(block.sets.length, 1),
    );
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
        _unavailable = true;
        return;
      }
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
    _timer?.removeListener(_onChanged);
    _timer = null;
    await _queue;
    if (!_activated || _unavailable) return;
    _sessionId = null;
    _sent = null;
    await _call(platform.endAll);
  }
}
