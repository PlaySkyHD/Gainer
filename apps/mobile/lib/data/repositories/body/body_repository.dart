import 'dart:math';

import '../../../domain/models/body/body_tracking.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../sync/local_sync_store.dart';

typedef BodyIdFactory = String Function();

const _bodyGoalType = 'body-goal';
const _dailyCheckInType = 'daily-check-in';

class BodyTrackingSnapshot {
  const BodyTrackingSnapshot({
    required this.activeGoal,
    required this.goalHistory,
    required this.checkIns,
    this.pendingResting = const [],
  });

  final ({String id, BodyGoal value})? activeGoal;
  final List<({String id, BodyGoal value})> goalHistory;
  final List<({String id, DailyCheckIn value})> checkIns;

  /// Gemessene Ruhewerte von Tagen ohne Check-in (warten auf den Check-in).
  final List<RestingEntry> pendingResting;

  /// Ruhewerte aus Check-ins und wartende Werte, ältester Tag zuerst.
  List<RestingEntry> get restingEntries {
    final entries = <RestingEntry>[
      for (final item in checkIns)
        if (item.value.restingHeartRateBpm != null ||
            item.value.restingHrvMs != null)
          RestingEntry(
            localDate: item.value.localDate,
            restingHeartRateBpm: item.value.restingHeartRateBpm,
            restingHrvMs: item.value.restingHrvMs,
          ),
      ...pendingResting,
    ]..sort((a, b) => a.localDate.compareTo(b.localDate));
    return List.unmodifiable(entries);
  }
}

/// Ergebnis von [BodyRepository.recordRestingMeasurement].
enum RestingMeasurementStatus {
  /// In den Check-in des Tages geschrieben.
  savedToCheckIn,

  /// Kein Check-in für den Tag: lokal gemerkt, bis er gespeichert wird.
  pending,
}

/// Sync-Metadatum mit den wartenden Ruhewerten je Tag.
const _pendingRestingKey = 'body-resting-pending';

enum HealthCheckInCommitStatus { imported, duplicate, dayConflict }

class HealthCheckInCommitResult {
  const HealthCheckInCommitResult(this.status, {this.checkInId});
  final HealthCheckInCommitStatus status;
  final String? checkInId;
}

/// Local-first body tracking backed by the account-bound SQLite outbox.
class BodyRepository {
  BodyRepository({
    required this.store,
    BodyIdFactory? ids,
    DateTime Function()? clock,
    this.transactionFaultForTesting,
  }) : ids = ids ?? _newUuidV4,
       clock = clock ?? DateTime.now;

  final LocalSyncStore store;
  final BodyIdFactory ids;
  final DateTime Function() clock;
  final void Function()? transactionFaultForTesting;

  Future<BodyTrackingSnapshot> read() async {
    final goals = await store.readAggregates(_bodyGoalType);
    final checkIns = await store.readAggregates(_dailyCheckInType);
    final parsedGoals = [
      for (final item in goals)
        (
          id: item.aggregateId,
          value: BodyGoal.fromJson(_map(item.workingCopy)),
        ),
    ];
    final active = parsedGoals.where((item) => item.value.isActive).toList();
    final history = parsedGoals.where((item) => !item.value.isActive).toList()
      ..sort(
        (left, right) => right.value.startDate.compareTo(left.value.startDate),
      );
    final parsedCheckIns =
        [
          for (final item in checkIns)
            (
              id: item.aggregateId,
              value: DailyCheckIn.fromJson(_map(item.workingCopy)),
            ),
        ]..sort(
          (left, right) =>
              right.value.localDate.compareTo(left.value.localDate),
        );
    if (active.length > 1) {
      throw StateError(
        'The local body-goal state contains multiple active goals.',
      );
    }
    return BodyTrackingSnapshot(
      activeGoal: active.isEmpty ? null : active.single,
      goalHistory: List.unmodifiable(history),
      checkIns: List.unmodifiable(parsedCheckIns),
      pendingResting: [
        for (final entry in (await _readPending()).entries)
          RestingEntry(
            localDate: entry.key,
            restingHeartRateBpm: entry.value.heartRate,
            restingHrvMs: entry.value.hrv,
            isPending: true,
          ),
      ],
    );
  }

  Future<Map<String, ({int? heartRate, int? hrv})>> _readPending() async {
    final raw = await store.readSyncMetadata(_pendingRestingKey);
    if (raw is! Map<String, dynamic>) return {};
    final result = <String, ({int? heartRate, int? hrv})>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      result[entry.key] = (
        heartRate: (value['restingHeartRateBpm'] as num?)?.toInt(),
        hrv: (value['restingHrvMs'] as num?)?.toInt(),
      );
    }
    return result;
  }

  Future<void> _writePending(
    Map<String, ({int? heartRate, int? hrv})> pending,
  ) async {
    if (pending.isEmpty) {
      await store.deleteSyncMetadata(_pendingRestingKey);
      return;
    }
    await store.writeSyncMetadata(_pendingRestingKey, {
      for (final entry in pending.entries)
        entry.key: {
          'restingHeartRateBpm': entry.value.heartRate,
          'restingHrvMs': entry.value.hrv,
        },
    });
  }

  /// Schreibt Ruhepuls und HRV (jeweils 25–150 bpm bzw. 1–300 ms) in den
  /// Check-in von [localDate]. Existiert der Check-in, wird er korrigiert
  /// (Operation `update`, übrige Werte bleiben). Fehlt er, verlangt der
  /// Check-in ein Gewicht: Die Werte werden lokal als „wartender Wert“
  /// gemerkt und beim nächsten Speichern des Check-ins dieses Tages
  /// mitgeschrieben ([saveCheckIn], [flushPendingResting]).
  Future<RestingMeasurementStatus> recordRestingMeasurement({
    required String localDate,
    required int restingHeartRateBpm,
    required int restingHrvMs,
  }) async {
    validateDailyCheckIn(
      DailyCheckInInput(
        localDate: localDate,
        weightKg: 1,
        caloriesKcal: null,
        proteinGrams: null,
        carbohydrateGrams: null,
        fatGrams: null,
        steps: null,
        sleepMinutes: null,
        restingHeartRateBpm: restingHeartRateBpm,
        restingHrvMs: restingHrvMs,
      ),
    );
    final existing = _findCheckInForDay(
      await store.readAggregates(_dailyCheckInType),
      localDate,
    );
    if (existing == null) {
      final pending = await _readPending();
      pending[localDate] = (heartRate: restingHeartRateBpm, hrv: restingHrvMs);
      await _writePending(pending);
      return RestingMeasurementStatus.pending;
    }
    final prior = DailyCheckIn.fromJson(_map(existing.workingCopy));
    await _writeCheckIn(
      existing: existing,
      checkIn: _copyCheckIn(
        prior,
        restingHeartRateBpm: restingHeartRateBpm,
        restingHrvMs: restingHrvMs,
        updatedAtUtc: clock().toUtc().toIso8601String(),
      ),
    );
    return RestingMeasurementStatus.savedToCheckIn;
  }

  /// Setzt nur die Schritte eines vorhandenen Check-ins, z. B. die fertige
  /// Tagessumme aus Apple Health. Liefert true, wenn sich etwas geändert hat;
  /// ohne Check-in für den Tag oder bei gleichem Wert bleibt alles unverändert.
  Future<bool> updateSteps({
    required String localDate,
    required int steps,
  }) async {
    validateDailyCheckIn(
      DailyCheckInInput(
        localDate: localDate,
        weightKg: 1,
        caloriesKcal: null,
        proteinGrams: null,
        carbohydrateGrams: null,
        fatGrams: null,
        steps: steps,
        sleepMinutes: null,
      ),
    );
    final existing = _findCheckInForDay(
      await store.readAggregates(_dailyCheckInType),
      localDate,
    );
    if (existing == null) return false;
    final prior = DailyCheckIn.fromJson(_map(existing.workingCopy));
    if (prior.steps == steps) return false;
    await _writeCheckIn(
      existing: existing,
      checkIn: DailyCheckIn(
        localDate: prior.localDate,
        weightKg: prior.weightKg,
        caloriesKcal: prior.caloriesKcal,
        proteinGrams: prior.proteinGrams,
        carbohydrateGrams: prior.carbohydrateGrams,
        fatGrams: prior.fatGrams,
        steps: steps,
        sleepMinutes: prior.sleepMinutes,
        restingHeartRateBpm: prior.restingHeartRateBpm,
        restingHrvMs: prior.restingHrvMs,
        createdAtUtc: prior.createdAtUtc,
        updatedAtUtc: clock().toUtc().toIso8601String(),
      ),
    );
    return true;
  }

  /// Überträgt wartende Ruhewerte in Check-ins, die es inzwischen gibt (z. B.
  /// aus dem Health-Import). Wartende Werte ohne Check-in bleiben liegen.
  Future<void> flushPendingResting() async {
    final pending = await _readPending();
    if (pending.isEmpty) return;
    final rows = await store.readAggregates(_dailyCheckInType);
    var changed = false;
    for (final date in [...pending.keys]) {
      final existing = _findCheckInForDay(rows, date);
      if (existing == null) continue;
      final value = pending[date]!;
      final prior = DailyCheckIn.fromJson(_map(existing.workingCopy));
      await _writeCheckIn(
        existing: existing,
        checkIn: _copyCheckIn(
          prior,
          restingHeartRateBpm: value.heartRate,
          restingHrvMs: value.hrv,
          updatedAtUtc: clock().toUtc().toIso8601String(),
        ),
      );
      pending.remove(date);
      changed = true;
    }
    if (changed) await _writePending(pending);
  }

  Future<void> _writeCheckIn({
    required LocalAggregateEnvelope<Object?> existing,
    required DailyCheckIn checkIn,
  }) => store.commitMutation(
    MutationDraft(
      mutationId: ids(),
      aggregateType: _dailyCheckInType,
      aggregateId: existing.aggregateId,
      operation: LocalMutationOperation.update,
      baseVersion: existing.serverVersion,
      body: checkIn.toJson(),
      envelope: _pendingEnvelope(existing, checkIn.toJson()),
      createdAtUtc: clock().toUtc(),
    ),
  );

  Future<String> activateGoal({
    required BodyGoalKind kind,
    required double startWeightKg,
    required double targetWeightKg,
    required String startDate,
    required String? targetDate,
  }) async {
    validateBodyGoal(
      kind: kind,
      startWeightKg: startWeightKg,
      targetWeightKg: targetWeightKg,
      startDate: startDate,
      targetDate: targetDate,
    );
    final current = await read();
    final active = current.activeGoal;
    final now = clock().toUtc();
    final createdAtUtc = now.toIso8601String();
    final goalId = ids();
    final newGoal = BodyGoal(
      kind: kind,
      startWeightKg: startWeightKg,
      targetWeightKg: targetWeightKg,
      startDate: startDate,
      targetDate: targetDate,
      createdAtUtc: createdAtUtc,
      endedAtUtc: null,
    );
    final related = <String, LocalAggregateEnvelope<Object?>>{};
    String? dependency;
    int? expectedActiveGoalVersion;
    if (active case final previous?) {
      final oldEnvelope = await store.readAggregate(_bodyGoalType, previous.id);
      if (oldEnvelope == null) {
        throw StateError('The active body goal disappeared.');
      }
      expectedActiveGoalVersion = oldEnvelope.serverVersion ?? 1;
      related[_bodyGoalType] = _pendingEnvelope(
        oldEnvelope,
        previous.value.toJson()..['endedAtUtc'] = createdAtUtc,
      );
      final writes =
          (await store.readOutbox(aggregateType: _bodyGoalType))
              .where(
                (item) =>
                    item.aggregateId == previous.id &&
                    item.status != LocalMutationStatus.clean &&
                    item.status != LocalMutationStatus.failed &&
                    item.status != LocalMutationStatus.conflict,
              )
              .toList()
            ..sort((left, right) => right.sequence.compareTo(left.sequence));
      dependency = writes.isEmpty ? null : writes.first.mutationId;
    }
    final payload = {
      ...newGoal.toJson(),
      'expectedActiveGoalId': active?.id,
      'expectedActiveGoalVersion': expectedActiveGoalVersion,
    };
    await store.commitMutation(
      MutationDraft(
        mutationId: ids(),
        aggregateType: _bodyGoalType,
        aggregateId: goalId,
        operation: LocalMutationOperation.create,
        baseVersion: null,
        body: payload,
        envelope: localEnvelope(
          aggregateId: goalId,
          workingCopy: newGoal.toJson(),
        ),
        relatedEnvelopes: [
          for (final entry in related.entries) (entry.key, entry.value),
        ],
        dependsOnMutationId: dependency,
        createdAtUtc: now,
        afterEnvelopeWriteForTesting: transactionFaultForTesting,
      ),
    );
    return goalId;
  }

  /// Speichert den Check-in des Tages. Für Kalorien, Makros, Schritte, Schlaf
  /// und Ruhewerte gilt: null = gespeicherten Wert behalten. Schritte sind
  /// Tagessummen und steigen nur, also gewinnt der größere Wert; so
  /// überschreibt ein älterer Health-Stand aus dem offenen Editor keinen
  /// neueren Wert von `HealthStepsSync`.
  Future<String> saveCheckIn(DailyCheckInInput input) async {
    validateDailyCheckIn(input);
    final localDate = input.localDate;
    final weightKg = input.weightKg;
    final caloriesKcal = input.caloriesKcal;
    final proteinGrams = input.proteinGrams;
    final carbohydrateGrams = input.carbohydrateGrams;
    final fatGrams = input.fatGrams;
    final steps = input.steps;
    final sleepMinutes = input.sleepMinutes;
    final restingHeartRateBpm = input.restingHeartRateBpm;
    final restingHrvMs = input.restingHrvMs;
    final now = clock().toUtc();
    final existing = _findCheckInForDay(
      await store.readAggregates(_dailyCheckInType),
      localDate,
    );
    final id = existing?.aggregateId ?? ids();
    final prior = existing == null
        ? null
        : DailyCheckIn.fromJson(_map(existing.workingCopy));
    final storedSteps = prior?.steps;
    final mergedSteps = steps == null || (storedSteps ?? 0) > steps
        ? storedSteps
        : steps;
    // Ruhewerte: ein wartender Wert des Tages (neuere Messung) gewinnt, sonst
    // der übergebene, sonst der bisherige Wert des Check-ins.
    final pending = await _readPending();
    final waiting = pending[localDate];
    final checkIn = DailyCheckIn(
      localDate: localDate,
      weightKg: weightKg,
      caloriesKcal: caloriesKcal ?? prior?.caloriesKcal,
      proteinGrams: proteinGrams ?? prior?.proteinGrams,
      carbohydrateGrams: carbohydrateGrams ?? prior?.carbohydrateGrams,
      fatGrams: fatGrams ?? prior?.fatGrams,
      steps: mergedSteps,
      sleepMinutes: sleepMinutes ?? prior?.sleepMinutes,
      restingHeartRateBpm:
          waiting?.heartRate ??
          restingHeartRateBpm ??
          prior?.restingHeartRateBpm,
      restingHrvMs: waiting?.hrv ?? restingHrvMs ?? prior?.restingHrvMs,
      createdAtUtc: prior?.createdAtUtc ?? now.toIso8601String(),
      updatedAtUtc: now.toIso8601String(),
    );
    await store.commitMutation(
      MutationDraft(
        mutationId: ids(),
        aggregateType: _dailyCheckInType,
        aggregateId: id,
        operation: existing == null
            ? LocalMutationOperation.create
            : LocalMutationOperation.update,
        baseVersion: existing?.serverVersion,
        body: checkIn.toJson(),
        envelope: existing == null
            ? localEnvelope(aggregateId: id, workingCopy: checkIn.toJson())
            : _pendingEnvelope(existing, checkIn.toJson()),
        createdAtUtc: now,
      ),
    );
    if (waiting != null) {
      pending.remove(localDate);
      await _writePending(pending);
    }
    return id;
  }

  /// Atomically records a reviewed Health weight sample, its ordinary Gainer
  /// check-in mutation, and its account-local idempotency mapping. The probe
  /// identifier is written only to the local Health ledger and never to the
  /// immutable HTTP payload.
  Future<HealthCheckInCommitResult> importHealthWeight({
    required String probeId,
    required String localDate,
    required double weightKg,
    required bool replaceExistingCheckIn,
    required bool Function() sessionGuard,
  }) => _importHealthWeight(
    probeId: probeId,
    localDate: localDate,
    weightKg: weightKg,
    replaceExistingCheckIn: replaceExistingCheckIn,
    sessionGuard: sessionGuard,
    attempt: 0,
  );

  Future<HealthCheckInCommitResult> _importHealthWeight({
    required String probeId,
    required String localDate,
    required double weightKg,
    required bool replaceExistingCheckIn,
    required bool Function() sessionGuard,
    required int attempt,
  }) async {
    if (probeId.isEmpty || probeId.length > 200) {
      throw ArgumentError.value(probeId, 'probeId');
    }
    validateDailyCheckIn(
      DailyCheckInInput(
        localDate: localDate,
        weightKg: weightKg,
        caloriesKcal: null,
        proteinGrams: null,
        carbohydrateGrams: null,
        fatGrams: null,
        steps: null,
        sleepMinutes: null,
      ),
    );
    const ledgerKey = 'health-ledger:body-mass';
    final rawLedger = await store.readSyncMetadata(ledgerKey);
    final probes = _healthProbes(rawLedger);
    if (probes.containsKey(probeId)) {
      final id =
          (probes[probeId] as Map<String, dynamic>?)?['checkInId'] as String?;
      return HealthCheckInCommitResult(
        HealthCheckInCommitStatus.duplicate,
        checkInId: id,
      );
    }
    final existing = _findCheckInForDay(
      await store.readAggregates(_dailyCheckInType),
      localDate,
    );
    if (existing != null && !replaceExistingCheckIn) {
      return HealthCheckInCommitResult(
        HealthCheckInCommitStatus.dayConflict,
        checkInId: existing.aggregateId,
      );
    }
    final now = clock().toUtc();
    final id = existing?.aggregateId ?? ids();
    final previous = existing == null ? null : _map(existing.workingCopy);
    final checkIn = DailyCheckIn(
      localDate: localDate,
      weightKg: weightKg,
      caloriesKcal: previous?['caloriesKcal'] as double?,
      proteinGrams: previous?['proteinGrams'] as double?,
      carbohydrateGrams: previous?['carbohydrateGrams'] as double?,
      fatGrams: previous?['fatGrams'] as double?,
      steps: previous?['steps'] as int?,
      sleepMinutes: previous?['sleepMinutes'] as int?,
      restingHeartRateBpm: (previous?['restingHeartRateBpm'] as num?)?.toInt(),
      restingHrvMs: (previous?['restingHrvMs'] as num?)?.toInt(),
      createdAtUtc:
          previous?['createdAtUtc'] as String? ?? now.toIso8601String(),
      updatedAtUtc: now.toIso8601String(),
    );
    probes[probeId] = {
      'localDate': localDate,
      'checkInId': id,
      'importedAtUtc': now.toIso8601String(),
    };
    try {
      await store.commitMutation(
        MutationDraft(
          mutationId: ids(),
          aggregateType: _dailyCheckInType,
          aggregateId: id,
          operation: existing == null
              ? LocalMutationOperation.create
              : LocalMutationOperation.update,
          baseVersion: existing?.serverVersion,
          body: checkIn.toJson(),
          envelope: existing == null
              ? localEnvelope(aggregateId: id, workingCopy: checkIn.toJson())
              : _pendingEnvelope(existing, checkIn.toJson()),
          localMetadataExpectations: {ledgerKey: rawLedger},
          localMetadataWrites: {
            ledgerKey: {'probes': probes},
          },
          resourceExpectations: [
            LocalResourceExpectation(
              aggregateType: _dailyCheckInType,
              aggregateId: id,
              optimisticVersion: existing?.optimisticVersion,
              serverVersion: existing?.serverVersion,
            ),
          ],
          mutationGuard: sessionGuard,
          createdAtUtc: now,
        ),
      );
    } on StateError catch (error) {
      if (attempt < 2 && _isRetryableHealthImportError(error)) {
        return _importHealthWeight(
          probeId: probeId,
          localDate: localDate,
          weightKg: weightKg,
          replaceExistingCheckIn: replaceExistingCheckIn,
          sessionGuard: sessionGuard,
          attempt: attempt + 1,
        );
      }
      rethrow;
    }
    return HealthCheckInCommitResult(
      HealthCheckInCommitStatus.imported,
      checkInId: id,
    );
  }
}

DailyCheckIn _copyCheckIn(
  DailyCheckIn prior, {
  required int? restingHeartRateBpm,
  required int? restingHrvMs,
  required String updatedAtUtc,
}) => DailyCheckIn(
  localDate: prior.localDate,
  weightKg: prior.weightKg,
  caloriesKcal: prior.caloriesKcal,
  proteinGrams: prior.proteinGrams,
  carbohydrateGrams: prior.carbohydrateGrams,
  fatGrams: prior.fatGrams,
  steps: prior.steps,
  sleepMinutes: prior.sleepMinutes,
  restingHeartRateBpm: restingHeartRateBpm ?? prior.restingHeartRateBpm,
  restingHrvMs: restingHrvMs ?? prior.restingHrvMs,
  createdAtUtc: prior.createdAtUtc,
  updatedAtUtc: updatedAtUtc,
);

LocalAggregateEnvelope<Object?> _pendingEnvelope(
  LocalAggregateEnvelope<Object?> old,
  Object? workingCopy,
) => LocalAggregateEnvelope(
  aggregateId: old.aggregateId,
  serverSnapshot: old.serverSnapshot,
  workingCopy: workingCopy,
  serverVersion: old.serverVersion,
  optimisticVersion: old.optimisticVersion + 1,
  syncState: LocalSyncState.pending,
);

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a local body resource object.');
  }
  return value;
}

LocalAggregateEnvelope<Object?>? _findCheckInForDay(
  List<LocalAggregateEnvelope<Object?>> rows,
  String localDate,
) {
  for (final row in rows) {
    if (_map(row.workingCopy)['localDate'] == localDate) {
      return row;
    }
  }
  return null;
}

Map<String, dynamic> _healthProbes(Object? rawLedger) {
  final ledger = rawLedger is Map<String, dynamic>
      ? Map<String, dynamic>.from(rawLedger)
      : <String, dynamic>{'probes': <String, Object?>{}};
  return ledger['probes'] is Map<String, dynamic>
      ? Map<String, dynamic>.from(ledger['probes'] as Map<String, dynamic>)
      : <String, dynamic>{};
}

bool _isRetryableHealthImportError(StateError error) =>
    error.message.contains('Health import state changed') ||
    error.message.contains('local resource changed');

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((item) => item.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
