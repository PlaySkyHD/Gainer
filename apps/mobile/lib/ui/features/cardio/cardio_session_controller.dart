import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/training/training_preferences.dart';
import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/cardio/cardio_analysis.dart';
import '../../../domain/models/cardio/cardio_draft.dart';
import '../../../domain/models/cardio/cardio_session.dart';

/// Besitzt die laufende Cardio-Einheit eines Kontos: Entwurf, Abfrage der
/// nativen Überwachung, Verdichtung zu 5-s-Werten und Abschluss.
///
/// Die native Seite puffert Messwerte und alarmiert auch bei gesperrtem Display.
/// Dart fragt im Vordergrund jede Sekunde ([pollInterval]) per
/// `readStatus(lastSequence)`, verdichtet die neuen Messwerte und sichert den
/// Entwurf höchstens alle [persistInterval] sowie beim Verlassen des
/// Vordergrunds. Im Hintergrund ruht die Abfrage.
class CardioSessionController extends ChangeNotifier {
  CardioSessionController({
    required this.repository,
    required this.platform,
    required this.notifications,
    required this.trainingPreferences,
    this.liveActivityEnabled = true,
    this.pollInterval = const Duration(seconds: 1),
    this.persistInterval = const Duration(seconds: 5),
    this.signalTimeout = const Duration(seconds: 10),
    this.scanDuration = const Duration(seconds: 5),
    this.autoPoll = true,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  /// Alarmverzögerung und Wiederholung der nativen Zonenlogik.
  static const graceSeconds = 15;
  static const repeatSeconds = 60;

  final CardioRepository repository;
  final HeartRatePlatform platform;
  final TimerNotificationPlatform notifications;
  final TrainingPreferences trainingPreferences;

  /// Live Activity für die Einheit zulassen (Systemschalter prüft Swift).
  final bool liveActivityEnabled;
  final Duration pollInterval;
  final Duration persistInterval;

  /// Nach dieser Zeit ohne Messwert gilt der Puls als „kein Signal“.
  final Duration signalTimeout;
  final Duration scanDuration;
  final DateTime Function() _clock;

  /// Zyklische Abfrage; Tests schalten sie aus und rufen [poll] selbst auf.
  final bool autoPoll;

  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  bool _disposed = false;
  bool _polling = false;
  bool _previewing = false;
  bool _notificationPermissionAsked = false;
  Timer? _timer;
  DateTime? _lastPersistAt;
  bool _dirty = false;

  CardioDraft? _active;
  HeartRateStatus _status = const HeartRateStatus();
  CardioAnalysis? _analysis;
  List<HeartRateSensor> _sensors = const [];
  bool _scanning = false;
  BluetoothProblem? _bluetoothException;

  /// Laufende Einheit oder null.
  CardioDraft? get active => _active;
  bool get isRunning => _active != null;

  /// Aktueller Puls; null ohne Gurt, ohne Messwert oder nach
  /// [signalTimeout] ohne neuen Messwert.
  int? get liveBpm {
    final bpm = _status.latestBpm;
    if (bpm == null || bpm <= 0) return null;
    final at = _status.latestAtUtc;
    if (at != null && _clock().difference(at) > signalTimeout) return null;
    return bpm;
  }

  /// Zielbereichsstatus: der native Stand, sonst aus [liveBpm] und Zielbereich
  /// abgeleitet. Ohne Einheit [HeartRateZoneState.none].
  HeartRateZoneState get zoneState {
    final draft = _active;
    if (draft == null) return HeartRateZoneState.none;
    final bpm = liveBpm;
    if (bpm == null) {
      return _status.connectionState == HeartRateConnectionState.idle &&
              _status.latestBpm == null
          ? HeartRateZoneState.none
          : HeartRateZoneState.noSignal;
    }
    final zone = draft.targetZone;
    if (zone == null) return HeartRateZoneState.none;
    if (bpm < zone.lowBpm) return HeartRateZoneState.below;
    if (bpm > zone.highBpm) return HeartRateZoneState.above;
    return HeartRateZoneState.inZone;
  }

  HeartRateConnectionState get connectionState => _status.connectionState;
  HeartRateBluetoothState get bluetoothState => _status.bluetoothState;

  /// Grund, warum Bluetooth nicht nutzbar ist; null, wenn nichts bekannt ist.
  BluetoothProblem? get bluetoothProblem => switch (_status.bluetoothState) {
    HeartRateBluetoothState.poweredOff => BluetoothProblem.poweredOff,
    HeartRateBluetoothState.unauthorized => BluetoothProblem.unauthorized,
    HeartRateBluetoothState.unsupported => BluetoothProblem.unsupported,
    _ => _bluetoothException,
  };

  /// Gemerkter oder verbundener Gurt.
  String? get sensorId => _status.sensorId ?? _active?.sensorId;
  String? get sensorName => _status.sensorName ?? _active?.sensorName;
  int? get batteryPercent => _status.batteryPercent;

  /// Zeit seit Start der laufenden Einheit.
  Duration get elapsed {
    final draft = _active;
    if (draft == null) return Duration.zero;
    final value = _clock().difference(draft.startedAtUtc);
    return value.isNegative ? Duration.zero : value;
  }

  /// Ø, Max und Zeit im Zielbereich der laufenden Einheit (ohne HRV).
  CardioAnalysis? get currentAnalysis => _analysis;

  /// Ergebnis der letzten Suche.
  List<HeartRateSensor> get sensors => _sensors;
  bool get isScanning => _scanning;

  /// Stellt eine laufende Einheit aus dem Entwurf wieder her. Hat die native
  /// Seite die Überwachung verloren, startet sie neu; ein gemerkter Gurt wird
  /// wieder verbunden.
  Future<void> load() async {
    final draft = await repository.readDraft();
    if (_disposed) return;
    _active = draft;
    if (draft == null) {
      _analysis = null;
      notifyListeners();
      return;
    }
    _analysis = _analysisOf(draft);
    notifyListeners();
    await poll();
    final current = _active;
    if (current != null &&
        current.sensorId != null &&
        _status.connectionState == HeartRateConnectionState.idle) {
      await _connectQuietly(current.sensorId!);
    }
    _syncTimer();
  }

  /// Startet eine Einheit. Läuft schon eine, wird diese zurückgegeben.
  /// [zone] und [warmupSeconds] gelten für die Einheit; [sensor] wird verbunden,
  /// sonst bleibt der gemerkte Gurt.
  Future<CardioDraft> start({
    CardioTargetZone? zone,
    int warmupSeconds = 180,
    HeartRateSensor? sensor,
  }) async {
    final running = _active;
    if (running != null) return running;
    if (zone != null && !zone.isValid) {
      throw ArgumentError.value(zone, 'zone', 'Ungültiger Zielbereich.');
    }
    final draft = CardioDraft(
      sessionId: repository.newSessionId(),
      startedAtUtc: _roundToSecond(_clock()),
      targetZone: zone,
      warmupSeconds: warmupSeconds.clamp(0, 600),
      sensorId: sensor?.id ?? _status.sensorId,
      sensorName: sensor?.name ?? _status.sensorName,
    );
    await repository.writeDraft(draft);
    _active = draft;
    _analysis = _analysisOf(draft);
    _lastPersistAt = _clock();
    _dirty = false;
    notifyListeners();
    if (!_notificationPermissionAsked) {
      _notificationPermissionAsked = true;
      try {
        await notifications.requestPermission();
      } on Object {
        // Ohne Erlaubnis läuft die Einheit weiter, nur ohne Alarm.
      }
    }
    try {
      await platform.startMonitoring(await _config(draft));
    } on BluetoothUnavailableException catch (error) {
      _bluetoothException = error.problem;
    } on Object {
      _active = null;
      _analysis = null;
      await repository.clearDraft();
      notifyListeners();
      rethrow;
    }
    if (sensor != null) await _connectQuietly(sensor.id);
    unawaited(_rememberZone(zone, draft.warmupSeconds));
    notifyListeners();
    _syncTimer();
    return draft;
  }

  /// Ändert den Zielbereich der laufenden Einheit; null entfernt ihn. Native
  /// Alarmierung und Anzeige gelten sofort, die gespeicherte Einheit enthält
  /// den zuletzt gesetzten Bereich.
  Future<void> updateZone(CardioTargetZone? zone) async {
    final draft = _active;
    if (draft == null) throw StateError('Es läuft keine Cardio-Einheit.');
    if (zone != null && !zone.isValid) {
      throw ArgumentError.value(zone, 'zone', 'Ungültiger Zielbereich.');
    }
    final next = draft.copyWith(targetZone: () => zone);
    _active = next;
    _analysis = _analysisOf(next);
    notifyListeners();
    await _persist(force: true);
    try {
      await platform.updateMonitoring(await _config(next));
    } on BluetoothUnavailableException catch (error) {
      _bluetoothException = error.problem;
    }
    unawaited(_rememberZone(zone, next.warmupSeconds));
  }

  /// Beendet die Einheit und speichert sie. Gibt die gespeicherte Einheit
  /// zurück. Die Rückfrage bei unter 60 s (verwerfen oder speichern) stellt der
  /// Aufrufer vor dem Aufruf, siehe [discard].
  Future<CardioSession> finish() async {
    final draft = _active;
    if (draft == null) throw StateError('Es läuft keine Cardio-Einheit.');
    _timer?.cancel();
    _timer = null;
    await poll();
    final current = _active;
    if (current == null || current.sessionId != draft.sessionId) {
      throw StateError('Die Cardio-Einheit wurde inzwischen beendet.');
    }
    var endedAt = _roundToSecond(_clock());
    if (!endedAt.isAfter(current.startedAtUtc)) {
      endedAt = current.startedAtUtc.add(const Duration(seconds: 1));
    }
    final saved = CardioSession(
      sessionId: current.sessionId,
      activityType: current.activityType,
      startedAtUtc: current.startedAtUtc,
      endedAtUtc: endedAt,
      targetZone: current.targetZone,
      sampleIntervalSeconds: current.sampleIntervalSeconds,
      heartRateBpm: CardioBucketer.finish(current, endedAt),
      rrIntervalsMs: current.rrIntervalsMs,
      sensorName: current.sensorName ?? _status.sensorName,
      createdAtUtc: endedAt,
      updatedAtUtc: endedAt,
    );
    try {
      final stored = await repository.saveFinished(saved);
      await repository.clearDraft();
      await _stopNative(current.sessionId);
      _active = null;
      _analysis = null;
      _dirty = false;
      notifyListeners();
      return stored;
    } on Object {
      _syncTimer();
      rethrow;
    }
  }

  /// Verwirft die laufende Einheit ohne zu speichern.
  Future<void> discard() async {
    final draft = _active;
    if (draft == null) return;
    _timer?.cancel();
    _timer = null;
    await repository.clearDraft();
    await _stopNative(draft.sessionId);
    _active = null;
    _analysis = null;
    _dirty = false;
    notifyListeners();
  }

  /// Sucht Pulsgurte. Bei Bluetooth-Problemen bleibt die Liste leer und
  /// [bluetoothProblem] nennt den Grund; es wird keine Suche gestartet.
  Future<List<HeartRateSensor>> scan() async {
    if (_scanning) return _sensors;
    _scanning = true;
    _bluetoothException = null;
    notifyListeners();
    try {
      _sensors = await platform.scan(scanDuration);
    } on BluetoothUnavailableException catch (error) {
      _bluetoothException = error.problem;
      _sensors = const [];
    } finally {
      _scanning = false;
      if (!_disposed) notifyListeners();
    }
    return _sensors;
  }

  /// Verbindet und merkt den Gurt. False bei unbekanntem Gurt oder Bluetooth-
  /// Problem.
  Future<bool> connect(String sensorId) async {
    _bluetoothException = null;
    try {
      final ok = await platform.connect(sensorId);
      final name = _sensors.where((s) => s.id == sensorId).firstOrNull?.name;
      final draft = _active;
      if (ok && draft != null) {
        _active = draft.copyWith(
          sensorId: () => sensorId,
          sensorName: () => name ?? draft.sensorName,
        );
        _dirty = true;
      }
      await refreshStatus();
      return ok;
    } on BluetoothUnavailableException catch (error) {
      _bluetoothException = error.problem;
      notifyListeners();
      return false;
    }
  }

  /// Trennt und vergisst den gemerkten Gurt.
  Future<void> forget() async {
    try {
      await platform.disconnect();
    } on BluetoothUnavailableException catch (error) {
      _bluetoothException = error.problem;
    }
    final draft = _active;
    if (draft != null) {
      _active = draft.copyWith(sensorId: () => null, sensorName: () => null);
      _dirty = true;
    }
    _status = const HeartRateStatus();
    await refreshStatus();
  }

  /// Liest den Gurtstatus außerhalb einer Einheit (Start-Sheet). Mit [watch]
  /// fragt der Controller im Vordergrund weiter jede Sekunde, bis
  /// [stopWatching] folgt.
  Future<void> watch() async {
    _previewing = true;
    await refreshStatus();
    _syncTimer();
  }

  void stopWatching() {
    _previewing = false;
    _syncTimer();
  }

  /// Liest den Status einmal und aktualisiert Anzeige (ohne Verdichtung).
  Future<void> refreshStatus() async {
    if (_active != null) return poll();
    try {
      _status = await platform.readStatus(0);
    } on BluetoothUnavailableException catch (error) {
      _bluetoothException = error.problem;
    }
    if (!_disposed) notifyListeners();
  }

  /// Eine Abfrage der nativen Überwachung: neue Messwerte lesen, verdichten,
  /// Entwurf ggf. sichern. Startet die native Überwachung neu, wenn sie die
  /// Einheit nicht (mehr) kennt. Öffentlich für Tests und für Aufrufer, die
  /// beim Zurückkehren in die App sofort aktualisieren wollen.
  Future<void> poll() async {
    final draft = _active;
    if (draft == null) return;
    if (_polling) return;
    _polling = true;
    try {
      final sequence = draft.lastSequence;
      final status = await platform.readStatus(sequence);
      final current = _active;
      if (_disposed ||
          current == null ||
          current.sessionId != draft.sessionId) {
        return;
      }
      _status = status;
      _bluetoothException = null;
      if (status.monitoringSessionId != current.sessionId) {
        // Native Überwachung weg (App beendet): mit dem Entwurf neu starten.
        // Sequenzen beginnen dort wieder bei 1.
        _active = current.copyWith(lastSequence: 0);
        await platform.startMonitoring(await _config(_active!));
        _dirty = true;
        _afterUpdate();
        await _persist(force: true);
        return;
      }
      if (status.lastSequence < sequence) {
        // Native Sequenz zurückgesetzt: neu ab 0 lesen.
        _active = current.copyWith(lastSequence: 0);
        _dirty = true;
        _afterUpdate();
        return;
      }
      var next = CardioBucketer.fold(current, status.samples, nowUtc: _clock());
      if (status.sensorName != null && status.sensorName != next.sensorName) {
        next = next.copyWith(
          sensorId: () => status.sensorId ?? next.sensorId,
          sensorName: () => status.sensorName,
        );
      }
      _dirty =
          _dirty ||
          status.samples.isNotEmpty ||
          next.buckets.length != current.buckets.length ||
          next.sensorName != current.sensorName;
      _active = next;
      _afterUpdate();
      await _persist();
    } on BluetoothUnavailableException catch (error) {
      _bluetoothException = error.problem;
      if (!_disposed) notifyListeners();
    } finally {
      _polling = false;
    }
  }

  void _afterUpdate() {
    final draft = _active;
    if (draft != null) _analysis = _analysisOf(draft);
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist({bool force = false}) async {
    final draft = _active;
    if (draft == null || !(force || _dirty)) return;
    final now = _clock();
    final last = _lastPersistAt;
    if (!force && last != null && now.difference(last) < persistInterval) {
      return;
    }
    _lastPersistAt = now;
    _dirty = false;
    await repository.writeDraft(draft);
  }

  CardioAnalysis _analysisOf(CardioDraft draft) {
    final open = CardioBucketer.openBucketMean(draft);
    return CardioAnalysis.fromSeries(
      heartRateBpm: [...draft.buckets, ?open],
      sampleIntervalSeconds: draft.sampleIntervalSeconds,
      zone: draft.targetZone,
      activeDuration: elapsed,
    );
  }

  Future<HeartRateMonitoringConfig> _config(CardioDraft draft) async {
    final prefs = await repository.preferences.read();
    return HeartRateMonitoringConfig(
      sessionId: draft.sessionId,
      title: draft.activityType.label,
      startedAtUtc: draft.startedAtUtc,
      soundId: trainingPreferences.timerSoundId.value,
      zoneLowBpm: draft.targetZone?.lowBpm,
      zoneHighBpm: draft.targetZone?.highBpm,
      graceSeconds: graceSeconds,
      repeatSeconds: repeatSeconds,
      warmupSeconds: draft.warmupSeconds,
      alertsEnabled: prefs.alertsEnabled,
      liveActivityEnabled: liveActivityEnabled,
    );
  }

  Future<void> _rememberZone(CardioTargetZone? zone, int warmupSeconds) async {
    try {
      await repository.preferences.update(
        (current) => current.copyWith(
          lastZoneLow: zone?.lowBpm,
          lastZoneHigh: zone?.highBpm,
          warmupSeconds: warmupSeconds,
        ),
      );
    } on Object {
      // Vorbelegung ist optional.
    }
  }

  Future<void> _connectQuietly(String sensorId) async {
    try {
      await platform.connect(sensorId);
      await poll();
    } on BluetoothUnavailableException catch (error) {
      _bluetoothException = error.problem;
    } on Object {
      // Der Gurt verbindet sich nativ selbst neu.
    }
  }

  Future<void> _stopNative(String sessionId) async {
    try {
      await platform.stopMonitoring(sessionId);
    } on Object {
      // Die Einheit ist gespeichert; ein Rest nativ endet mit dem nächsten Start.
    }
  }

  void _onLifecycle(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _syncTimer();
      unawaited(poll());
    } else {
      _timer?.cancel();
      _timer = null;
      unawaited(_persist(force: true));
    }
  }

  void _syncTimer() {
    final needed =
        autoPoll && _foreground && !_disposed && (isRunning || _previewing);
    if (!needed) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(pollInterval, (_) {
      if (isRunning) {
        unawaited(poll());
      } else if (_previewing) {
        unawaited(refreshStatus());
      }
    });
  }

  /// Sichert den Entwurf, hält die Abfrage an und beendet die native
  /// Überwachung (Abmelden). Beim nächsten [load] startet sie wieder.
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    final draft = _active;
    if (draft != null) {
      await _persist(force: true);
      await _stopNative(draft.sessionId);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    super.dispose();
  }
}

DateTime _roundToSecond(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
}
