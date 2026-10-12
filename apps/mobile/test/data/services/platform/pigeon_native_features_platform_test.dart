import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_native_features_platform.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';

class _FakeMobilePlatformApi extends MobilePlatformApi {
  String? barcode;
  PlatformCapturedImage? pickerImage;
  PlatformCapturedImage? cameraImage;
  final List<String> haptics = [];
  final List<(String, int, int)> scheduled = [];
  final List<String> cancelled = [];
  bool permissionGranted = false;
  bool healthAvailable = true;
  PlatformAuthorizationRequestResult healthRequestCompleted =
      PlatformAuthorizationRequestResult.requestCompleted;
  PlatformAuthorizationRequestResult workoutRequestCompleted =
      PlatformAuthorizationRequestResult.requestCompleted;
  List<PlatformBodyMassSample> bodyMassSamples = [];
  PlatformWorkoutExportResult exportResult = PlatformWorkoutExportResult(
    status: 'saved',
    syncIdentifier: 'gainer.health.workout.v1.opaque',
    syncVersion: 1,
  );
  final List<(int, int, int, List<String>)> snapshots = [];
  final List<(String, String, int, int, int?, int)> liveActivityCalls = [];
  final List<String> endedActivities = [];
  int clearedSnapshots = 0;

  @override
  Future<String?> scanBarcode() async => barcode;

  @override
  Future<PlatformCapturedImage?> capturePhoto() async => cameraImage;

  @override
  Future<PlatformCapturedImage?> chooseImage() async => pickerImage;

  @override
  Future<void> performHaptic(String intent) async => haptics.add(intent);

  @override
  Future<bool> requestNotificationPermission() async => permissionGranted;

  @override
  Future<void> schedulePauseNotification(
    String workoutId,
    int generation,
    int targetAtUtcEpochMilliseconds,
  ) async {
    scheduled.add((workoutId, generation, targetAtUtcEpochMilliseconds));
  }

  @override
  Future<void> cancelPauseNotifications(String workoutId) async =>
      cancelled.add(workoutId);

  @override
  Future<bool> isHealthDataAvailable() async => healthAvailable;

  @override
  Future<PlatformAuthorizationRequestResult>
  requestBodyMassReadAuthorization() async => healthRequestCompleted;

  @override
  Future<List<PlatformBodyMassSample>> readBodyMassSamples(
    int fromUtcEpochMilliseconds,
    int toUtcEpochMilliseconds,
  ) async => bodyMassSamples;

  @override
  Future<PlatformAuthorizationRequestResult>
  requestWorkoutWriteAuthorization() async => workoutRequestCompleted;

  @override
  Future<PlatformWorkoutExportResult> exportCompletedWorkout(
    String accountId,
    String workoutId,
    int syncVersion,
    int startedAtUtcEpochMilliseconds,
    int completedAtUtcEpochMilliseconds,
  ) async => exportResult;

  @override
  Future<void> publishNeutralExtensionSnapshot(
    int schemaVersion,
    int generation,
    int updatedAtUtcEpochMilliseconds,
    List<String> availableRoutes,
  ) async => snapshots.add((
    schemaVersion,
    generation,
    updatedAtUtcEpochMilliseconds,
    availableRoutes,
  ));

  @override
  Future<void> clearExtensionSnapshot(int minimumGeneration) async {
    clearedSnapshots++;
  }

  @override
  Future<bool> startLiveActivity(
    String sessionId,
    String status,
    int startedAtUtcEpochMilliseconds,
    int? restEndsAtUtcEpochMilliseconds,
    int staleAtUtcEpochMilliseconds,
  ) async {
    liveActivityCalls.add((
      'start',
      sessionId,
      status == 'rest' ? 1 : 0,
      startedAtUtcEpochMilliseconds,
      restEndsAtUtcEpochMilliseconds,
      staleAtUtcEpochMilliseconds,
    ));
    return true;
  }

  @override
  Future<bool> updateLiveActivity(
    String sessionId,
    String status,
    int startedAtUtcEpochMilliseconds,
    int? restEndsAtUtcEpochMilliseconds,
    int staleAtUtcEpochMilliseconds,
  ) async {
    liveActivityCalls.add((
      'update',
      sessionId,
      status == 'rest' ? 1 : 0,
      startedAtUtcEpochMilliseconds,
      restEndsAtUtcEpochMilliseconds,
      staleAtUtcEpochMilliseconds,
    ));
    return true;
  }

  @override
  Future<void> endLiveActivity(String sessionId) async =>
      endedActivities.add(sessionId);

  @override
  Future<void> endAllLiveActivities() async => endedActivities.add('*');
}

void main() {
  test('capture methods preserve barcode, bytes, and MIME type', () async {
    final api = _FakeMobilePlatformApi()
      ..barcode = '0123456789012'
      ..cameraImage = PlatformCapturedImage(
        bytes: Uint8List.fromList([1, 2]),
        mimeType: 'image/jpeg',
      )
      ..pickerImage = PlatformCapturedImage(
        bytes: Uint8List.fromList([3, 4]),
        mimeType: 'image/jpeg',
      );
    final platform = PigeonNativeFeaturesPlatform(api: api);

    expect(await platform.scanBarcode(), '0123456789012');
    expect((await platform.capturePhoto())?.bytes, [1, 2]);
    expect((await platform.chooseImage())?.mimeType, 'image/jpeg');
  });

  test('timer and haptic ports map their stable values to Pigeon', () async {
    final api = _FakeMobilePlatformApi()..permissionGranted = true;
    final platform = PigeonNativeFeaturesPlatform(api: api);
    final target = DateTime.utc(2026, 10, 12, 9, 30);

    expect(await platform.requestPermission(), isTrue);
    await platform.schedule(
      workoutId: 'workout-opaque-id',
      generation: 7,
      targetAtUtc: target,
    );
    await platform.cancel('workout-opaque-id');
    await platform.perform(HapticIntent.commit);
    await platform.perform(HapticIntent.timerComplete);
    await platform.perform(HapticIntent.success);

    expect(api.scheduled, [
      ('workout-opaque-id', 7, target.millisecondsSinceEpoch),
    ]);
    expect(api.cancelled, ['workout-opaque-id']);
    expect(api.haptics, ['commit', 'timerComplete', 'success']);
  });

  test(
    'HealthKit ports preserve samples and completed export identity',
    () async {
      final api = _FakeMobilePlatformApi()
        ..bodyMassSamples = [
          PlatformBodyMassSample(
            uuid: 'sample-id',
            measuredAtUtcEpochMilliseconds: 1_791_805_800_000,
            weightKilograms: 72.25,
            sourceName: 'Health',
          ),
        ];
      final platform = PigeonNativeFeaturesPlatform(api: api);
      final request = CompletedWorkoutHealthExport(
        accountId: 'd8ff16ea-672f-4ac3-a978-2666ee8b0a5f',
        workoutId: '849da1bf-4326-4bfb-b06e-80f994f80044',
        status: 'completed',
        serverVersion: 9,
        startedAtUtc: DateTime.utc(2026, 10, 12, 9),
        completedAtUtc: DateTime.utc(2026, 10, 12, 10),
      );

      expect(await platform.isAvailable(), isTrue);
      expect(
        await platform.requestBodyMassReadAuthorization(),
        PlatformAuthorizationRequestResult.requestCompleted,
      );
      expect(
        await platform.requestWorkoutWriteAuthorization(),
        PlatformAuthorizationRequestResult.requestCompleted,
      );
      final samples = await platform.readBodyMassSamples(
        fromUtc: DateTime.utc(2026, 10, 1),
        toUtc: DateTime.utc(2026, 10, 12),
      );
      expect(samples.single.weightKilograms, 72.25);
      expect(samples.single.measuredAtUtc.isUtc, isTrue);
      final receipt = await platform.exportCompletedWorkout(request);
      expect(receipt.status, HealthExportStatus.saved);
      expect(receipt.syncIdentifier, startsWith('gainer.health.workout.v1.'));
      expect(receipt.syncVersion, 1);
    },
  );

  test(
    'extension and Live Activity ports send only neutral route/time state',
    () async {
      final api = _FakeMobilePlatformApi();
      final platform = PigeonNativeFeaturesPlatform(api: api);
      final updateAt = DateTime.utc(2026, 10, 12, 10);
      final restEnd = updateAt.add(const Duration(minutes: 2));
      final staleAt = updateAt.add(const Duration(hours: 1));
      final liveState = LiveActivityState(
        sessionId: '849da1bf-4326-4bfb-b06e-80f994f80044',
        status: LiveActivityStatus.rest,
        startedAtUtc: updateAt,
        staleAtUtc: staleAt,
        restEndsAtUtc: restEnd,
      );
      await platform.publish(
        NeutralExtensionSnapshot(
          schemaVersion: 1,
          generation: 4,
          updatedAtUtc: updateAt,
          availableRoutes: {'training', 'checkIn'},
        ),
      );
      expect(await platform.start(state: liveState), isTrue);
      expect(await platform.update(state: liveState), isTrue);
      await platform.end(liveState.sessionId);
      await platform.endAll();
      await platform.clear(minimumGeneration: 6);

      expect(api.snapshots.single.$1, 1);
      expect(api.snapshots.single.$2, 4);
      expect(api.snapshots.single.$4, ['checkIn', 'training']);
      expect(api.liveActivityCalls.map((call) => call.$1), ['start', 'update']);
      expect(api.liveActivityCalls.first.$3, 1);
      expect(api.liveActivityCalls.first.$5, restEnd.millisecondsSinceEpoch);
      expect(api.endedActivities, [liveState.sessionId, '*']);
      expect(api.clearedSnapshots, 1);
    },
  );

  test('uncompleted workouts cannot be wrapped in a Health export request', () {
    expect(
      () => CompletedWorkoutHealthExport(
        accountId: 'd8ff16ea-672f-4ac3-a978-2666ee8b0a5f',
        workoutId: '849da1bf-4326-4bfb-b06e-80f994f80044',
        status: 'running',
        serverVersion: 1,
        startedAtUtc: DateTime.utc(2026, 10, 12, 9),
        completedAtUtc: DateTime.utc(2026, 10, 12, 10),
      ),
      throwsArgumentError,
    );
  });
}
