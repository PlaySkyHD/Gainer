import 'generated/mobile_platform_api.dart';
import 'platform_ports.dart';

/// Routes user-initiated Apple system features through the typed Pigeon API.
class PigeonNativeFeaturesPlatform
    implements
        CapturePlatform,
        TimerNotificationPlatform,
        HapticsPlatform,
        HealthPlatform,
        ExtensionSnapshotPlatform,
        LiveActivityPlatform {
  PigeonNativeFeaturesPlatform({MobilePlatformApi? api})
    : _api = api ?? MobilePlatformApi();

  final MobilePlatformApi _api;

  Future<PlatformRoute?> readPendingRoute() => _api.readPendingRoute();

  Future<void> clearPendingRoute() => _api.clearPendingRoute();

  Future<void> retryPendingRoute() => _api.retryPendingRoute();

  @override
  Future<String?> scanBarcode() => _api.scanBarcode();

  @override
  Future<CapturedImage?> capturePhoto() async {
    final image = await _api.capturePhoto();
    if (image == null) return null;
    return CapturedImage(bytes: image.bytes, mimeType: image.mimeType);
  }

  @override
  Future<CapturedImage?> chooseImage() async {
    final image = await _api.chooseImage();
    if (image == null) return null;
    return CapturedImage(bytes: image.bytes, mimeType: image.mimeType);
  }

  @override
  Future<void> perform(HapticIntent intent) =>
      _api.performHaptic(switch (intent) {
        HapticIntent.commit => 'commit',
        HapticIntent.timerComplete => 'timerComplete',
        HapticIntent.success => 'success',
      });

  @override
  Future<bool> requestPermission() => _api.requestNotificationPermission();

  @override
  Future<void> schedule({
    required String workoutId,
    required int generation,
    required DateTime targetAtUtc,
  }) {
    return _api.schedulePauseNotification(
      workoutId,
      generation,
      targetAtUtc.toUtc().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> cancel(String workoutId) =>
      _api.cancelPauseNotifications(workoutId);

  @override
  Future<bool> isAvailable() => _api.isHealthDataAvailable();

  @override
  Future<PlatformAuthorizationRequestResult>
  requestBodyMassReadAuthorization() => _api.requestBodyMassReadAuthorization();

  @override
  Future<List<BodyMassSample>> readBodyMassSamples({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final samples = await _api.readBodyMassSamples(
      fromUtc.toUtc().millisecondsSinceEpoch,
      toUtc.toUtc().millisecondsSinceEpoch,
    );
    return samples
        .map(
          (sample) => BodyMassSample(
            uuid: sample.uuid,
            measuredAtUtc: DateTime.fromMillisecondsSinceEpoch(
              sample.measuredAtUtcEpochMilliseconds,
              isUtc: true,
            ),
            weightKilograms: sample.weightKilograms,
            sourceName: sample.sourceName,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<PlatformAuthorizationRequestResult>
  requestWorkoutWriteAuthorization() => _api.requestWorkoutWriteAuthorization();

  @override
  Future<WorkoutExportReceipt> exportCompletedWorkout(
    CompletedWorkoutHealthExport workout,
  ) async {
    final receipt = await _api.exportCompletedWorkout(
      workout.accountId,
      workout.workoutId,
      workout.serverVersion,
      workout.startedAtUtc.millisecondsSinceEpoch,
      workout.completedAtUtc.millisecondsSinceEpoch,
    );
    final status = switch (receipt.status) {
      'saved' => HealthExportStatus.saved,
      'alreadyPresent' => HealthExportStatus.alreadyPresent,
      _ => throw StateError('Unknown HealthKit export result.'),
    };
    return WorkoutExportReceipt(
      status: status,
      syncIdentifier: receipt.syncIdentifier,
      syncVersion: receipt.syncVersion,
    );
  }

  @override
  Future<void> publish(NeutralExtensionSnapshot snapshot) {
    return _api.publishNeutralExtensionSnapshot(
      snapshot.schemaVersion,
      snapshot.generation,
      snapshot.updatedAtUtc.toUtc().millisecondsSinceEpoch,
      snapshot.availableRoutes.toList(growable: false)..sort(),
    );
  }

  @override
  Future<void> clear({required int minimumGeneration}) =>
      _api.clearExtensionSnapshot(minimumGeneration);

  @override
  Future<bool> start({required LiveActivityState state}) =>
      _api.startLiveActivity(_liveActivityPlatformState(state));

  @override
  Future<bool> update({required LiveActivityState state}) =>
      _api.updateLiveActivity(_liveActivityPlatformState(state));

  @override
  Future<void> end(String sessionId) => _api.endLiveActivity(sessionId);

  @override
  Future<void> endAll() => _api.endAllLiveActivities();

  PlatformLiveActivityState _liveActivityPlatformState(
    LiveActivityState state,
  ) {
    final detail = state.detail;
    return PlatformLiveActivityState(
      sessionId: state.sessionId,
      timerPhase: state.timerPhase.name,
      startedAtUtcEpochMilliseconds: state.startedAtUtc
          .toUtc()
          .millisecondsSinceEpoch,
      expired: state.expired,
      staleAtUtcEpochMilliseconds: state.staleAtUtc
          .toUtc()
          .millisecondsSinceEpoch,
      timerTargetAtUtcEpochMilliseconds: state.timerTargetAtUtc
          ?.toUtc()
          .millisecondsSinceEpoch,
      pausedRemainingSeconds: state.pausedRemainingSeconds,
      detail: detail == null
          ? null
          : PlatformLiveActivityDetail(
              title: detail.title,
              exerciseName: detail.exerciseName,
              setIndex: detail.setIndex,
              setCount: detail.setCount,
            ),
    );
  }
}
