import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/data/services/platform/generated/mobile_platform_api.dart',
    swiftOut: 'ios/Runner/MobilePlatformApi.g.swift',
    dartPackageName: 'gainer_mobile',
  ),
)
class PlatformHealthCheck {
  const PlatformHealthCheck({required this.available});

  final bool available;
}

/// Reports that an authorization request finished, not that access was granted.
enum PlatformAuthorizationRequestResult { requestCompleted }

/// Ergebnis eines Schreibversuchs nach Apple Health.
enum PlatformHealthWriteStatus { saved, alreadyPresent, notAuthorized }

class PlatformCapturedImage {
  const PlatformCapturedImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

class PlatformBodyMassSample {
  const PlatformBodyMassSample({
    required this.uuid,
    required this.measuredAtUtcEpochMilliseconds,
    required this.weightKilograms,
    required this.sourceName,
    this.syncIdentifier,
  });

  final String uuid;
  final int measuredAtUtcEpochMilliseconds;
  final double weightKilograms;
  final String sourceName;

  /// `HKMetadataKeySyncIdentifier` der Probe; null bei fremden Quellen.
  final String? syncIdentifier;
}

/// Schlafanalyse einer Nacht: früheste Einschlafzeit bis späteste Aufwachzeit.
class PlatformSleepWindow {
  const PlatformSleepWindow({
    required this.bedtimeUtcEpochMilliseconds,
    required this.wakeUtcEpochMilliseconds,
    required this.asleepMinutes,
    required this.sourceName,
    required this.fromGainer,
  });

  final int bedtimeUtcEpochMilliseconds;
  final int wakeUtcEpochMilliseconds;
  final int asleepMinutes;
  final String sourceName;

  /// Wahr, wenn nur Gainer-eigene Proben vorliegen.
  final bool fromGainer;
}

class PlatformWorkoutExportResult {
  const PlatformWorkoutExportResult({
    required this.status,
    required this.syncIdentifier,
    required this.syncVersion,
  });

  final String status;
  final String syncIdentifier;
  final int syncVersion;
}

class PlatformLiveActivityDetail {
  const PlatformLiveActivityDetail({
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
}

/// Neutraler Zustand der Trainings-Live-Activity. Restzeiten werden aus dem
/// Zielzeitpunkt berechnet, nicht hochgezählt.
class PlatformLiveActivityState {
  const PlatformLiveActivityState({
    required this.sessionId,
    required this.timerPhase,
    required this.startedAtUtcEpochMilliseconds,
    required this.expired,
    required this.staleAtUtcEpochMilliseconds,
    this.timerTargetAtUtcEpochMilliseconds,
    this.pausedRemainingSeconds,
    this.restDurationSeconds,
    this.detail,
  });

  final String sessionId;

  /// One of `ready`, `running`, `paused`, `expired`.
  final String timerPhase;
  final int startedAtUtcEpochMilliseconds;
  final bool expired;
  final int staleAtUtcEpochMilliseconds;
  final int? timerTargetAtUtcEpochMilliseconds;
  final int? pausedRemainingSeconds;

  /// Dauer der aktuellen Pause in Sekunden; fehlt ohne Pause.
  final int? restDurationSeconds;
  final PlatformLiveActivityDetail? detail;
}

class PlatformRoute {
  const PlatformRoute({
    required this.destination,
    required this.source,
    required this.createdAtUtcEpochMilliseconds,
  });

  final String destination;
  final String source;
  final int createdAtUtcEpochMilliseconds;
}

/// Gefundener Pulsgurt mit Heart Rate Service (0x180D).
class PlatformHeartRateSensor {
  const PlatformHeartRateSensor({
    required this.id,
    required this.name,
    required this.isConnected,
    this.signalStrength,
  });

  /// `CBPeripheral.identifier` als UUID-String.
  final String id;
  final String name;
  final bool isConnected;

  /// RSSI in dBm; fehlt bei schon verbundenen Gurten.
  final int? signalStrength;
}

/// Ein Messwert des Gurts mit fortlaufender Sequenz je Überwachung.
class PlatformHeartRateSample {
  const PlatformHeartRateSample({
    required this.sequence,
    required this.atUtcEpochMilliseconds,
    required this.bpm,
    required this.rrIntervalsMs,
  });

  final int sequence;
  final int atUtcEpochMilliseconds;
  final int bpm;

  /// RR-Intervalle dieses Messwerts in ms, umgerechnet aus 1/1024 s.
  final List<int> rrIntervalsMs;
}

/// Phase einer Intervall-Vorlage mit eigenem Zielbereich.
class PlatformCardioPhase {
  const PlatformCardioPhase({
    required this.startOffsetSeconds,
    required this.durationSeconds,
    required this.name,
    this.zoneLowBpm,
    this.zoneHighBpm,
  });

  /// Sekunden ab Start der Einheit.
  final int startOffsetSeconds;
  final int durationSeconds;
  final String name;
  final int? zoneLowBpm;
  final int? zoneHighBpm;
}

/// Konfiguration der nativen Cardio-Überwachung (Puffer, Zonenalarm, Live Activity).
class PlatformCardioMonitoringConfig {
  const PlatformCardioMonitoringConfig({
    required this.sessionId,
    required this.title,
    required this.startedAtUtcEpochMilliseconds,
    required this.graceSeconds,
    required this.repeatSeconds,
    required this.warmupSeconds,
    required this.soundId,
    required this.alertsEnabled,
    required this.liveActivityEnabled,
    this.zoneLowBpm,
    this.zoneHighBpm,
    this.phases,
    this.voiceEnabled,
    this.voiceIntervalMinutes,
  });

  final String sessionId;

  /// Anzeigename der Sportart, z. B. „Rad-Ergometer“.
  final String title;
  final int startedAtUtcEpochMilliseconds;
  final int graceSeconds;
  final int repeatSeconds;
  final int warmupSeconds;

  /// Timerton für Alarme, siehe `playTimerSound`.
  final String soundId;
  final bool alertsEnabled;
  final bool liveActivityEnabled;

  /// Zielbereich ohne Phasen bzw. nach der letzten Phase.
  final int? zoneLowBpm;
  final int? zoneHighBpm;

  /// Phasen einer Vorlage, aufsteigend und ohne Überlappung; null oder leer
  /// heißt freie Einheit mit [zoneLowBpm]/[zoneHighBpm].
  final List<PlatformCardioPhase>? phases;

  /// Sprachansagen für Alarme und Phasenwechsel; null = aus.
  final bool? voiceEnabled;

  /// Regelmäßige Ansage von Dauer und Puls in Minuten; null oder 0 = aus.
  final int? voiceIntervalMinutes;
}

/// Zustand von Bluetooth, Gurt und Überwachung samt neuen Messwerten.
class PlatformHeartRateStatus {
  const PlatformHeartRateStatus({
    required this.bluetoothState,
    required this.connectionState,
    required this.lastSequence,
    required this.samples,
    this.sensorId,
    this.sensorName,
    this.batteryPercent,
    this.latestBpm,
    this.latestAtUtcEpochMilliseconds,
    this.monitoringSessionId,
    this.zoneState,
  });

  /// One of `unknown`, `poweredOn`, `poweredOff`, `unauthorized`, `unsupported`, `resetting`.
  final String bluetoothState;

  /// One of `idle`, `connecting`, `connected`, `reconnecting`.
  final String connectionState;

  /// Höchste vergebene Sequenz der laufenden Überwachung, 0 ohne Werte.
  final int lastSequence;

  /// Messwerte mit Sequenz größer als die angefragte, aufsteigend.
  final List<PlatformHeartRateSample> samples;
  final String? sensorId;
  final String? sensorName;
  final int? batteryPercent;
  final int? latestBpm;
  final int? latestAtUtcEpochMilliseconds;

  /// Session der laufenden Überwachung; null, wenn keine läuft.
  final String? monitoringSessionId;

  /// One of `none`, `inZone`, `above`, `below`, `noSignal`; null ohne Überwachung.
  final String? zoneState;
}

/// Beendete Cardio-Einheit für den Export nach Apple Health.
class PlatformCardioExport {
  const PlatformCardioExport({
    required this.accountId,
    required this.sessionId,
    required this.syncVersion,
    required this.activityType,
    required this.startedAtUtcEpochMilliseconds,
    required this.endedAtUtcEpochMilliseconds,
    required this.sampleIntervalSeconds,
    required this.heartRateBpm,
    this.distanceKm,
    this.energyKcal,
  });

  final String accountId;
  final String sessionId;
  final int syncVersion;

  /// `IndoorCycling`.
  final String activityType;
  final int startedAtUtcEpochMilliseconds;
  final int endedAtUtcEpochMilliseconds;
  final int sampleIntervalSeconds;

  /// Ein Wert je Intervall ab Start, 0 = kein Signal.
  final List<int> heartRateBpm;
  final double? distanceKm;
  final double? energyKcal;
}

/// Rohdaten eines neu erstellten Passkeys; Dart setzt daraus die WebAuthn-Antwort zusammen.
class PlatformPasskeyRegistration {
  const PlatformPasskeyRegistration({
    required this.credentialId,
    required this.clientDataJson,
    required this.attestationObject,
  });

  final Uint8List credentialId;
  final Uint8List clientDataJson;
  final Uint8List attestationObject;
}

/// Rohdaten einer Passkey-Anmeldung.
class PlatformPasskeyAssertion {
  const PlatformPasskeyAssertion({
    required this.credentialId,
    required this.clientDataJson,
    required this.authenticatorData,
    required this.signature,
    required this.userHandle,
  });

  final Uint8List credentialId;
  final Uint8List clientDataJson;
  final Uint8List authenticatorData;
  final Uint8List signature;
  final Uint8List userHandle;
}

/// Stand des Diktats. [status] ist `idle`, `listening`, `finished`,
/// `denied`, `unavailable` oder `failed`.
class PlatformDictationState {
  PlatformDictationState({required this.status, required this.transcript});

  String status;
  String transcript;
}

@HostApi()
abstract class MobilePlatformApi {
  @async
  PlatformHealthCheck getPlatformHealth();

  @async
  Uint8List? readSessionCheckpoint(String apiOrigin);

  @async
  void writeSessionCheckpoint(String apiOrigin, Uint8List checkpoint);

  @async
  void clearSessionCheckpoint(String apiOrigin);

  @async
  Uint8List? readPendingHandover(String apiOrigin, String accountId);

  @async
  void writePendingHandover(
    String apiOrigin,
    String accountId,
    Uint8List record,
  );

  @async
  void clearPendingHandover(String apiOrigin, String accountId);

  @async
  String? scanBarcode();

  @async
  PlatformCapturedImage? capturePhoto();

  @async
  PlatformCapturedImage? chooseImage();

  @async
  void performHaptic(String intent);

  @async
  bool requestNotificationPermission();

  @async
  void schedulePauseNotification(
    String workoutId,
    int generation,
    int targetAtUtcEpochMilliseconds,
    String soundId,
  );

  /// Spielt einen Timerton in der App (Vorschau und Ablauf im Vordergrund).
  /// Unbekannte IDs fallen auf den Standardton zurück.
  @async
  void playTimerSound(String soundId);

  @async
  void cancelPauseNotifications(String workoutId);

  @async
  bool isHealthDataAvailable();

  /// Completes when the system authorization sheet has been handled.
  /// The result does not indicate read permission; HealthKit intentionally
  /// hides read authorization, so an empty query remains an empty result.
  @async
  PlatformAuthorizationRequestResult requestBodyMassReadAuthorization();

  @async
  List<PlatformBodyMassSample> readBodyMassSamples(
    int fromUtcEpochMilliseconds,
    int toUtcEpochMilliseconds,
  );

  /// Fragt Lesen (Gewicht, Schritte, Schlaf) und Schreiben (Gewicht, Schlaf)
  /// für den Check-in in einem Systemdialog an.
  @async
  PlatformAuthorizationRequestResult requestCheckInAuthorization();

  /// Tagessumme der Schritte; null ohne Daten.
  @async
  int? readStepCount(int fromUtcEpochMilliseconds, int toUtcEpochMilliseconds);

  @async
  PlatformSleepWindow? readSleep(
    int fromUtcEpochMilliseconds,
    int toUtcEpochMilliseconds,
  );

  @async
  PlatformHealthWriteStatus writeBodyMass(
    double kilograms,
    int measuredAtUtcEpochMilliseconds,
    String syncIdentifier,
  );

  @async
  PlatformHealthWriteStatus writeSleep(
    int bedtimeUtcEpochMilliseconds,
    int wakeUtcEpochMilliseconds,
    String syncIdentifier,
  );

  @async
  PlatformAuthorizationRequestResult requestWorkoutWriteAuthorization();

  @async
  PlatformWorkoutExportResult exportCompletedWorkout(
    String accountId,
    String workoutId,
    int syncVersion,
    int startedAtUtcEpochMilliseconds,
    int completedAtUtcEpochMilliseconds,
  );

  @async
  void publishNeutralExtensionSnapshot(
    int schemaVersion,
    int generation,
    int updatedAtUtcEpochMilliseconds,
    List<String> availableRoutes,
  );

  @async
  void clearExtensionSnapshot(int minimumGeneration);

  @async
  bool startLiveActivity(PlatformLiveActivityState state);

  @async
  bool updateLiveActivity(PlatformLiveActivityState state);

  @async
  void endLiveActivity(String sessionId);

  @async
  void endAllLiveActivities();

  /// Ob Live Activities für die App in den iOS-Einstellungen erlaubt sind.
  @async
  bool areLiveActivitiesEnabled();

  /// Öffnet die Einstellungen der App, z. B. um Live Activities einzuschalten.
  @async
  void openAppSettings();

  @async
  PlatformRoute? readPendingRoute();

  @async
  void clearPendingRoute();

  @async
  void retryPendingRoute();

  /// Zustand von Bluetooth und Gurt sowie Messwerte nach [afterSequence].
  @async
  PlatformHeartRateStatus readHeartRateStatus(int afterSequence);

  /// Sucht [durationMilliseconds] lang nach Pulsgurten; enthält schon verbundene.
  @async
  List<PlatformHeartRateSensor> scanHeartRateSensors(int durationMilliseconds);

  /// Verbindet und merkt den Gurt; verbindet nach Abbrüchen selbst neu.
  /// False, wenn der Gurt unbekannt ist.
  @async
  bool connectHeartRateSensor(String sensorId);

  /// Trennt und vergisst den gemerkten Gurt.
  @async
  void disconnectHeartRateSensor();

  /// Startet Puffer, Zonenalarm und ggf. Live Activity; ersetzt eine laufende Überwachung.
  @async
  void startCardioMonitoring(PlatformCardioMonitoringConfig config);

  /// Ändert Zielbereich und Optionen, ohne Puffer und Sequenzen zurückzusetzen.
  @async
  void updateCardioMonitoring(PlatformCardioMonitoringConfig config);

  /// Beendet Puffer, Alarm und Live Activity der Session.
  @async
  void stopCardioMonitoring(String sessionId);

  @async
  PlatformAuthorizationRequestResult requestCardioWriteAuthorization();

  @async
  PlatformWorkoutExportResult exportCardioSession(PlatformCardioExport export);

  /// Erstellt mit Face ID einen Passkey für die Domain [relyingPartyId].
  /// Null, wenn der Nutzer abbricht.
  @async
  PlatformPasskeyRegistration? createPasskey(
    String relyingPartyId,
    Uint8List challenge,
    Uint8List userId,
    String userName,
  );

  /// Meldet mit einem gespeicherten Passkey der Domain an. Null bei Abbruch
  /// oder wenn kein Passkey vorhanden ist.
  @async
  PlatformPasskeyAssertion? assertPasskey(
    String relyingPartyId,
    Uint8List challenge,
  );

  /// Öffnet [url] im Anmelde-Sheet des Systems (ASWebAuthenticationSession,
  /// teilt die Anmeldung mit Safari) und liefert die Rückleitung auf
  /// [callbackScheme]. Null, wenn der Nutzer abbricht.
  @async
  String? authenticateWebSession(String url, String callbackScheme);

  /// Startet das Diktat mit Spracherkennung nur auf dem Gerät. Fragt beim
  /// ersten Mal Mikrofon und Spracherkennung an.
  @async
  PlatformDictationState startDictation(String localeId);

  /// Aktueller Text und Zustand des Diktats.
  @async
  PlatformDictationState readDictation();

  /// Beendet die Aufnahme; der endgültige Text folgt über [readDictation].
  @async
  void stopDictation();

  /// Bricht das Diktat ab und verwirft den Text.
  @async
  void cancelDictation();
}

@FlutterApi()
abstract class MobileRouteFlutterApi {
  @async
  void dispatchRoute(PlatformRoute route);
}
