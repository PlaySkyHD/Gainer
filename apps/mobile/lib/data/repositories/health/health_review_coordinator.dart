import '../../../domain/models/training/training.dart';
import '../../services/platform/platform_ports.dart';
import '../body/body_repository.dart';
import '../sync/local_sync_store.dart';

enum HealthImportReviewStatus { imported, duplicate, dayConflict, skipped }

class HealthSessionIdentity {
  const HealthSessionIdentity({
    required this.accountId,
    required this.generation,
  });
  final String accountId;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is HealthSessionIdentity &&
      other.accountId == accountId &&
      other.generation == generation;
  @override
  int get hashCode => Object.hash(accountId, generation);
}

class HealthImportReviewResult {
  const HealthImportReviewResult({required this.sample, required this.status});
  final BodyMassSample sample;
  final HealthImportReviewStatus status;
}

class HealthWeightReview {
  HealthWeightReview({
    required this.fromLocalDate,
    required this.toLocalDate,
    required List<BodyMassSample> samples,
    required this.sessionGeneration,
  }) : samples = List.unmodifiable(samples);
  final String fromLocalDate;
  final String toLocalDate;
  final List<BodyMassSample> samples;
  final int sessionGeneration;
}

class CompletedWorkoutCandidate {
  const CompletedWorkoutCandidate({
    required this.id,
    required this.value,
    required this.serverVersion,
  });
  final String id;
  final WorkoutRecord value;
  final int serverVersion;
}

class HealthReviewCoordinator {
  HealthReviewCoordinator({
    required this.store,
    required this.bodyRepository,
    required this.platform,
    required this.accountId,
    required this.currentSessionIdentity,
  });

  final LocalSyncStore store;
  final BodyRepository bodyRepository;
  final HealthPlatform platform;
  final String accountId;

  /// Returns the live account and generation, or null after logout.
  final HealthSessionIdentity? Function() currentSessionIdentity;

  Future<bool> isAvailable() async {
    final session = _requireActiveSession();
    final result = await platform.isAvailable();
    _requireActiveSession(session);
    return result;
  }

  /// Requests permission only as a result of the caller's explicit import action.
  /// The result means that the system request sheet finished, not that access was granted.
  Future<HealthWeightReview?> prepareWeightReview({
    required String fromLocalDate,
    required String toLocalDate,
  }) async {
    _validateRange(fromLocalDate, toLocalDate);
    final session = _requireActiveSession();
    final available = await platform.isAvailable();
    _requireActiveSession(session);
    if (!available) {
      throw StateError('Apple Health ist auf diesem Gerät nicht verfügbar.');
    }
    await platform.requestBodyMassReadAuthorization();
    _requireActiveSession(session);
    final from = _localMidnight(fromLocalDate).toUtc();
    final throughExclusive = _localMidnight(_addDays(toLocalDate, 1)).toUtc();
    final samples = await platform.readBodyMassSamples(
      fromUtc: from,
      toUtc: throughExclusive,
    );
    _requireActiveSession(session);
    final filtered = samples.where((sample) {
      final instant = sample.measuredAtUtc.toUtc();
      return !instant.isBefore(from) &&
          instant.isBefore(throughExclusive) &&
          sample.weightKilograms.isFinite &&
          sample.weightKilograms > 0;
    }).toList()..sort((a, b) => a.measuredAtUtc.compareTo(b.measuredAtUtc));
    return HealthWeightReview(
      fromLocalDate: fromLocalDate,
      toLocalDate: toLocalDate,
      samples: filtered,
      sessionGeneration: session.generation,
    );
  }

  Future<List<HealthImportReviewResult>> confirmWeightReview({
    required HealthWeightReview review,
    required Set<String> selectedProbeIds,
    required bool acceptedServerSyncNotice,
    Set<String> replaceCheckInProbeIds = const {},
    Set<String> skipCheckInProbeIds = const {},
  }) async {
    if (!acceptedServerSyncNotice) {
      throw StateError(
        'Der Hinweis zum Gainer-Server-Sync muss bestätigt werden.',
      );
    }
    if (selectedProbeIds.isEmpty) return const [];
    final session = _requireActiveSession(
      HealthSessionIdentity(
        accountId: accountId,
        generation: review.sessionGeneration,
      ),
    );
    final byId = {for (final sample in review.samples) sample.uuid: sample};
    if (selectedProbeIds.any((id) => !byId.containsKey(id))) {
      throw ArgumentError('Eine ausgewählte Health-Probe fehlt im Review.');
    }
    if (replaceCheckInProbeIds.intersection(skipCheckInProbeIds).isNotEmpty) {
      throw ArgumentError(
        'Ein Tageskonflikt kann nicht gleichzeitig ersetzt und übersprungen werden.',
      );
    }
    final outcomes = <HealthImportReviewResult>[];
    for (final id in selectedProbeIds) {
      final sample = byId[id]!;
      if (skipCheckInProbeIds.contains(id)) {
        outcomes.add(
          HealthImportReviewResult(
            sample: sample,
            status: HealthImportReviewStatus.skipped,
          ),
        );
        continue;
      }
      final localDate = _date(sample.measuredAtUtc.toLocal());
      _requireActiveSession(session);
      final result = await bodyRepository.importHealthWeight(
        probeId: sample.uuid,
        localDate: localDate,
        weightKg: sample.weightKilograms,
        replaceExistingCheckIn: replaceCheckInProbeIds.contains(id),
        sessionGuard: () => _isActiveSession(session),
      );
      _requireActiveSession(session);
      outcomes.add(
        HealthImportReviewResult(
          sample: sample,
          status: switch (result.status) {
            HealthCheckInCommitStatus.imported =>
              HealthImportReviewStatus.imported,
            HealthCheckInCommitStatus.duplicate =>
              HealthImportReviewStatus.duplicate,
            HealthCheckInCommitStatus.dayConflict =>
              HealthImportReviewStatus.dayConflict,
          },
        ),
      );
    }
    return List.unmodifiable(outcomes);
  }

  Future<List<CompletedWorkoutCandidate>> completedWorkoutsForExport() async {
    final session = _requireActiveSession();
    await store.ensureAccountBound();
    _requireActiveSession(session);
    if (store.accountId != accountId) {
      throw StateError(
        'Health-Exportkonto stimmt nicht mit dem lokalen Konto überein.',
      );
    }
    final rows = await store.readAggregates('workout');
    _requireActiveSession(session);
    final values = <CompletedWorkoutCandidate>[];
    for (final row in rows) {
      final version = row.serverVersion;
      if (version == null || version <= 0) continue;
      final serverSnapshot = row.serverSnapshot;
      if (serverSnapshot is! Map<String, dynamic>) continue;
      final workout = WorkoutRecord.fromJson(serverSnapshot);
      if (workout.isCompleted && workout.completedAtUtc != null) {
        values.add(
          CompletedWorkoutCandidate(
            id: row.aggregateId,
            value: workout,
            serverVersion: version,
          ),
        );
      }
    }
    values.sort(
      (a, b) => (b.value.completedAtUtc ?? '').compareTo(
        a.value.completedAtUtc ?? '',
      ),
    );
    return List.unmodifiable(values);
  }

  /// Exports only a server-confirmed completed workout after an explicit user confirmation.
  /// HealthKit handles the stable identifier/version mapping; this local ledger records its receipt.
  Future<WorkoutExportReceipt> exportWorkout({
    required String workoutId,
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      throw StateError(
        'Der Health-Export erfordert eine ausdrückliche Bestätigung.',
      );
    }
    final session = _requireActiveSession();
    await store.ensureAccountBound();
    _requireActiveSession(session);
    if (store.accountId != accountId) {
      throw StateError(
        'Health-Exportkonto stimmt nicht mit dem lokalen Konto überein.',
      );
    }
    final row = await store.readAggregate('workout', workoutId);
    _requireActiveSession(session);
    if (row == null || row.serverVersion == null || row.serverVersion! <= 0) {
      throw StateError(
        'Nur serverbestätigte abgeschlossene Workouts dürfen exportiert werden.',
      );
    }
    final rawServerSnapshot = row.serverSnapshot;
    if (rawServerSnapshot is! Map<String, dynamic>) {
      throw StateError('Das Workout wurde noch nicht vom Server bestätigt.');
    }
    final data = WorkoutRecord.fromJson(rawServerSnapshot);
    if (!data.isCompleted || data.completedAtUtc == null) {
      throw StateError('Nur abgeschlossene Workouts dürfen exportiert werden.');
    }
    final start = DateTime.tryParse(data.startedAtUtc)?.toUtc();
    final end = DateTime.tryParse(data.completedAtUtc!)?.toUtc();
    if (start == null || end == null || !start.isBefore(end)) {
      throw StateError('Workout-Zeiten sind ungültig.');
    }
    final available = await platform.isAvailable();
    _requireActiveSession(session);
    if (!available) {
      throw StateError('Apple Health ist auf diesem Gerät nicht verfügbar.');
    }
    await platform.requestWorkoutWriteAuthorization();
    _requireActiveSession(session);
    final request = CompletedWorkoutHealthExport(
      accountId: accountId,
      workoutId: workoutId,
      status: data.status.toLowerCase(),
      serverVersion: row.serverVersion!,
      startedAtUtc: start,
      completedAtUtc: end,
    );
    try {
      final receipt = await platform.exportCompletedWorkout(request);
      _requireActiveSession(session);
      await store.writeSyncMetadata('health-ledger:workout-export:$workoutId', {
        'accountId': accountId,
        'workoutId': workoutId,
        'serverVersion': row.serverVersion,
        'syncIdentifier': receipt.syncIdentifier,
        'syncVersion': receipt.syncVersion,
        'status': receipt.status.name,
        'recordedAtUtc': DateTime.now().toUtc().toIso8601String(),
      });
      _requireActiveSession(session);
      return receipt;
    } catch (error) {
      if (_isActiveSession(session)) {
        await store.writeSyncMetadata(
          'health-ledger:workout-export:$workoutId',
          {
            'accountId': accountId,
            'workoutId': workoutId,
            'serverVersion': row.serverVersion,
            'status': 'failed',
            'retryable': true,
            'recordedAtUtc': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
      rethrow;
    }
  }

  static String localDateForSample(BodyMassSample sample) =>
      _date(sample.measuredAtUtc.toLocal());

  static void _validateRange(String from, String to) {
    if (!_validLocalDate(from) ||
        !_validLocalDate(to) ||
        from.compareTo(to) > 0) {
      throw ArgumentError('Der Health-Zeitraum ist ungültig.');
    }
    final start = DateTime.parse(from), end = DateTime.parse(to);
    if (end.difference(start).inDays > 90) {
      throw ArgumentError(
        'Der Health-Importzeitraum darf höchstens 90 Tage umfassen.',
      );
    }
  }

  static DateTime _localMidnight(String date) {
    final parsed = DateTime.parse(date);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _addDays(String date, int amount) {
    final day = DateTime.parse(date).add(Duration(days: amount));
    return _date(day);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  HealthSessionIdentity _requireActiveSession([
    HealthSessionIdentity? expected,
  ]) {
    final current = currentSessionIdentity();
    if (store.accountId != accountId ||
        current == null ||
        current.accountId != accountId ||
        (expected != null && current != expected)) {
      throw StateError(
        'Das aktive Health-Konto hat sich geändert. Bitte den Vorgang neu starten.',
      );
    }
    return current;
  }

  bool _isActiveSession(HealthSessionIdentity expected) =>
      currentSessionIdentity() == expected && store.accountId == accountId;

  static bool _validLocalDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null && _date(parsed) == value;
  }
}
