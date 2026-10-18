import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';

/// Konfigurierbarer Health-Fake; Tests überschreiben nur, was sie brauchen.
class FakeHealthPlatform implements HealthPlatform {
  bool available = true;
  List<BodyMassSample> bodyMass = const [];
  int? steps;
  HealthSleepWindow? sleep;

  /// Wirft beim jeweiligen Aufruf, wenn gesetzt.
  Object? checkInAuthorizationError;
  Object? readError;
  Object? writeError;

  HealthWriteStatus writeResult = HealthWriteStatus.saved;
  int checkInAuthorizations = 0;
  final List<({DateTime from, DateTime to})> bodyMassReads = [];
  final List<({DateTime from, DateTime to})> stepReads = [];
  final List<({DateTime from, DateTime to})> sleepReads = [];
  final List<({double kg, DateTime at, String id})> bodyMassWrites = [];
  final List<({DateTime bed, DateTime wake, String id})> sleepWrites = [];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<PlatformAuthorizationRequestResult>
  requestBodyMassReadAuthorization() async =>
      PlatformAuthorizationRequestResult.requestCompleted;

  @override
  Future<List<BodyMassSample>> readBodyMassSamples({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    bodyMassReads.add((from: fromUtc, to: toUtc));
    if (readError != null) throw readError!;
    return bodyMass;
  }

  @override
  Future<PlatformAuthorizationRequestResult>
  requestCheckInAuthorization() async {
    checkInAuthorizations++;
    if (checkInAuthorizationError != null) throw checkInAuthorizationError!;
    return PlatformAuthorizationRequestResult.requestCompleted;
  }

  @override
  Future<int?> readStepCount({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    stepReads.add((from: fromUtc, to: toUtc));
    if (readError != null) throw readError!;
    return steps;
  }

  @override
  Future<HealthSleepWindow?> readSleep({
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    sleepReads.add((from: fromUtc, to: toUtc));
    if (readError != null) throw readError!;
    return sleep;
  }

  @override
  Future<HealthWriteStatus> writeBodyMass({
    required double kilograms,
    required DateTime measuredAtUtc,
    required String syncIdentifier,
  }) async {
    if (writeError != null) throw writeError!;
    bodyMassWrites.add((kg: kilograms, at: measuredAtUtc, id: syncIdentifier));
    return writeResult;
  }

  @override
  Future<HealthWriteStatus> writeSleep({
    required DateTime bedtimeUtc,
    required DateTime wakeUtc,
    required String syncIdentifier,
  }) async {
    if (writeError != null) throw writeError!;
    sleepWrites.add((bed: bedtimeUtc, wake: wakeUtc, id: syncIdentifier));
    return writeResult;
  }

  @override
  Future<PlatformAuthorizationRequestResult>
  requestWorkoutWriteAuthorization() async =>
      PlatformAuthorizationRequestResult.requestCompleted;

  @override
  Future<WorkoutExportReceipt> exportCompletedWorkout(
    CompletedWorkoutHealthExport workout,
  ) async => const WorkoutExportReceipt(
    status: HealthExportStatus.saved,
    syncIdentifier: 'health-workout-id',
    syncVersion: 1,
  );
}
