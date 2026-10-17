const restTimerMinSeconds = 5;
const restTimerMaxSeconds = 30 * 60;
const restTimerAdjustStepSeconds = 15;
const defaultRestTimerSeconds = 180;

enum RestTimerPhase { ready, running, paused, expired }

class RestTimerException implements Exception {
  const RestTimerException(this.message);

  final String message;

  @override
  String toString() => 'RestTimerException: $message';
}

/// Immutable pause timer of one workout. All transitions take `now` explicitly
/// so the timer can be driven deterministically; none of them starts a timer
/// on its own. Every state change increments [generation].
///
/// [baseDurationSeconds] is the duration of the last started run. It is only
/// changed in [RestTimerPhase.ready] (by [adjust] or [selectShortcut]), so
/// [close] can restore it after a run.
class RestTimerState {
  const RestTimerState._({
    required this.workoutId,
    required this.baseDurationSeconds,
    required this.phase,
    required this.generation,
    this.targetAtUtc,
    this.pausedRemainingSeconds,
  });

  factory RestTimerState.ready({
    required String workoutId,
    int baseDurationSeconds = defaultRestTimerSeconds,
    int generation = 0,
  }) {
    _requireDuration(baseDurationSeconds);
    return RestTimerState._(
      workoutId: workoutId,
      baseDurationSeconds: baseDurationSeconds,
      phase: RestTimerPhase.ready,
      generation: generation,
    );
  }

  final String workoutId;
  final int baseDurationSeconds;
  final RestTimerPhase phase;
  final int generation;

  /// Set in [RestTimerPhase.running] and [RestTimerPhase.expired].
  final DateTime? targetAtUtc;

  /// Set in [RestTimerPhase.paused].
  final int? pausedRemainingSeconds;

  /// Starts from ready (base duration) or paused (kept remaining time).
  RestTimerState start({required DateTime now}) {
    switch (phase) {
      case RestTimerPhase.ready:
      case RestTimerPhase.expired:
        // A new rest after the previous one ran out is always a deliberate tap.
        return _copy(
          phase: RestTimerPhase.running,
          targetAtUtc: now.toUtc().add(Duration(seconds: baseDurationSeconds)),
        );
      case RestTimerPhase.paused:
        return _copy(
          phase: RestTimerPhase.running,
          targetAtUtc: now.toUtc().add(
            Duration(seconds: pausedRemainingSeconds!),
          ),
          clearPausedRemaining: true,
        );
      case RestTimerPhase.running:
        throw RestTimerException('Cannot start a timer that is ${phase.name}.');
    }
  }

  /// Pauses a running timer and keeps its remaining time, rounded up to whole
  /// seconds. If the time has already run out, the timer becomes expired.
  RestTimerState stop({required DateTime now}) {
    if (phase != RestTimerPhase.running) {
      throw RestTimerException('Cannot stop a timer that is ${phase.name}.');
    }
    final remaining = remainingSecondsAt(now);
    if (remaining == 0) {
      return expire(now: now);
    }
    return _copy(
      phase: RestTimerPhase.paused,
      pausedRemainingSeconds: remaining,
      clearTarget: true,
    );
  }

  /// Adds [deltaSeconds] to the base duration (ready) or to the remaining time
  /// (running, paused). Results are clamped to 5 s to 30 min for the duration
  /// and to 0 s to 30 min for the remaining time. Adjusting down to zero while
  /// running or paused expires the timer.
  RestTimerState adjust(int deltaSeconds, {required DateTime now}) {
    final utcNow = now.toUtc();
    switch (phase) {
      case RestTimerPhase.ready:
        final base = _clamp(
          baseDurationSeconds + deltaSeconds,
          restTimerMinSeconds,
          restTimerMaxSeconds,
        );
        if (base == baseDurationSeconds) return this;
        return _copy(baseDurationSeconds: base);
      case RestTimerPhase.running:
        final remaining = _clamp(
          remainingSecondsAt(utcNow) + deltaSeconds,
          0,
          restTimerMaxSeconds,
        );
        if (remaining == 0) {
          return expire(now: utcNow, force: true);
        }
        return _copy(targetAtUtc: utcNow.add(Duration(seconds: remaining)));
      case RestTimerPhase.paused:
        final remaining = _clamp(
          pausedRemainingSeconds! + deltaSeconds,
          0,
          restTimerMaxSeconds,
        );
        if (remaining == 0) {
          return _copy(
            phase: RestTimerPhase.expired,
            targetAtUtc: utcNow,
            clearPausedRemaining: true,
          );
        }
        return _copy(pausedRemainingSeconds: remaining);
      case RestTimerPhase.expired:
        throw RestTimerException('Cannot adjust a timer that is expired.');
    }
  }

  /// Closes the timer and restores the last started duration in ready.
  RestTimerState close() {
    if (phase == RestTimerPhase.ready) return this;
    return _copy(
      phase: RestTimerPhase.ready,
      clearTarget: true,
      clearPausedRemaining: true,
    );
  }

  /// Chooses a shortcut duration. Only allowed while ready or expired.
  RestTimerState selectShortcut(int seconds, {required DateTime now}) {
    _requireDuration(seconds);
    if (phase != RestTimerPhase.ready && phase != RestTimerPhase.expired) {
      throw RestTimerException(
        'Cannot select a shortcut while the timer is ${phase.name}.',
      );
    }
    if (phase == RestTimerPhase.ready && seconds == baseDurationSeconds) {
      return this;
    }
    return _copy(
      phase: RestTimerPhase.ready,
      baseDurationSeconds: seconds,
      clearTarget: true,
      clearPausedRemaining: true,
    );
  }

  /// Returns to ready after the next set was recorded. No-op in other phases,
  /// so it is safe to call for every recorded set.
  RestTimerState acknowledgeNextSetRecorded() {
    if (phase != RestTimerPhase.expired) return this;
    return _copy(
      phase: RestTimerPhase.ready,
      clearTarget: true,
      clearPausedRemaining: true,
    );
  }

  /// Moves a running timer to expired once its target time has been reached.
  /// Returns this unchanged otherwise.
  RestTimerState expire({required DateTime now, bool force = false}) {
    if (phase != RestTimerPhase.running) return this;
    if (!force && !isExpiredAt(now)) return this;
    return _copy(
      phase: RestTimerPhase.expired,
      targetAtUtc: targetAtUtc!.isAfter(now.toUtc())
          ? now.toUtc()
          : targetAtUtc,
    );
  }

  /// Seconds left, rounded up and never negative. Ready shows the base
  /// duration, paused the kept remaining time, expired always zero.
  int remainingSecondsAt(DateTime now) {
    switch (phase) {
      case RestTimerPhase.ready:
        return baseDurationSeconds;
      case RestTimerPhase.running:
        final millis = targetAtUtc!.difference(now.toUtc()).inMilliseconds;
        return millis <= 0 ? 0 : (millis + 999) ~/ 1000;
      case RestTimerPhase.paused:
        return pausedRemainingSeconds!;
      case RestTimerPhase.expired:
        return 0;
    }
  }

  bool isExpiredAt(DateTime now) =>
      phase == RestTimerPhase.expired ||
      (phase == RestTimerPhase.running && !now.toUtc().isBefore(targetAtUtc!));

  Map<String, Object?> toJson() => {
    'workoutId': workoutId,
    'baseDurationSeconds': baseDurationSeconds,
    'phase': phase.name,
    'generation': generation,
    'targetAtUtc': targetAtUtc?.toUtc().toIso8601String(),
    'pausedRemainingSeconds': pausedRemainingSeconds,
  };

  factory RestTimerState.fromJson(Map<String, dynamic> json) {
    final phase = RestTimerPhase.values.firstWhere(
      (value) => value.name == json['phase'],
      orElse: () => throw const FormatException('Unknown rest timer phase.'),
    );
    final targetAt = json['targetAtUtc'] as String?;
    final paused = json['pausedRemainingSeconds'] as int?;
    final baseDuration = json['baseDurationSeconds'] as int;
    final generation = json['generation'] as int;
    final workoutId = json['workoutId'] as String;
    _requireDuration(baseDuration);
    if (generation < 0 ||
        (phase == RestTimerPhase.running || phase == RestTimerPhase.expired) !=
            (targetAt != null) ||
        (phase == RestTimerPhase.paused) != (paused != null)) {
      throw const FormatException('Inconsistent rest timer state.');
    }
    return RestTimerState._(
      workoutId: workoutId,
      baseDurationSeconds: baseDuration,
      phase: phase,
      generation: generation,
      targetAtUtc: targetAt == null ? null : DateTime.parse(targetAt).toUtc(),
      pausedRemainingSeconds: paused,
    );
  }

  RestTimerState _copy({
    RestTimerPhase? phase,
    int? baseDurationSeconds,
    DateTime? targetAtUtc,
    int? pausedRemainingSeconds,
    bool clearTarget = false,
    bool clearPausedRemaining = false,
  }) {
    return RestTimerState._(
      workoutId: workoutId,
      baseDurationSeconds: baseDurationSeconds ?? this.baseDurationSeconds,
      phase: phase ?? this.phase,
      generation: generation + 1,
      targetAtUtc: clearTarget ? null : (targetAtUtc ?? this.targetAtUtc),
      pausedRemainingSeconds: clearPausedRemaining
          ? null
          : (pausedRemainingSeconds ?? this.pausedRemainingSeconds),
    );
  }
}

int _clamp(int value, int min, int max) => value < min
    ? min
    : value > max
    ? max
    : value;

void _requireDuration(int seconds) {
  if (seconds < restTimerMinSeconds || seconds > restTimerMaxSeconds) {
    throw ArgumentError.value(
      seconds,
      'seconds',
      'Expected a duration from $restTimerMinSeconds s to $restTimerMaxSeconds s.',
    );
  }
}
