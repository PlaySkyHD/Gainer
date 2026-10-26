import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../data/repositories/timer/rest_timer_store.dart';
import '../../../data/repositories/training/training_preferences.dart';
import '../../../data/services/native/rest_timer_alert_port.dart';
import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/timer/rest_timer_shortcuts.dart';
import '../../../domain/models/timer/rest_timer_sound.dart';
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
    this.preferences,
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

  /// Timerton und automatischer Start. Ohne Einstellungen gelten die Standardwerte.
  final TrainingPreferences? preferences;
  final DateTime Function() _clock;

  late RestTimerState _state;
  RestTimerShortcuts _shortcuts = RestTimerShortcuts.defaults;
  bool _observingLifecycle = false;
  bool _ended = false;
  bool _disposed = false;
  bool _foreground = true;
  bool? _permissionGranted;
  bool _notificationsUnavailable = false;
  Timer? _ticker;
  Future<void> _notificationQueue = Future<void>.value();

  RestTimerState get state => _state;
  RestTimerPhase get phase => _state.phase;
  RestTimerShortcuts get shortcuts => _shortcuts;
  DateTime get now => _clock();

  /// Gewählter Ablaufton für Benachrichtigung und Ersatzton in der App.
  String get soundId =>
      RestTimerSound.resolveId(preferences?.timerSoundId.value);

  bool get autoStartEnabled => preferences?.autoStartRestTimer.value ?? false;

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

  /// Startet den Timer sofort mit der Dauer des Shortcuts. Nur im Bereit- oder
  /// Abgelaufen-Zustand möglich.
  Future<void> startShortcut(int seconds) async {
    if (_ended || _state.phase == RestTimerPhase.running) return;
    final now = _clock();
    // Pausiert ersetzt der Shortcut die angehaltene Pause durch eine neue.
    final base = _state.phase == RestTimerPhase.paused
        ? _state.close()
        : _state;
    await _commit(base.selectShortcut(seconds, now: now).start(now: now));
  }

  /// Startet den Timer mit der zuletzt gewählten Dauer, wenn er bereit oder
  /// abgelaufen ist. Ein laufender oder pausierter Timer bleibt unverändert.
  Future<void> autoStart() async {
    if (_ended || !_canStartFresh) return;
    await _commit(_state.start(now: _clock()));
  }

  bool get _canStartFresh =>
      _state.phase == RestTimerPhase.ready ||
      _state.phase == RestTimerPhase.expired;

  Future<void> addShortcut(int seconds) async {
    if (_ended) return;
    final next = _shortcuts.add(seconds);
    if (next == _shortcuts) return;
    await _saveShortcuts(next);
  }

  Future<void> moveShortcut(int oldIndex, int newIndex) async {
    if (_ended) return;
    final next = _shortcuts.move(oldIndex, newIndex);
    if (next == _shortcuts) return;
    await _saveShortcuts(next);
  }

  Future<void> removeShortcut(int seconds) async {
    if (_ended) return;
    final next = _shortcuts.remove(seconds);
    if (next == _shortcuts) return;
    await _saveShortcuts(next);
  }

  /// Wählt den Timerton, spielt ihn zur Probe und merkt ihn sich. Ein laufender
  /// Timer plant seine Benachrichtigung mit dem neuen Ton neu.
  Future<void> selectSound(String id) async {
    if (_ended) return;
    final resolved = RestTimerSound.resolveId(id);
    unawaited(alerts.playSound(resolved).catchError((Object _) {}));
    final preferences = this.preferences;
    if (preferences == null || resolved == soundId) return;
    try {
      await preferences.update((v) => v.copyWith(timerSoundId: resolved));
    } catch (_) {
      return;
    }
    notifyListeners();
    if (_state.phase == RestTimerPhase.running) {
      await _enqueueSchedule(_state);
    }
  }

  Future<void> setAutoStart(bool enabled) async {
    if (_ended || enabled == autoStartEnabled) return;
    try {
      await preferences?.update((v) => v.copyWith(autoStartRestTimer: enabled));
    } catch (_) {
      return;
    }
    notifyListeners();
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
    _disposed = true;
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

  /// Ablauf: Die geplante Benachrichtigung bleibt bestehen, sie ist das
  /// Tonsignal. Bei geöffneter App kommt nur die Haptik dazu; einen eigenen Ton
  /// spielt die App nur, wenn keine Benachrichtigung erscheinen kann.
  void _expire(DateTime at) {
    _state = _state.expire(now: at);
    _syncTicker();
    notifyListeners();
    unawaited(_persist(_state));
    if (!_foreground) return;
    unawaited(_alertForeground());
  }

  Future<void> _alertForeground() async {
    final notified = await _notificationsAllowed();
    if (_ended || !_foreground) return;
    if (!notified) alerts.playSound(soundId).catchError((Object _) {});
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
        soundId: soundId,
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
      // Die Berechtigungsabfrage kann den Controller überleben.
      if (!_disposed) notifyListeners();
    }
    return granted;
  }
}
