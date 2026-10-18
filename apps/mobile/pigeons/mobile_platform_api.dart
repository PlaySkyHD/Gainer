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
}

@FlutterApi()
abstract class MobileRouteFlutterApi {
  @async
  void dispatchRoute(PlatformRoute route);
}
