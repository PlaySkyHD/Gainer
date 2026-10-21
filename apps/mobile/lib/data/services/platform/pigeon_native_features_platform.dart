import 'package:flutter/services.dart';

import '../../../domain/models/cardio/cardio_draft.dart';
import '../native/rest_timer_alert_port.dart';
import 'generated/mobile_platform_api.dart';
import 'platform_ports.dart';

/// Routes user-initiated Apple system features through the typed Pigeon API.
class PigeonNativeFeaturesPlatform
    implements
        CapturePlatform,
        TimerNotificationPlatform,
        RestTimerAlertPort,
        HapticsPlatform,
        HealthPlatform,
        ExtensionSnapshotPlatform,
        LiveActivityPlatform,
        HeartRatePlatform,
        CardioHealthPlatform,
        DictationPlatform {
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
  Future<DictationState> startDictation({required String localeId}) async =>
      _dictation(await _api.startDictation(localeId));

  @override
  Future<DictationState> readDictation() async =>
      _dictation(await _api.readDictation());

  @override
  Future<void> stopDictation() => _api.stopDictation();

  @override
  Future<void> cancelDictation() => _api.cancelDictation();

  static DictationState _dictation(PlatformDictationState state) =>
      DictationState(
        status: DictationStatus.values.firstWhere(
          (value) => value.name == state.status,
          orElse: () => DictationStatus.failed,
        ),
        transcript: state.transcript,
      );

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
    required String soundId,
  }) {
    return _api.schedulePauseNotification(
      workoutId,
      generation,
      targetAtUtc.toUtc().millisecondsSinceEpoch,
      soundId,
    );
  }

  @override
  Future<void> playSound(String soundId) => _api.playTimerSound(soundId);

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
            syncIdentifier: sample.syncIdentifier,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<PlatformAuthorizationRequestResult> requestCheckInAuthorization() =>
      _api.requestCheckInAuthorization();

  @override
  Future<int?> readStepCount({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) => _api.readStepCount(
    fromUtc.toUtc().millisecondsSinceEpoch,
    toUtc.toUtc().millisecondsSinceEpoch,
  );

  @override
  Future<HealthSleepWindow?> readSleep({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final window = await _api.readSleep(
      fromUtc.toUtc().millisecondsSinceEpoch,
      toUtc.toUtc().millisecondsSinceEpoch,
    );
    if (window == null) return null;
    return HealthSleepWindow(
      bedtimeUtc: DateTime.fromMillisecondsSinceEpoch(
        window.bedtimeUtcEpochMilliseconds,
        isUtc: true,
      ),
      wakeUtc: DateTime.fromMillisecondsSinceEpoch(
        window.wakeUtcEpochMilliseconds,
        isUtc: true,
      ),
      asleepMinutes: window.asleepMinutes,
      sourceName: window.sourceName,
      fromGainer: window.fromGainer,
    );
  }

  @override
  Future<HealthWriteStatus> writeBodyMass({
    required double kilograms,
    required DateTime measuredAtUtc,
    required String syncIdentifier,
  }) async => _writeStatus(
    await _api.writeBodyMass(
      kilograms,
      measuredAtUtc.toUtc().millisecondsSinceEpoch,
      syncIdentifier,
    ),
  );

  @override
  Future<HealthWriteStatus> writeSleep({
    required DateTime bedtimeUtc,
    required DateTime wakeUtc,
    required String syncIdentifier,
  }) async => _writeStatus(
    await _api.writeSleep(
      bedtimeUtc.toUtc().millisecondsSinceEpoch,
      wakeUtc.toUtc().millisecondsSinceEpoch,
      syncIdentifier,
    ),
  );

  HealthWriteStatus _writeStatus(PlatformHealthWriteStatus status) =>
      switch (status) {
        PlatformHealthWriteStatus.saved => HealthWriteStatus.saved,
        PlatformHealthWriteStatus.alreadyPresent =>
          HealthWriteStatus.alreadyPresent,
        PlatformHealthWriteStatus.notAuthorized =>
          HealthWriteStatus.notAuthorized,
      };

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

  @override
  Future<bool> isEnabled() => _api.areLiveActivitiesEnabled();

  @override
  Future<void> openSettings() => _api.openAppSettings();

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
      restDurationSeconds: state.restDurationSeconds,
      detail: detail == null
          ? null
          : PlatformLiveActivityDetail(
              title: detail.title,
              exerciseName: detail.exerciseName,
              setIndex: detail.setIndex,
              setCount: detail.setCount,
              exerciseIndex: detail.exerciseIndex,
              exerciseCount: detail.exerciseCount,
              targetText: detail.targetText,
            ),
    );
  }

  @override
  Future<HeartRateStatus> readStatus(int afterSequence) => _ble(() async {
    final status = await _api.readHeartRateStatus(afterSequence);
    return HeartRateStatus(
      bluetoothState:
          HeartRateBluetoothState.values
              .where((v) => v.name == status.bluetoothState)
              .firstOrNull ??
          HeartRateBluetoothState.unknown,
      connectionState:
          HeartRateConnectionState.values
              .where((v) => v.name == status.connectionState)
              .firstOrNull ??
          HeartRateConnectionState.idle,
      lastSequence: status.lastSequence,
      samples: [
        for (final sample in status.samples)
          CardioSample(
            sequence: sample.sequence,
            atUtc: DateTime.fromMillisecondsSinceEpoch(
              sample.atUtcEpochMilliseconds,
              isUtc: true,
            ),
            bpm: sample.bpm,
            rrIntervalsMs: sample.rrIntervalsMs,
          ),
      ],
      sensorId: status.sensorId,
      sensorName: status.sensorName,
      batteryPercent: status.batteryPercent,
      latestBpm: status.latestBpm,
      latestAtUtc: status.latestAtUtcEpochMilliseconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              status.latestAtUtcEpochMilliseconds!,
              isUtc: true,
            ),
      monitoringSessionId: status.monitoringSessionId,
      zoneState: HeartRateZoneState.values
          .where((v) => v.name == status.zoneState)
          .firstOrNull,
    );
  });

  @override
  Future<List<HeartRateSensor>> scan(Duration duration) => _ble(() async {
    final sensors = await _api.scanHeartRateSensors(duration.inMilliseconds);
    return [
      for (final sensor in sensors)
        HeartRateSensor(
          id: sensor.id,
          name: sensor.name,
          isConnected: sensor.isConnected,
          signalStrength: sensor.signalStrength,
        ),
    ];
  });

  @override
  Future<bool> connect(String sensorId) =>
      _ble(() => _api.connectHeartRateSensor(sensorId));

  @override
  Future<void> disconnect() => _ble(_api.disconnectHeartRateSensor);

  @override
  Future<void> startMonitoring(HeartRateMonitoringConfig config) =>
      _ble(() => _api.startCardioMonitoring(_monitoringConfig(config)));

  @override
  Future<void> updateMonitoring(HeartRateMonitoringConfig config) =>
      _ble(() => _api.updateCardioMonitoring(_monitoringConfig(config)));

  @override
  Future<void> stopMonitoring(String sessionId) =>
      _ble(() => _api.stopCardioMonitoring(sessionId));

  PlatformCardioMonitoringConfig _monitoringConfig(
    HeartRateMonitoringConfig config,
  ) => PlatformCardioMonitoringConfig(
    sessionId: config.sessionId,
    title: config.title,
    startedAtUtcEpochMilliseconds: config.startedAtUtc
        .toUtc()
        .millisecondsSinceEpoch,
    graceSeconds: config.graceSeconds,
    repeatSeconds: config.repeatSeconds,
    warmupSeconds: config.warmupSeconds,
    soundId: config.soundId,
    alertsEnabled: config.alertsEnabled,
    liveActivityEnabled: config.liveActivityEnabled,
    zoneLowBpm: config.zoneLowBpm,
    zoneHighBpm: config.zoneHighBpm,
    phases: config.phases.isEmpty
        ? null
        : [
            for (final phase in config.phases)
              PlatformCardioPhase(
                startOffsetSeconds: phase.startOffsetSeconds,
                durationSeconds: phase.durationSeconds,
                name: phase.name,
                zoneLowBpm: phase.lowBpm,
                zoneHighBpm: phase.highBpm,
              ),
          ],
    voiceEnabled: config.voiceEnabled,
    voiceIntervalMinutes: config.voiceIntervalMinutes,
  );

  /// Übersetzt die Bluetooth-Fehlercodes der Plattform.
  Future<T> _ble<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      final problem = switch (error.code) {
        'bluetooth_powered_off' => BluetoothProblem.poweredOff,
        'bluetooth_unauthorized' => BluetoothProblem.unauthorized,
        'bluetooth_unsupported' => BluetoothProblem.unsupported,
        _ => null,
      };
      if (problem == null) rethrow;
      throw BluetoothUnavailableException(problem);
    }
  }

  @override
  Future<void> requestWriteAuthorization() =>
      _api.requestCardioWriteAuthorization();

  @override
  Future<WorkoutExportReceipt> exportCardioSession(
    CardioHealthExport export,
  ) async {
    final receipt = await _api.exportCardioSession(
      PlatformCardioExport(
        accountId: export.accountId,
        sessionId: export.sessionId,
        syncVersion: export.syncVersion,
        activityType: export.activityType,
        startedAtUtcEpochMilliseconds: export.startedAtUtc
            .toUtc()
            .millisecondsSinceEpoch,
        endedAtUtcEpochMilliseconds: export.endedAtUtc
            .toUtc()
            .millisecondsSinceEpoch,
        sampleIntervalSeconds: export.sampleIntervalSeconds,
        heartRateBpm: export.heartRateBpm,
        distanceKm: export.distanceKm,
        energyKcal: export.energyKcal,
      ),
    );
    return WorkoutExportReceipt(
      status: switch (receipt.status) {
        'saved' => HealthExportStatus.saved,
        'alreadyPresent' => HealthExportStatus.alreadyPresent,
        _ => throw StateError('Unknown HealthKit export result.'),
      },
      syncIdentifier: receipt.syncIdentifier,
      syncVersion: receipt.syncVersion,
    );
  }
}
