import 'dart:typed_data';

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

abstract interface class TimerNotificationPlatform {
  Future<bool> requestPermission();
  Future<void> schedule({
    required String workoutId,
    required int generation,
    required DateTime targetAtUtc,
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
}

enum HealthExportStatus { saved, alreadyPresent }

class BodyMassSample {
  const BodyMassSample({
    required this.uuid,
    required this.measuredAtUtc,
    required this.weightKilograms,
    required this.sourceName,
  });

  final String uuid;
  final DateTime measuredAtUtc;
  final double weightKilograms;
  final String sourceName;
}

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

/// Detailangaben der Live Activity. Nur bei ausdrücklicher Freigabe gesetzt;
/// Gewichte und Wiederholungen gehören nie hierher.
class LiveActivityDetail {
  const LiveActivityDetail({
    required this.title,
    required this.exerciseName,
    required this.setIndex,
    required this.setCount,
  });

  final String title;
  final String exerciseName;
  final int setIndex;
  final int setCount;

  @override
  bool operator ==(Object other) =>
      other is LiveActivityDetail &&
      other.title == title &&
      other.exerciseName == exerciseName &&
      other.setIndex == setIndex &&
      other.setCount == setCount;

  @override
  int get hashCode => Object.hash(title, exerciseName, setIndex, setCount);
}

/// Neutraler Zustand einer Trainings-Live-Activity. Er enthält keine Gewichte,
/// Wiederholungen oder Kontodaten; die Restzeit leitet die Oberfläche aus dem
/// Zielzeitpunkt ab.
class LiveActivityState {
  const LiveActivityState({
    required this.sessionId,
    required this.timerPhase,
    required this.startedAtUtc,
    required this.staleAtUtc,
    this.timerTargetAtUtc,
    this.pausedRemainingSeconds,
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
      other.detail == detail;

  @override
  int get hashCode => Object.hash(
    sessionId,
    timerPhase,
    startedAtUtc,
    staleAtUtc,
    timerTargetAtUtc,
    pausedRemainingSeconds,
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
