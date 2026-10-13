import 'dart:math';

import '../../../domain/models/body/body_tracking.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../sync/local_sync_store.dart';

typedef BodyIdFactory = String Function();

class BodyTrackingSnapshot {
  const BodyTrackingSnapshot({
    required this.activeGoal,
    required this.goalHistory,
    required this.checkIns,
  });

  final ({String id, BodyGoal value})? activeGoal;
  final List<({String id, BodyGoal value})> goalHistory;
  final List<({String id, DailyCheckIn value})> checkIns;
}

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
    final goals = await store.readAggregates('body-goal');
    final checkIns = await store.readAggregates('daily-check-in');
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
    );
  }

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
      final oldEnvelope = await store.readAggregate('body-goal', previous.id);
      if (oldEnvelope == null) {
        throw StateError('The active body goal disappeared.');
      }
      expectedActiveGoalVersion = oldEnvelope.serverVersion ?? 1;
      related['body-goal'] = _pendingEnvelope(
        oldEnvelope,
        previous.value.toJson()..['endedAtUtc'] = createdAtUtc,
      );
      final writes =
          (await store.readOutbox(aggregateType: 'body-goal'))
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
      mutationId: ids(),
      aggregateType: 'body-goal',
      aggregateId: goalId,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: payload,
      envelope: localEnvelope(
        aggregateId: goalId,
        workingCopy: newGoal.toJson(),
      ),
      relatedEnvelopes: related,
      dependsOnMutationId: dependency,
      createdAtUtc: now,
      afterEnvelopeWriteForTesting: transactionFaultForTesting,
    );
    return goalId;
  }

  Future<String> saveCheckIn({
    required String localDate,
    required double weightKg,
    required double? caloriesKcal,
    required double? proteinGrams,
    required double? carbohydrateGrams,
    required double? fatGrams,
    required int? steps,
    required int? sleepMinutes,
  }) async {
    validateDailyCheckIn(
      localDate: localDate,
      weightKg: weightKg,
      caloriesKcal: caloriesKcal,
      proteinGrams: proteinGrams,
      carbohydrateGrams: carbohydrateGrams,
      fatGrams: fatGrams,
      steps: steps,
      sleepMinutes: sleepMinutes,
    );
    final now = clock().toUtc();
    final rows = await store.readAggregates('daily-check-in');
    LocalAggregateEnvelope<Object?>? existing;
    for (final row in rows) {
      if (_map(row.workingCopy)['localDate'] == localDate) {
        existing = row;
        break;
      }
    }
    final id = existing?.aggregateId ?? ids();
    final prior = existing == null ? null : _map(existing.workingCopy);
    final checkIn = DailyCheckIn(
      localDate: localDate,
      weightKg: weightKg,
      caloriesKcal: caloriesKcal,
      proteinGrams: proteinGrams,
      carbohydrateGrams: carbohydrateGrams,
      fatGrams: fatGrams,
      steps: steps,
      sleepMinutes: sleepMinutes,
      createdAtUtc: prior?['createdAtUtc'] as String? ?? now.toIso8601String(),
      updatedAtUtc: now.toIso8601String(),
    );
    await store.commitMutation(
      mutationId: ids(),
      aggregateType: 'daily-check-in',
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
    );
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
      localDate: localDate,
      weightKg: weightKg,
      caloriesKcal: null,
      proteinGrams: null,
      carbohydrateGrams: null,
      fatGrams: null,
      steps: null,
      sleepMinutes: null,
    );
    final ledgerKey = 'health-ledger:body-mass';
    final rawLedger = await store.readSyncMetadata(ledgerKey);
    final ledger = rawLedger is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawLedger)
        : <String, dynamic>{'probes': <String, Object?>{}};
    final probes = ledger['probes'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(ledger['probes'] as Map<String, dynamic>)
        : <String, dynamic>{};
    if (probes.containsKey(probeId)) {
      final id =
          (probes[probeId] as Map<String, dynamic>?)?['checkInId'] as String?;
      return HealthCheckInCommitResult(
        HealthCheckInCommitStatus.duplicate,
        checkInId: id,
      );
    }
    final rows = await store.readAggregates('daily-check-in');
    LocalAggregateEnvelope<Object?>? existing;
    for (final row in rows) {
      if (_map(row.workingCopy)['localDate'] == localDate) {
        existing = row;
        break;
      }
    }
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
        mutationId: ids(),
        aggregateType: 'daily-check-in',
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
            aggregateType: 'daily-check-in',
            aggregateId: id,
            optimisticVersion: existing?.optimisticVersion,
            serverVersion: existing?.serverVersion,
          ),
        ],
        mutationGuard: sessionGuard,
        createdAtUtc: now,
      );
    } on StateError catch (error) {
      if (attempt < 2 &&
          (error.message.contains('Health import state changed') ||
              error.message.contains('local resource changed'))) {
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
