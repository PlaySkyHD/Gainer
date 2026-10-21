import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;

import '../../../domain/models/cardio/cardio_draft.dart';
import '../../../domain/models/cardio/cardio_template.dart';
import '../../../domain/models/timer/rest_timer_state.dart';
import 'generated/mobile_platform_api.dart';

abstract interface class CapturePlatform {
  Future<String?> scanBarcode();
  Future<CapturedImage?> capturePhoto();
  Future<CapturedImage?> chooseImage();
}

class CapturedImage {
  const CapturedImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

abstract interface class SecureSessionPlatform {
  Future<Uint8List?> readCheckpoint(String apiOrigin);
  Future<void> writeCheckpoint(String apiOrigin, Uint8List checkpoint);
  Future<void> clearCheckpoint(String apiOrigin);
}

/// System passkey sheet with Face ID. Returns null when the user cancels.
abstract interface class PasskeyPlatform {
  Future<PlatformPasskeyRegistration?> createPasskey({
    required String relyingPartyId,
    required Uint8List challenge,
    required Uint8List userId,
    required String userName,
  });

  Future<PlatformPasskeyAssertion?> assertPasskey({
    required String relyingPartyId,
    required Uint8List challenge,
  });
}

abstract interface class TimerNotificationPlatform {
  Future<bool> requestPermission();
  Future<void> schedule({
    required String workoutId,
    required int generation,
    required DateTime targetAtUtc,
    required String soundId,
  });
  Future<void> cancel(String workoutId);
}

enum HapticIntent { commit, timerComplete, success }

abstract interface class HapticsPlatform {
  Future<void> perform(HapticIntent intent);
}

abstract interface class HealthPlatform {
  Future<bool> isAvailable();
  Future<PlatformAuthorizationRequestResult> requestBodyMassReadAuthorization();
  Future<List<BodyMassSample>> readBodyMassSamples({
    required DateTime fromUtc,
    required DateTime toUtc,
  });
  Future<PlatformAuthorizationRequestResult> requestCheckInAuthorization();
  Future<int?> readStepCount({
    required DateTime fromUtc,
    required DateTime toUtc,
  });
  Future<HealthSleepWindow?> readSleep({
    required DateTime fromUtc,
    required DateTime toUtc,
  });
  Future<HealthWriteStatus> writeBodyMass({
    required double kilograms,
    required DateTime measuredAtUtc,
    required String syncIdentifier,
  });
  Future<HealthWriteStatus> writeSleep({
    required DateTime bedtimeUtc,
    required DateTime wakeUtc,
    required String syncIdentifier,
  });
  Future<PlatformAuthorizationRequestResult> requestWorkoutWriteAuthorization();
  Future<WorkoutExportReceipt> exportCompletedWorkout(
    CompletedWorkoutHealthExport workout,
  );
}

abstract interface class ExtensionSnapshotPlatform {
  Future<void> publish(NeutralExtensionSnapshot snapshot);
  Future<void> clear({required int minimumGeneration});
}

abstract interface class LiveActivityPlatform {
  Future<bool> start({required LiveActivityState state});
  Future<bool> update({required LiveActivityState state});
  Future<void> end(String sessionId);
  Future<void> endAll();

  /// Ob Live Activities in den iOS-Einstellungen für die App erlaubt sind.
  Future<bool> isEnabled();

  /// Öffnet die Einstellungen der App.
  Future<void> openSettings();
}

enum HealthExportStatus { saved, alreadyPresent }

enum HealthWriteStatus { saved, alreadyPresent, notAuthorized }

/// Schlafanalyse einer Nacht aus Apple Health.
class HealthSleepWindow {
  const HealthSleepWindow({
    required this.bedtimeUtc,
    required this.wakeUtc,
    required this.asleepMinutes,
    required this.sourceName,
    this.fromGainer = false,
  });

  final DateTime bedtimeUtc;
  final DateTime wakeUtc;
  final int asleepMinutes;
  final String sourceName;

  /// Wahr, wenn nur Gainer-eigene Proben vorliegen.
  final bool fromGainer;
}

class BodyMassSample {
  const BodyMassSample({
    required this.uuid,
    required this.measuredAtUtc,
    required this.weightKilograms,
    required this.sourceName,
    this.syncIdentifier,
  });

  final String uuid;
  final DateTime measuredAtUtc;
  final double weightKilograms;
  final String sourceName;

  /// `HKMetadataKeySyncIdentifier`; Gainer-Proben beginnen mit `gainer-checkin-`.
  final String? syncIdentifier;

  /// Gainer hat die Probe selbst geschrieben.
  bool get isFromGainer =>
      (syncIdentifier?.startsWith(checkInSyncPrefix) ?? false) ||
      sourceName == 'Gainer';
}

const checkInSyncPrefix = 'gainer-checkin-';

class CompletedWorkoutHealthExport {
  factory CompletedWorkoutHealthExport({
    required String accountId,
    required String workoutId,
    required String status,
    required int serverVersion,
    required DateTime startedAtUtc,
    required DateTime completedAtUtc,
  }) {
    if (status != 'completed' || serverVersion <= 0) {
      throw ArgumentError(
        'Health export requires a server-confirmed completed workout.',
      );
    }
    if (!startedAtUtc.isBefore(completedAtUtc)) {
      throw ArgumentError('Workout completion must be after its start.');
    }
    return CompletedWorkoutHealthExport._(
      accountId: accountId,
      workoutId: workoutId,
      serverVersion: serverVersion,
      startedAtUtc: startedAtUtc.toUtc(),
      completedAtUtc: completedAtUtc.toUtc(),
    );
  }

  const CompletedWorkoutHealthExport._({
    required this.accountId,
    required this.workoutId,
    required this.serverVersion,
    required this.startedAtUtc,
    required this.completedAtUtc,
  });

  final String accountId;
  final String workoutId;
  final int serverVersion;
  final DateTime startedAtUtc;
  final DateTime completedAtUtc;
}

class WorkoutExportReceipt {
  const WorkoutExportReceipt({
    required this.status,
    required this.syncIdentifier,
    required this.syncVersion,
  });

  final HealthExportStatus status;
  final String syncIdentifier;
  final int syncVersion;
}

/// Detailangaben der Live Activity. Nur bei ausdrücklicher Freigabe gesetzt.
/// Erfasste Ist-Werte gehören nie hierher; [targetText] ist nur der Zielwert des
/// nächsten Satzes aus dem Vorwert.
class LiveActivityDetail {
  const LiveActivityDetail({
    required this.title,
    required this.exerciseName,
    required this.setIndex,
    required this.setCount,
    this.exerciseIndex,
    this.exerciseCount,
    this.targetText,
  });

  final String title;
  final String exerciseName;
  final int setIndex;
  final int setCount;

  /// 1-basierte Position der Übung im Training.
  final int? exerciseIndex;
  final int? exerciseCount;

  /// Zielwert des nächsten Satzes aus dem Vorwert, z. B. „Ziel 60 kg × 10“.
  final String? targetText;

  @override
  bool operator ==(Object other) =>
      other is LiveActivityDetail &&
      other.title == title &&
      other.exerciseName == exerciseName &&
      other.setIndex == setIndex &&
      other.setCount == setCount &&
      other.exerciseIndex == exerciseIndex &&
      other.exerciseCount == exerciseCount &&
      other.targetText == targetText;

  @override
  int get hashCode => Object.hash(
    title,
    exerciseName,
    setIndex,
    setCount,
    exerciseIndex,
    exerciseCount,
    targetText,
  );
}

/// Neutraler Zustand einer Trainings-Live-Activity. Er enthält keine erfassten
/// Gewichte, Wiederholungen oder Kontodaten; die Restzeit leitet die Oberfläche
/// aus dem Zielzeitpunkt ab.
class LiveActivityState {
  const LiveActivityState({
    required this.sessionId,
    required this.timerPhase,
    required this.startedAtUtc,
    required this.staleAtUtc,
    this.timerTargetAtUtc,
    this.pausedRemainingSeconds,
    this.restDurationSeconds,
    this.detail,
  });

  /// Workout-ID; eine Activity je Training.
  final String sessionId;
  final RestTimerPhase timerPhase;
  final DateTime startedAtUtc;
  final DateTime staleAtUtc;

  /// Nur im Zustand laufender Pause.
  final DateTime? timerTargetAtUtc;

  /// Nur im Zustand pausierter Pause.
  final int? pausedRemainingSeconds;

  /// Dauer der aktuellen Pause (mindestens die Basisdauer); nur während einer
  /// laufenden oder pausierten Pause gesetzt, dient dem Fortschrittsbalken.
  final int? restDurationSeconds;

  /// Nur bei Detailfreigabe und vorhandenen Übungen.
  final LiveActivityDetail? detail;

  bool get expired => timerPhase == RestTimerPhase.expired;

  @override
  bool operator ==(Object other) =>
      other is LiveActivityState &&
      other.sessionId == sessionId &&
      other.timerPhase == timerPhase &&
      other.startedAtUtc == startedAtUtc &&
      other.staleAtUtc == staleAtUtc &&
      other.timerTargetAtUtc == timerTargetAtUtc &&
      other.pausedRemainingSeconds == pausedRemainingSeconds &&
      other.restDurationSeconds == restDurationSeconds &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(
    sessionId,
    timerPhase,
    startedAtUtc,
    staleAtUtc,
    timerTargetAtUtc,
    pausedRemainingSeconds,
    restDurationSeconds,
    detail,
  );
}

enum NativeAppRoute { training, checkIn, nutrition }

enum NativeRouteSource { widget, liveActivity, shortcut }

class NativeAppRouteRequest {
  const NativeAppRouteRequest({
    required this.destination,
    required this.source,
    required this.createdAtUtc,
  });

  final NativeAppRoute destination;
  final NativeRouteSource source;
  final DateTime createdAtUtc;
}

abstract interface class NativeRouteConsumer {
  /// Returns true only after the current app session/account is loaded and active.
  Future<bool> hasActiveAccountSession();
  Future<void> onRouteRequested(NativeAppRouteRequest request);
}

class NeutralExtensionSnapshot {
  const NeutralExtensionSnapshot({
    required this.schemaVersion,
    required this.generation,
    required this.updatedAtUtc,
    required this.availableRoutes,
  });

  final int schemaVersion;
  final int generation;
  final DateTime updatedAtUtc;
  final Set<String> availableRoutes;
}

enum HeartRateBluetoothState {
  unknown,
  poweredOn,
  poweredOff,
  unauthorized,
  unsupported,
  resetting,
}

enum HeartRateConnectionState { idle, connecting, connected, reconnecting }

/// Zonenstatus der nativen Überwachung.
enum HeartRateZoneState { none, inZone, above, below, noSignal }

/// Grund, warum Bluetooth nicht nutzbar ist.
enum BluetoothProblem { poweredOff, unauthorized, unsupported }

/// Bluetooth ist aus, nicht erlaubt oder fehlt; die Oberfläche erklärt den
/// Grund und verweist in die Einstellungen.
class BluetoothUnavailableException implements Exception {
  const BluetoothUnavailableException(this.problem);

  final BluetoothProblem problem;

  @override
  String toString() => 'BluetoothUnavailableException($problem)';
}

class HeartRateSensor {
  const HeartRateSensor({
    required this.id,
    required this.name,
    required this.isConnected,
    this.signalStrength,
  });

  final String id;
  final String name;
  final bool isConnected;
  final int? signalStrength;
}

/// Konfiguration der nativen Überwachung (Puffer, Zonenalarm, Live Activity).
class HeartRateMonitoringConfig {
  const HeartRateMonitoringConfig({
    required this.sessionId,
    required this.title,
    required this.startedAtUtc,
    required this.soundId,
    this.zoneLowBpm,
    this.zoneHighBpm,
    this.graceSeconds = 15,
    this.repeatSeconds = 60,
    this.warmupSeconds = 180,
    this.alertsEnabled = true,
    this.liveActivityEnabled = true,
    this.phases = const [],
    this.voiceEnabled = false,
    this.voiceIntervalMinutes = 0,
  });

  final String sessionId;
  final String title;
  final DateTime startedAtUtc;
  final String soundId;
  final int? zoneLowBpm;
  final int? zoneHighBpm;
  final int graceSeconds;
  final int repeatSeconds;
  final int warmupSeconds;
  final bool alertsEnabled;
  final bool liveActivityEnabled;

  /// Aufgelöste Phasen einer Vorlage; leer = ein fester Zielbereich.
  final List<CardioPhase> phases;

  /// Sprachansagen und Intervall der Zeitansage in Minuten (0 = aus).
  final bool voiceEnabled;
  final int voiceIntervalMinutes;

  @override
  bool operator ==(Object other) =>
      other is HeartRateMonitoringConfig &&
      other.sessionId == sessionId &&
      other.title == title &&
      other.startedAtUtc == startedAtUtc &&
      other.soundId == soundId &&
      other.zoneLowBpm == zoneLowBpm &&
      other.zoneHighBpm == zoneHighBpm &&
      other.graceSeconds == graceSeconds &&
      other.repeatSeconds == repeatSeconds &&
      other.warmupSeconds == warmupSeconds &&
      other.alertsEnabled == alertsEnabled &&
      other.liveActivityEnabled == liveActivityEnabled &&
      listEquals(other.phases, phases) &&
      other.voiceEnabled == voiceEnabled &&
      other.voiceIntervalMinutes == voiceIntervalMinutes;

  @override
  int get hashCode => Object.hash(
    sessionId,
    title,
    startedAtUtc,
    soundId,
    zoneLowBpm,
    zoneHighBpm,
    graceSeconds,
    repeatSeconds,
    warmupSeconds,
    alertsEnabled,
    liveActivityEnabled,
    Object.hashAll(phases),
    voiceEnabled,
    voiceIntervalMinutes,
  );
}

class HeartRateStatus {
  const HeartRateStatus({
    this.bluetoothState = HeartRateBluetoothState.unknown,
    this.connectionState = HeartRateConnectionState.idle,
    this.lastSequence = 0,
    this.samples = const [],
    this.sensorId,
    this.sensorName,
    this.batteryPercent,
    this.latestBpm,
    this.latestAtUtc,
    this.monitoringSessionId,
    this.zoneState,
  });

  final HeartRateBluetoothState bluetoothState;
  final HeartRateConnectionState connectionState;
  final int lastSequence;

  /// Messwerte nach der angefragten Sequenz, aufsteigend.
  final List<CardioSample> samples;
  final String? sensorId;
  final String? sensorName;
  final int? batteryPercent;
  final int? latestBpm;
  final DateTime? latestAtUtc;

  /// Session der laufenden nativen Überwachung; null, wenn keine läuft.
  final String? monitoringSessionId;
  final HeartRateZoneState? zoneState;
}

/// Pulsgurt und native Cardio-Überwachung. Bluetooth-Probleme melden sich als
/// [BluetoothUnavailableException].
abstract interface class HeartRatePlatform {
  Future<HeartRateStatus> readStatus(int afterSequence);
  Future<List<HeartRateSensor>> scan(Duration duration);

  /// False, wenn der Gurt unbekannt ist.
  Future<bool> connect(String sensorId);

  /// Trennt und vergisst den gemerkten Gurt.
  Future<void> disconnect();
  Future<void> startMonitoring(HeartRateMonitoringConfig config);
  Future<void> updateMonitoring(HeartRateMonitoringConfig config);
  Future<void> stopMonitoring(String sessionId);
}

/// Beendete Cardio-Einheit für den Export nach Apple Health.
class CardioHealthExport {
  const CardioHealthExport({
    required this.accountId,
    required this.sessionId,
    required this.syncVersion,
    required this.activityType,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.sampleIntervalSeconds,
    required this.heartRateBpm,
    this.distanceKm,
    this.energyKcal,
  });

  final String accountId;
  final String sessionId;
  final int syncVersion;
  final String activityType;
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
  final int sampleIntervalSeconds;
  final List<int> heartRateBpm;
  final double? distanceKm;
  final double? energyKcal;
}

abstract interface class CardioHealthPlatform {
  Future<void> requestWriteAuthorization();
  Future<WorkoutExportReceipt> exportCardioSession(CardioHealthExport export);
}

/// Anmelde-Sheet des Systems für OAuth (z. B. Strava).
abstract interface class WebAuthenticationPlatform {
  /// Rückleitung auf [callbackScheme]; null, wenn der Nutzer abbricht.
  Future<Uri?> authenticate(Uri url, {required String callbackScheme});
}
