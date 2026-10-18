import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_native_features_platform.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';

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
  int checkInRequests = 0;
  int? stepCount = 8432;
  PlatformSleepWindow? sleepWindow;
  PlatformHealthWriteStatus writeStatus = PlatformHealthWriteStatus.saved;
  final List<(double, int, String)> bodyMassWrites = [];
  final List<(int, int, String)> sleepWrites = [];
  final List<(int, int)> stepRanges = [];
  PlatformWorkoutExportResult exportResult = PlatformWorkoutExportResult(
    status: 'saved',
    syncIdentifier: 'gainer.health.workout.v1.opaque',
    syncVersion: 1,
  );
  final List<(int, int, int, List<String>)> snapshots = [];
  final List<(String, PlatformLiveActivityState)> liveActivityCalls = [];
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
  requestCheckInAuthorization() async {
    checkInRequests++;
    return PlatformAuthorizationRequestResult.requestCompleted;
  }

  @override
  Future<int?> readStepCount(
    int fromUtcEpochMilliseconds,
    int toUtcEpochMilliseconds,
  ) async {
    stepRanges.add((fromUtcEpochMilliseconds, toUtcEpochMilliseconds));
    return stepCount;
  }

  @override
  Future<PlatformSleepWindow?> readSleep(
    int fromUtcEpochMilliseconds,
    int toUtcEpochMilliseconds,
  ) async => sleepWindow;

  @override
  Future<PlatformHealthWriteStatus> writeBodyMass(
    double kilograms,
    int measuredAtUtcEpochMilliseconds,
    String syncIdentifier,
  ) async {
    bodyMassWrites.add((
      kilograms,
      measuredAtUtcEpochMilliseconds,
      syncIdentifier,
    ));
    return writeStatus;
  }

  @override
  Future<PlatformHealthWriteStatus> writeSleep(
    int bedtimeUtcEpochMilliseconds,
    int wakeUtcEpochMilliseconds,
    String syncIdentifier,
  ) async {
    sleepWrites.add((
      bedtimeUtcEpochMilliseconds,
      wakeUtcEpochMilliseconds,
      syncIdentifier,
    ));
    return writeStatus;
  }

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
  Future<bool> startLiveActivity(PlatformLiveActivityState state) async {
    liveActivityCalls.add(('start', state));
    return true;
  }

  @override
  Future<bool> updateLiveActivity(PlatformLiveActivityState state) async {
    liveActivityCalls.add(('update', state));
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

  test('Check-in-Port bildet Schritte, Schlaf und Sync-ID ab', () async {
    final api = _FakeMobilePlatformApi()
      ..bodyMassSamples = [
        PlatformBodyMassSample(
          uuid: 'own',
          measuredAtUtcEpochMilliseconds: 1_791_805_800_000,
          weightKilograms: 80.9,
          sourceName: 'Gainer',
          syncIdentifier: 'gainer-checkin-a-2026-10-12-weight',
        ),
        PlatformBodyMassSample(
          uuid: 'foreign',
          measuredAtUtcEpochMilliseconds: 1_791_805_800_000,
          weightKilograms: 81.4,
          sourceName: 'Waage',
        ),
      ]
      ..sleepWindow = PlatformSleepWindow(
        bedtimeUtcEpochMilliseconds: 1_791_760_000_000,
        wakeUtcEpochMilliseconds: 1_791_787_500_000,
        asleepMinutes: 450,
        sourceName: 'Watch',
        fromGainer: false,
      );
    final platform = PigeonNativeFeaturesPlatform(api: api);

    expect(
      await platform.requestCheckInAuthorization(),
      PlatformAuthorizationRequestResult.requestCompleted,
    );
    expect(api.checkInRequests, 1);
    expect(
      await platform.readStepCount(
        fromUtc: DateTime.utc(2026, 10, 12),
        toUtc: DateTime.utc(2026, 10, 13),
      ),
      8432,
    );
    expect(api.stepRanges.single, (
      DateTime.utc(2026, 10, 12).millisecondsSinceEpoch,
      DateTime.utc(2026, 10, 13).millisecondsSinceEpoch,
    ));
    api.stepCount = null;
    expect(
      await platform.readStepCount(
        fromUtc: DateTime.utc(2026, 10, 12),
        toUtc: DateTime.utc(2026, 10, 13),
      ),
      isNull,
    );

    final sleep = (await platform.readSleep(
      fromUtc: DateTime.utc(2026, 10, 11, 16),
      toUtc: DateTime.utc(2026, 10, 12, 12),
    ))!;
    expect(sleep.bedtimeUtc.isUtc, isTrue);
    expect(sleep.wakeUtc.difference(sleep.bedtimeUtc).inMinutes, 458);
    expect(sleep.asleepMinutes, 450);
    expect(sleep.sourceName, 'Watch');
    expect(sleep.fromGainer, isFalse);
    api.sleepWindow = null;
    expect(
      await platform.readSleep(
        fromUtc: DateTime.utc(2026, 10, 11, 16),
        toUtc: DateTime.utc(2026, 10, 12, 12),
      ),
      isNull,
    );

    final samples = await platform.readBodyMassSamples(
      fromUtc: DateTime.utc(2026, 10, 12),
      toUtc: DateTime.utc(2026, 10, 13),
    );
    expect(samples.first.isFromGainer, isTrue);
    expect(samples.first.syncIdentifier, startsWith('gainer-checkin-'));
    expect(samples.last.isFromGainer, isFalse);
    expect(samples.last.syncIdentifier, isNull);
  });

  test('Schreib-Port reicht Werte durch und bildet alle Status ab', () async {
    final api = _FakeMobilePlatformApi();
    final platform = PigeonNativeFeaturesPlatform(api: api);
    final status = {
      PlatformHealthWriteStatus.saved: HealthWriteStatus.saved,
      PlatformHealthWriteStatus.alreadyPresent:
          HealthWriteStatus.alreadyPresent,
      PlatformHealthWriteStatus.notAuthorized: HealthWriteStatus.notAuthorized,
    };
    for (final entry in status.entries) {
      api.writeStatus = entry.key;
      expect(
        await platform.writeBodyMass(
          kilograms: 80.9,
          measuredAtUtc: DateTime.utc(2026, 10, 12, 8),
          syncIdentifier: 'gainer-checkin-a-2026-10-12-weight',
        ),
        entry.value,
      );
      expect(
        await platform.writeSleep(
          bedtimeUtc: DateTime.utc(2026, 10, 11, 21, 30),
          wakeUtc: DateTime.utc(2026, 10, 12, 5),
          syncIdentifier: 'gainer-checkin-a-2026-10-12-sleep',
        ),
        entry.value,
      );
    }
    expect(api.bodyMassWrites.first, (
      80.9,
      DateTime.utc(2026, 10, 12, 8).millisecondsSinceEpoch,
      'gainer-checkin-a-2026-10-12-weight',
    ));
    expect(api.sleepWrites.first, (
      DateTime.utc(2026, 10, 11, 21, 30).millisecondsSinceEpoch,
      DateTime.utc(2026, 10, 12, 5).millisecondsSinceEpoch,
      'gainer-checkin-a-2026-10-12-sleep',
    ));
  });

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
        timerPhase: RestTimerPhase.running,
        startedAtUtc: updateAt,
        staleAtUtc: staleAt,
        timerTargetAtUtc: restEnd,
        detail: const LiveActivityDetail(
          title: 'Pull',
          exerciseName: 'Latzug',
          setIndex: 1,
          setCount: 3,
        ),
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
      final sent = api.liveActivityCalls.first.$2;
      expect(sent.timerPhase, 'running');
      expect(sent.expired, isFalse);
      expect(
        sent.timerTargetAtUtcEpochMilliseconds,
        restEnd.millisecondsSinceEpoch,
      );
      expect(sent.pausedRemainingSeconds, isNull);
      expect(sent.detail?.exerciseName, 'Latzug');
      expect(sent.detail?.setIndex, 1);
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
