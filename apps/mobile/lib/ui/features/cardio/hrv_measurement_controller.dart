import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/body/body_repository.dart';
import '../../../data/repositories/cardio/cardio_preferences.dart';
import '../../../data/repositories/training/training_preferences.dart';
import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/body/body_tracking.dart';
import '../../../domain/models/cardio/cardio_analysis.dart';
import '../../../domain/models/cardio/cardio_draft.dart';
import '../../../domain/models/cardio/resting_measurement.dart';
import 'cardio_session_controller.dart';

enum HrvPhase { idle, settling, measuring, result }

/// Geführte HRV-Messung in Ruhe. Nutzt die native Überwachung mit eigener
/// `sessionId` (ohne Alarm, ohne Live Activity); es entsteht keine
/// `CardioSession`. Läuft nie gleichzeitig mit einer Cardio-Einheit oder deren
/// Erholung (siehe [blockedReason]).
class HrvMeasurementController extends ChangeNotifier {
  HrvMeasurementController({
    required this.platform,
    required this.session,
    required this.body,
    required this.preferences,
    required this.trainingPreferences,
    this.settleDuration = const Duration(seconds: 30),
    this.pollInterval = const Duration(seconds: 1),
    this.signalTimeout = const Duration(seconds: 10),
    this.autoPoll = true,
    String Function()? newId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? (() => 'hrv-${DateTime.now().microsecondsSinceEpoch}');

  /// Anzahl gespeicherter Messungen für „Als Ruhepuls übernehmen“.
  static const adoptCount = 7;

  final HeartRatePlatform platform;
  final CardioSessionController session;
  final BodyRepository body;
  final CardioPreferences preferences;
  final TrainingPreferences trainingPreferences;

  /// Einschwingzeit, die nicht gewertet wird.
  final Duration settleDuration;
  final Duration pollInterval;
  final Duration signalTimeout;

  /// Zyklische Abfrage; Tests schalten sie aus und rufen [poll] selbst auf.
  final bool autoPoll;
  final DateTime Function() _clock;
  final String Function() _newId;

  HrvPhase _phase = HrvPhase.idle;
  String? _sessionId;
  DateTime? _startedAt;
  Duration _duration = const Duration(minutes: 2);
  int _lastSequence = 0;
  final List<CardioSample> _window = [];
  int? _liveBpm;
  DateTime? _liveAt;
  RestingMeasurement? _result;
  RestingMeasurementStatus? _saved;
  String? _error;
  bool _busy = false;
  bool _polling = false;
  bool _disposed = false;
  Timer? _timer;
  List<RestingEntry> _history = const [];

  HrvPhase get phase => _phase;
  bool get isRunning =>
      _phase == HrvPhase.settling || _phase == HrvPhase.measuring;

  /// Gewählte Messdauer (nach dem Einschwingen).
  Duration get duration => _duration;
  RestingMeasurement? get result => _result;

  /// Ergebnis des Speicherns; null, solange nicht gespeichert.
  RestingMeasurementStatus? get saved => _saved;
  String? get error => _error;
  bool get isBusy => _busy;
  List<RestingEntry> get history => _history;

  /// Aktueller Puls; null ohne Wert oder nach [signalTimeout].
  int? get liveBpm {
    final at = _liveAt;
    if (_liveBpm == null ||
        (at != null && _clock().difference(at) > signalTimeout)) {
      return null;
    }
    return _liveBpm;
  }

  /// Gültige RR-Werte im Messfenster bisher.
  int get validRrCount => _window
      .expand((sample) => sample.rrIntervalsMs)
      .where(
        (rr) =>
            rr >= CardioAnalysis.minValidRrMs &&
            rr <= CardioAnalysis.maxValidRrMs,
      )
      .length;

  Duration get _elapsed {
    final start = _startedAt;
    if (start == null) return Duration.zero;
    final value = _clock().difference(start);
    return value.isNegative ? Duration.zero : value;
  }

  /// Verbleibende Zeit der aktuellen Phase (Einschwingen oder Messung).
  Duration get remaining {
    final total = settleDuration + _duration;
    final left = _phase == HrvPhase.settling
        ? settleDuration - _elapsed
        : total - _elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Warum keine Messung gestartet werden kann; null, wenn sie möglich ist.
  String? get blockedReason {
    if (session.isBusy) {
      return 'Während einer Cardio-Einheit ist keine HRV-Messung möglich. '
          'Beende zuerst die Einheit.';
    }
    if (session.connectionState != HeartRateConnectionState.connected) {
      return 'Für die Messung brauchst du einen verbundenen Pulsgurt.';
    }
    return null;
  }

  bool get canStart => !isRunning && !_busy && blockedReason == null;

  /// Liest Messdauer und Verlauf.
  Future<void> load() async {
    final prefs = await preferences.read();
    _duration = Duration(minutes: prefs.hrvMinutes);
    await _loadHistory();
    _notify();
  }

  Future<void> _loadHistory() async {
    try {
      _history = (await body.read()).restingEntries;
    } on Object {
      _history = const [];
    }
  }

  /// Merkt die Messdauer (1–5 min) in den Einstellungen.
  Future<void> setMinutes(int minutes) async {
    if (isRunning) return;
    final value = minutes.clamp(
      CardioPreferenceValues.minHrvMinutes,
      CardioPreferenceValues.maxHrvMinutes,
    );
    _duration = Duration(minutes: value);
    _notify();
    await preferences.update((current) => current.copyWith(hrvMinutes: value));
  }

  List<int> get _lastRestingRates => [
    for (final entry in _history.reversed)
      if (entry.restingHeartRateBpm != null) entry.restingHeartRateBpm!,
  ].take(adoptCount).toList();

  /// Anzahl der Messungen, aus denen der Median entsteht (höchstens 7).
  int get medianSampleCount => _lastRestingRates.length;

  /// Median der Ruhepulse der letzten [adoptCount] Messungen; null ohne Werte.
  int? get medianRestingHeartRate =>
      RestingMeasurement.median(_lastRestingRates);

  /// Ob der Median als Ruhepuls für die Zonen übernommen werden kann (die
  /// Einstellungen erlauben 30–120 bpm).
  bool get canAdopt {
    final median = medianRestingHeartRate;
    return median != null && median >= 30 && median <= 120;
  }

  /// Setzt `CardioPreferences.restingHeartRate` auf den Median der letzten
  /// [adoptCount] Messungen.
  Future<bool> adoptRestingHeartRate() async {
    final median = medianRestingHeartRate;
    if (median == null || !canAdopt) return false;
    await preferences.update(
      (current) => current.copyWith(restingHeartRate: () => median),
    );
    return true;
  }

  /// Startet Einschwingen und Messung.
  Future<void> start() async {
    if (!canStart) return;
    _busy = true;
    _error = null;
    _result = null;
    _saved = null;
    _notify();
    final id = _newId();
    final now = _clock();
    try {
      await platform.startMonitoring(
        HeartRateMonitoringConfig(
          sessionId: id,
          title: 'HRV-Messung',
          startedAtUtc: now.toUtc(),
          soundId: trainingPreferences.timerSoundId.value,
          alertsEnabled: false,
          liveActivityEnabled: false,
        ),
      );
    } on BluetoothUnavailableException catch (e) {
      _busy = false;
      _error = bluetoothMessage(e.problem);
      _notify();
      return;
    } on Object {
      _busy = false;
      _error = 'Die Messung konnte nicht gestartet werden.';
      _notify();
      return;
    }
    _sessionId = id;
    _startedAt = now.toUtc();
    _lastSequence = 0;
    _window.clear();
    _liveBpm = null;
    _liveAt = null;
    _phase = HrvPhase.settling;
    _busy = false;
    _syncTimer();
    _notify();
  }

  /// Bricht die Messung ab, ohne etwas zu speichern.
  Future<void> cancel() async {
    if (!isRunning) return;
    final id = _sessionId;
    _timer?.cancel();
    _timer = null;
    _phase = HrvPhase.idle;
    _sessionId = null;
    _window.clear();
    _notify();
    if (id != null) await _stopNative(id);
  }

  /// Eine Abfrage der nativen Überwachung; beendet die Messung nach Ablauf.
  Future<void> poll() async {
    final id = _sessionId;
    final start = _startedAt;
    if (!isRunning || id == null || start == null || _polling) return;
    _polling = true;
    try {
      final status = await platform.readStatus(_lastSequence);
      if (_disposed || _sessionId != id) return;
      if (status.monitoringSessionId != id) {
        await _abort('Die Messung wurde unterbrochen.');
        return;
      }
      _liveBpm = status.latestBpm;
      _liveAt = status.latestAtUtc;
      final windowStart = start.add(settleDuration);
      final windowEnd = windowStart.add(_duration);
      for (final sample in status.samples) {
        if (sample.sequence <= _lastSequence) continue;
        _lastSequence = sample.sequence;
        if (!sample.atUtc.isBefore(windowStart) &&
            !sample.atUtc.isAfter(windowEnd)) {
          _window.add(sample);
        }
      }
      final elapsed = _elapsed;
      if (elapsed >= settleDuration + _duration) {
        await _complete(id);
        return;
      }
      _phase = elapsed >= settleDuration
          ? HrvPhase.measuring
          : HrvPhase.settling;
      _notify();
    } on BluetoothUnavailableException catch (e) {
      await _abort(bluetoothMessage(e.problem));
    } finally {
      _polling = false;
    }
  }

  Future<void> _complete(String id) async {
    _timer?.cancel();
    _timer = null;
    _result = RestingMeasurement.of(_window);
    _phase = HrvPhase.result;
    _sessionId = null;
    _notify();
    await _stopNative(id);
  }

  Future<void> _abort(String message) async {
    final id = _sessionId;
    _timer?.cancel();
    _timer = null;
    _phase = HrvPhase.idle;
    _sessionId = null;
    _window.clear();
    _error = message;
    _notify();
    if (id != null) await _stopNative(id);
  }

  /// Speichert das Ergebnis im Check-in des Tages (siehe
  /// [BodyRepository.recordRestingMeasurement]).
  Future<bool> save() async {
    final result = _result;
    if (result == null || !result.isStorable || _busy || _saved != null) {
      return false;
    }
    _busy = true;
    _error = null;
    _notify();
    try {
      final now = _clock().toLocal();
      _saved = await body.recordRestingMeasurement(
        localDate:
            '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}',
        restingHeartRateBpm: result.restingHeartRateBpm!,
        restingHrvMs: result.rmssdMs!,
      );
      await _loadHistory();
      return true;
    } on Object {
      _error = 'Die Messung konnte nicht gespeichert werden.';
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Verwirft das Ergebnis und startet eine neue Messung.
  Future<void> repeat() async {
    _result = null;
    _saved = null;
    _phase = HrvPhase.idle;
    _notify();
    await start();
  }

  /// Schließt das Ergebnis, ohne zu speichern.
  void discardResult() {
    _result = null;
    _saved = null;
    _phase = HrvPhase.idle;
    _notify();
  }

  static String bluetoothMessage(BluetoothProblem problem) => switch (problem) {
    BluetoothProblem.poweredOff => 'Bluetooth ist aus.',
    BluetoothProblem.unauthorized => 'Gainer darf Bluetooth nicht nutzen.',
    BluetoothProblem.unsupported => 'Bluetooth wird nicht unterstützt.',
  };

  void _syncTimer() {
    if (!autoPoll || !isRunning || _disposed) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(poll()));
  }

  Future<void> _stopNative(String id) async {
    try {
      await platform.stopMonitoring(id);
    } on Object {
      // Die Messung ist ausgewertet; ein Rest nativ endet beim nächsten Start.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Beendet eine laufende Messung (Verlassen des Screens).
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    final id = _sessionId;
    if (id != null) unawaited(_stopNative(id));
    super.dispose();
  }
}
