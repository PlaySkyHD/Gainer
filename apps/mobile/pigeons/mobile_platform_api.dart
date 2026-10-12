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
  });

  final String uuid;
  final int measuredAtUtcEpochMilliseconds;
  final double weightKilograms;
  final String sourceName;
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
  );

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
  bool startLiveActivity(
    String sessionId,
    String status,
    int startedAtUtcEpochMilliseconds,
    int? restEndsAtUtcEpochMilliseconds,
    int staleAtUtcEpochMilliseconds,
  );

  @async
  bool updateLiveActivity(
    String sessionId,
    String status,
    int startedAtUtcEpochMilliseconds,
    int? restEndsAtUtcEpochMilliseconds,
    int staleAtUtcEpochMilliseconds,
  );

  @async
  void endLiveActivity(String sessionId);

  @async
  void endAllLiveActivities();

  @async
  PlatformRoute? readPendingRoute();

  @async
  void clearPendingRoute();
}

@FlutterApi()
abstract class MobileRouteFlutterApi {
  void dispatchRoute(PlatformRoute route);
}
