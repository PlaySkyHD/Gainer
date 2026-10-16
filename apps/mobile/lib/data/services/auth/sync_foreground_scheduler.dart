import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../repositories/sync/sync_repository.dart';
import '../api/api_client.dart';

typedef SyncSchedulerTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

/// Runs sync when an account scope starts or returns to the foreground.
/// Transient network failures retry while the app stays foregrounded. The delay
/// grows to a fixed ceiling so a long outage still recovers when connectivity
/// returns, without creating an OS-background sync promise.
class SyncForegroundScheduler with WidgetsBindingObserver {
  SyncForegroundScheduler({
    required this.synchronize,
    required this.isActive,
    this.clock = DateTime.now,
    this.observeLifecycle = true,
    this.timerFactory = Timer.new,
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ],
  }) : assert(retryDelays.isNotEmpty);

  final Future<SyncRunReport> Function() synchronize;
  final bool Function() isActive;
  final DateTime Function() clock;
  final bool observeLifecycle;
  final SyncSchedulerTimerFactory timerFactory;
  final List<Duration> retryDelays;

  Future<void>? _inFlight;
  Timer? _retryTimer;
  var _retryIndex = 0;
  var _started = false;
  var _disposed = false;
  var _foreground = true;
  var _handoverPaused = false;
  var _runAgain = false;
  SyncRunReport? lastReport;
  Object? lastError;

  Future<void> start() {
    if (_disposed || !isActive()) return Future<void>.value();
    if (!_started) {
      _started = true;
      if (observeLifecycle) {
        WidgetsBinding.instance.addObserver(this);
        final state = WidgetsBinding.instance.lifecycleState;
        _foreground = state == null || state == AppLifecycleState.resumed;
      }
    }
    return _foreground && !_handoverPaused
        ? onForeground()
        : Future<void>.value();
  }

  /// Called by the binding on app resume, or by a network-return signal.
  Future<void> onForeground() {
    if (_disposed || !isActive() || _isSessionBlocked) {
      return Future<void>.value();
    }
    _foreground = true;
    // Recheck the persisted freeze on resume. If it remains active, the
    // account scope pauses again before any sync request is issued.
    _handoverPaused = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryIndex = 0;
    return _runOnce();
  }

  /// Stops retries while a writer handover has frozen this client.
  void pause() {
    _handoverPaused = true;
    _cancelRetry();
  }

  /// Resumes after handover was cancelled or this client became writer again.
  Future<void> resume() => onForeground();

  /// Allows the next explicit/account-scope sync after a persisted freeze ends.
  void allow() {
    if (_disposed) return;
    _handoverPaused = false;
    _retryIndex = 0;
  }

  /// Coalesces committed local edits into the active run or a follow-up run.
  Future<void> onLocalCommit() {
    if (_disposed ||
        !_foreground ||
        _handoverPaused ||
        _isSessionBlocked ||
        !isActive()) {
      return Future<void>.value();
    }
    _cancelRetry();
    _retryIndex = 0;
    if (_inFlight != null) {
      _runAgain = true;
      return _inFlight!;
    }
    return _runOnce();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(onForeground());
    } else {
      _foreground = false;
      _cancelRetry();
    }
  }

  Future<void> _runOnce() {
    if (_disposed || !_foreground || _handoverPaused || !isActive()) {
      return Future<void>.value();
    }
    final active = _inFlight;
    if (active != null) return active;
    late final Future<void> run;
    run = _perform().whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
    _inFlight = run;
    return run;
  }

  Future<void> _perform() async {
    do {
      _runAgain = false;
      await _performSingle();
    } while (_runAgain &&
        !_disposed &&
        _foreground &&
        !_handoverPaused &&
        isActive());
  }

  Future<void> _performSingle() async {
    try {
      final report = await synchronize();
      if (_disposed || !isActive()) return;
      lastReport = report;
      lastError = null;
      _retryIndex = 0;
      if (report.state == SyncRunState.retryPending &&
          report.nextRetryAtUtc != null) {
        _scheduleRetryAt(report.nextRetryAtUtc!);
      }
      if (!{
        SyncRunState.idle,
        SyncRunState.synced,
        SyncRunState.inactiveClient,
      }.contains(report.state)) {
        _runAgain = false;
      }
    } on ApiException catch (error) {
      _runAgain = false;
      if (_disposed || !isActive()) return;
      lastError = error;
      if (error.code == 'network_error') _scheduleRetry();
    } catch (error) {
      _runAgain = false;
      if (_disposed || !isActive()) return;
      lastError = error;
    }
  }

  void _scheduleRetry() {
    if (_disposed ||
        !_foreground ||
        _handoverPaused ||
        !isActive() ||
        _retryTimer != null) {
      return;
    }
    final delay = retryDelays[_retryIndex.clamp(0, retryDelays.length - 1)];
    if (_retryIndex < retryDelays.length - 1) _retryIndex++;
    _retryTimer = timerFactory(delay, () {
      _retryTimer = null;
      if (_disposed || !_foreground || _handoverPaused || !isActive()) return;
      unawaited(_runOnce());
    });
  }

  void _scheduleRetryAt(DateTime dueUtc) {
    if (_disposed ||
        !_foreground ||
        _handoverPaused ||
        !isActive() ||
        _retryTimer != null) {
      return;
    }
    final requested = dueUtc.toUtc().difference(clock().toUtc());
    final Duration delay;
    if (requested <= Duration.zero) {
      delay = retryDelays[_retryIndex.clamp(0, retryDelays.length - 1)];
    } else if (requested > retryDelays.last) {
      delay = retryDelays.last;
    } else {
      delay = requested;
    }
    if (_retryIndex < retryDelays.length - 1) _retryIndex++;
    _retryTimer = timerFactory(delay, () {
      _retryTimer = null;
      if (_disposed || !_foreground || _handoverPaused || !isActive()) return;
      unawaited(_runOnce());
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  bool get _isSessionBlocked =>
      lastReport?.state == SyncRunState.authBlocked ||
      lastReport?.state == SyncRunState.upgradeRequired;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_started && observeLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _cancelRetry();
    await _inFlight;
  }
}
