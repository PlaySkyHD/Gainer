import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../data/repositories/timer/rest_timer_store.dart';
import '../../../data/services/native/rest_timer_alert_port.dart';
import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/timer/rest_timer_shortcuts.dart';
import '../../../domain/models/timer/rest_timer_state.dart';

/// Pausentimer eines aktiven Trainings. Der Zustand liegt im Speicher und wird
/// bei jeder Änderung über [RestTimerStore] gesichert. Die Restzeit wird immer
/// aus dem Zielzeitpunkt berechnet, nie hochgezählt.
///
/// Lebt so lange wie das aktive Training; [endForWorkout] beim Beenden oder
/// Löschen, [dispose] beim Abmelden oder Kontowechsel.
class RestTimerController extends ChangeNotifier with WidgetsBindingObserver {
  RestTimerController({
    required this.workoutId,
    required this.store,
    required this.notifications,
    required this.haptics,
    required this.alerts,
    DateTime Function()? clock,
    bool observeLifecycle = true,
  }) : _clock = clock ?? DateTime.now {
    _state = RestTimerState.ready(workoutId: workoutId);
    _observingLifecycle = observeLifecycle;
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  final String workoutId;
  final RestTimerStore store;
  final TimerNotificationPlatform notifications;
  final HapticsPlatform haptics;
  final RestTimerAlertPort alerts;
  final DateTime Function() _clock;

  late RestTimerState _state;
  RestTimerShortcuts _shortcuts = RestTimerShortcuts.defaults;
  bool _observingLifecycle = false;
  bool _ended = false;
  bool _foreground = true;
  bool? _permissionGranted;
  bool _notificationsUnavailable = false;
  Timer? _ticker;
  Future<void> _notificationQueue = Future<void>.value();

  RestTimerState get state => _state;
  RestTimerPhase get phase => _state.phase;
  RestTimerShortcuts get shortcuts => _shortcuts;
  DateTime get now => _clock();

  /// Verweigerte Benachrichtigungen. Der Timer läuft trotzdem; die Oberfläche
  /// zeigt daraufhin nur einen dezenten Hinweis.
  bool get notificationsUnavailable => _notificationsUnavailable;

  int get remainingSeconds => _state.remainingSecondsAt(_clock());

  /// Anteil der Restzeit an der Ausgangsdauer, 0 bis 1, für den Ring.
  double get progress {
    final base = _state.baseDurationSeconds;
    if (base == 0) return 0;
    return (remainingSeconds / base).clamp(0, 1).toDouble();
  }

  /// Lädt den gespeicherten Zustand und die Shortcuts. Ein laufender Timer
  /// wird nicht neu geplant: die Benachrichtigung existiert bereits.
  Future<void> load() async {
    final loaded = await store.load(workoutId, now: _clock());
    try {
      _shortcuts = await store.loadShortcuts();
    } on FormatException {
      _shortcuts = RestTimerShortcuts.defaults;
    }
    if (_ended) return;
    _adopt(loaded);
    notifyListeners();
  }

  Future<void> start() async {
    if (_ended || _state.phase == RestTimerPhase.running) return;
    await _commit(_state.start(now: _clock()));
  }

  Future<void> stop() async {
    if (_ended || _state.phase != RestTimerPhase.running) return;
    await _commit(_state.stop(now: _clock()));
  }

  /// Verlängert oder verkürzt die Ausgangsdauer (bereit) bzw. die Restzeit
  /// (laufend, pausiert). Ein abgelaufener Timer nimmt keine Anpassung an.
  Future<void> adjust(int deltaSeconds) async {
    if (_ended || _state.phase == RestTimerPhase.expired) return;
    final next = _state.adjust(deltaSeconds, now: _clock());
    if (identical(next, _state)) return;
    await _commit(next);
  }

  /// Beendet den Timer und setzt ihn auf die zuletzt gestartete Dauer zurück.
  Future<void> close() async {
    if (_ended) return;
    final next = _state.close();
    if (identical(next, _state)) return;
    await _commit(next);
  }

  /// Wählt eine Dauer aus. Nur im Bereit- oder Abgelaufen-Zustand möglich.
  Future<void> selectShortcut(int seconds) async {
    if (_ended) return;
    final phase = _state.phase;
    if (phase == RestTimerPhase.running || phase == RestTimerPhase.paused) {
      return;
    }
    final next = _state.selectShortcut(seconds, now: _clock());
    if (identical(next, _state)) return;
    await _commit(next);
  }

  Future<void> addShortcut(int seconds) async {
    if (_ended) return;
    final next = _shortcuts.add(seconds);
    if (next == _shortcuts) return;
    await _saveShortcuts(next);
  }

  Future<void> removeShortcut(int seconds) async {
    if (_ended) return;
    final next = _shortcuts.remove(seconds);
    if (next == _shortcuts) return;
    await _saveShortcuts(next);
  }

  /// Aufrufen, sobald ein Satz vollständig erfasst ist. Erst dann verlässt ein
  /// abgelaufener Timer die 0:00-Anzeige; Teileingaben tun das nicht.
  Future<void> onSetRecorded() async {
    if (_ended || _state.phase != RestTimerPhase.expired) return;
    await _commit(_state.acknowledgeNextSetRecorded());
  }

  /// Räumt Zustand und Benachrichtigung beim Beenden oder Löschen des
  /// Trainings ab. Danach nimmt der Controller keine Aktionen mehr an.
  Future<void> endForWorkout() async {
    if (_ended) return;
    _ended = true;
    _ticker?.cancel();
    _ticker = null;
    _state = RestTimerState.ready(
      workoutId: workoutId,
      generation: _state.generation + 1,
    );
    notifyListeners();
    await Future.wait([_persist(_state), _enqueueCancel()]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ended) return;
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // Berechtigungen können in den Systemeinstellungen geändert worden sein.
      _permissionGranted = null;
      unawaited(_reloadFromStore());
    } else {
      _foreground = false;
    }
  }

  @override
  void dispose() {
    _ended = true;
    _ticker?.cancel();
    _ticker = null;
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    unawaited(_enqueueCancel());
    super.dispose();
  }

  Future<void> _reloadFromStore() async {
    final loaded = await store.load(workoutId, now: _clock());
    if (_ended) return;
    _adopt(loaded);
    notifyListeners();
  }

  /// Übernimmt einen gespeicherten Zustand nur, wenn er neuer ist. Ohne
  /// Generation könnte ein verspäteter Lesevorgang eine neuere Pause überschreiben.
  void _adopt(RestTimerState loaded) {
    if (loaded.generation <= _state.generation) return;
    _state = loaded;
    _syncTicker();
  }

  Future<void> _commit(RestTimerState next) {
    _state = next;
    _syncTicker();
    notifyListeners();
    final running = next.phase == RestTimerPhase.running;
    return Future.wait([
      _persist(next),
      running ? _enqueueSchedule(next) : _enqueueCancel(),
    ]);
  }

  Future<void> _saveShortcuts(RestTimerShortcuts next) async {
    _shortcuts = next;
    notifyListeners();
    try {
      await store.saveShortcuts(next);
    } catch (_) {
      // Shortcuts sind Komfort; ein Speicherfehler darf den Timer nicht blockieren.
    }
  }

  Future<void> _persist(RestTimerState next) async {
    try {
      await store.save(next);
    } catch (_) {
      // Der Zustand bleibt im Speicher gültig. Ein Fehler beim Sichern darf
      // das Training nicht unterbrechen.
    }
  }

  void _syncTicker() {
    final running = _state.phase == RestTimerPhase.running;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _onTick() {
    if (_ended) return;
    final at = _clock();
    if (_state.phase == RestTimerPhase.running && _state.isExpiredAt(at)) {
      _expire(at);
      return;
    }
    notifyListeners();
  }

  /// Ablauf während die App geöffnet ist: einmal Ton und Haptik. Im
  /// Hintergrund übernimmt die lokale Benachrichtigung.
  void _expire(DateTime at) {
    final foreground = _foreground;
    unawaited(_commit(_state.expire(now: at)));
    if (!foreground) return;
    alerts.playExpiry().catchError((Object _) {});
    haptics.perform(HapticIntent.timerComplete).catchError((Object _) {});
  }

  Future<void> _enqueueSchedule(RestTimerState timer) {
    return _enqueueNotification(() async {
      // Eine neuere Änderung hat diese Planung bereits überholt.
      if (_ended || _state.generation != timer.generation) return;
      if (_state.phase != RestTimerPhase.running) return;
      if (!await _notificationsAllowed()) return;
      await notifications.schedule(
        workoutId: workoutId,
        generation: timer.generation,
        targetAtUtc: timer.targetAtUtc!,
      );
    });
  }

  Future<void> _enqueueCancel() {
    return _enqueueNotification(() => notifications.cancel(workoutId));
  }

  /// Benachrichtigungen laufen strikt nacheinander, damit ein Stopp nicht von
  /// einer noch ausstehenden Planung überholt wird.
  Future<void> _enqueueNotification(Future<void> Function() action) {
    final next = _notificationQueue.then((_) async {
      try {
        await action();
      } catch (_) {
        // Benachrichtigungen sind optional; der In-App-Timer bleibt gültig.
      }
    });
    _notificationQueue = next;
    return next;
  }

  Future<bool> _notificationsAllowed() async {
    var granted = _permissionGranted;
    if (granted == null) {
      try {
        granted = await notifications.requestPermission();
      } catch (_) {
        granted = false;
      }
      _permissionGranted = granted;
    }
    final unavailable = !granted;
    if (_notificationsUnavailable != unavailable) {
      _notificationsUnavailable = unavailable;
      notifyListeners();
    }
    return granted;
  }
}
