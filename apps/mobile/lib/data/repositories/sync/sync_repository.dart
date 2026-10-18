import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/api/sync_api_models.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../../services/api/api_client.dart';
import '../../services/local/local_database.dart';
import '../../services/local/pending_handover_secret_store.dart';
import 'local_conflict_recovery.dart';
import 'local_sync_store.dart';
import 'native_handover_repository.dart';
import 'sync_payload_codec.dart';

/// Trainingsoperationen verlangen Protokollversion 3; sonst antwortet der
/// Server mit `upgrade_required`.
const nativeSyncProtocolVersion = 3;

const _syncLeaseKey = 'sync-lease';
const _pullCursorKey = pullCursorMetadataKey;

enum SyncRunState {
  idle,
  busy,
  synced,
  retryPending,
  authBlocked,
  inactiveClient,
  upgradeRequired,
}

class SyncRunReport {
  const SyncRunReport({
    required this.state,
    required this.pushed,
    required this.pulledBatches,
    this.nextRetryAtUtc,
  });

  final SyncRunState state;
  final int pushed;
  final int pulledBatches;
  final DateTime? nextRetryAtUtc;
}

/// Sync v2 coordinator over the existing API client and durable SQLite store.
/// The pull path is available to registered non-writers; only the active writer
/// is allowed to push mutations.
abstract interface class MobileSyncActions {
  Future<PendingHandoverRecord?> readPendingHandover();
  Future<BeginSyncHandoverResponse> beginHandover({required String requestId});
  Future<CompleteSyncHandoverResponse> completeHandover({
    required String handoverId,
    required String oneTimeCode,
    required int frozenRevision,
    required String sourceClientId,
    required DateTime expiresAtUtc,
  });
  Future<bool> recoverExpiredTargetHandover();
  Future<void> cancelHandover({required String handoverId});
  Future<List<LocalConflictRecord>> readConflicts();
  Future<void> acceptConflictServerState(String conflictId);
  Future<String> retryConflictOnCurrentServerVersion({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  });
  Future<Map<String, ConflictResourceInfo>> readConflictResourceInfos();
  Future<void> forceLocalState({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  });
  Future<SyncRunReport> synchronize({
    bool takeOverWriting = false,
    DateTime? now,
  });
}

class SyncRepository implements MobileSyncActions {
  SyncRepository({
    required this.store,
    required this.api,
    required this.installationIdentity,
    required this.displayName,
    this.handoverSecrets,
  });

  final LocalSyncStore store;
  final ApiClient api;
  final InstallationIdentityStore installationIdentity;
  final String displayName;
  final PendingHandoverSecretStore? handoverSecrets;
  Future<SyncRunReport>? _activeSync;
  final String _leaseOwnerId = _newLeaseOwnerId();

  late final NativeHandoverRepository _handover = NativeHandoverRepository(
    store: store,
    api: api,
    installationIdentity: installationIdentity,
    displayName: displayName,
    secrets: handoverSecrets,
    assertSessionMatchesStore: _assertCurrentSessionMatchesStore,
    synchronizeSource: _synchronizeSourceForHandover,
    pullAll: _pullAll,
  );

  Future<void> _synchronizeSourceForHandover() async {
    final result = await synchronize();
    if (result.state == SyncRunState.authBlocked ||
        result.state == SyncRunState.upgradeRequired ||
        result.state == SyncRunState.inactiveClient ||
        result.state == SyncRunState.retryPending) {
      throw StateError(
        'The source client cannot begin handover in its current sync state.',
      );
    }
  }

  @override
  Future<PendingHandoverRecord?> readPendingHandover() =>
      _handover.readPendingHandover();

  @override
  Future<List<LocalConflictRecord>> readConflicts() async {
    await store.ensureAccountBound();
    final rows = await (store.database.select(
      store.database.localConflicts,
    )..orderBy([(row) => OrderingTerm.desc(row.createdAtUtc)])).get();
    return rows
        .map(
          (row) => LocalConflictRecord(
            conflictId: row.conflictId,
            aggregateType: row.aggregateType,
            aggregateId: row.aggregateId,
            createdAtUtc: DateTime.parse(row.createdAtUtc).toUtc(),
            code: row.code,
            detail: jsonDecode(row.detailJson),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> acceptConflictServerState(String conflictId) =>
      store.acceptConflictServerState(conflictId);

  @override
  Future<String> retryConflictOnCurrentServerVersion({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  }) => store.retryConflictOnCurrentServerVersion(
    conflictId: conflictId,
    replacementMutationId: replacementMutationId,
    createdAtUtc: createdAtUtc,
  );

  @override
  Future<Map<String, ConflictResourceInfo>> readConflictResourceInfos() =>
      store.readConflictResourceInfos();

  @override
  Future<void> forceLocalState({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  }) => store.forceLocalState(
    conflictId: conflictId,
    replacementMutationId: replacementMutationId,
    createdAtUtc: createdAtUtc,
  );

  @override
  Future<SyncRunReport> synchronize({
    bool takeOverWriting = false,
    DateTime? now,
  }) {
    final active = _activeSync;
    if (active != null) return active;
    final run = _synchronizeWithLease(
      takeOverWriting: takeOverWriting,
      now: now,
    );
    _activeSync = run;
    return run.whenComplete(() {
      if (identical(_activeSync, run)) _activeSync = null;
    });
  }

  Future<SyncRunReport> _synchronizeWithLease({
    required bool takeOverWriting,
    DateTime? now,
  }) async {
    await store.ensureAccountBound();
    final database = store.database;
    final currentTime = (now ?? DateTime.now()).toUtc();
    final acquired = await database.transaction(() async {
      final row = await (database.select(
        database.localSyncMetadata,
      )..where((t) => t.key.equals(_syncLeaseKey))).getSingleOrNull();
      if (row != null) {
        final value = jsonDecode(row.valueJson);
        if (value is Map<String, dynamic> &&
            value['ownerId'] != _leaseOwnerId &&
            value['expiresAtUtc'] is String &&
            (value['expiresAtUtc'] as String).compareTo(
                  currentTime.toIso8601String(),
                ) >
                0) {
          return false;
        }
      }
      await database
          .into(database.localSyncMetadata)
          .insertOnConflictUpdate(
            LocalSyncMetadataCompanion.insert(
              key: _syncLeaseKey,
              valueJson: jsonEncode({
                'ownerId': _leaseOwnerId,
                'expiresAtUtc': currentTime
                    .add(const Duration(minutes: 5))
                    .toIso8601String(),
              }),
            ),
          );
      return true;
    });
    if (!acquired) {
      return const SyncRunReport(
        state: SyncRunState.busy,
        pushed: 0,
        pulledBatches: 0,
      );
    }
    try {
      return await _synchronizeOnce(takeOverWriting: takeOverWriting, now: now);
    } finally {
      await database.transaction(() async {
        final row = await (database.select(
          database.localSyncMetadata,
        )..where((t) => t.key.equals(_syncLeaseKey))).getSingleOrNull();
        if (row == null) return;
        final value = jsonDecode(row.valueJson);
        if (value is Map<String, dynamic> &&
            value['ownerId'] == _leaseOwnerId) {
          await (database.delete(
            database.localSyncMetadata,
          )..where((t) => t.key.equals(_syncLeaseKey))).go();
        }
      });
    }
  }

  Future<SyncRunReport> _synchronizeOnce({
    required bool takeOverWriting,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    await store.ensureAccountBound();
    await _refreshSyncLease();
    final session = await api.getSession();
    if (session == null) {
      return _blockAuthorization('authentication_required');
    }
    if (session.userId.toLowerCase() != store.accountId.toLowerCase()) {
      return _blockAuthorization('account_changed');
    }
    final clientId = await installationIdentity.getOrCreateInstallationId();
    SyncClientRegistrationResponse registration;
    try {
      await _refreshSyncLease();
      registration = await api.registerSyncClient(
        SyncClientRegistrationRequest(
          clientId: clientId,
          displayName: displayName,
          protocolVersion: nativeSyncProtocolVersion,
          takeOverWriting: takeOverWriting,
        ),
        expectedAccountId: store.accountId,
      );
    } on ApiException catch (error) {
      final blocked = await _registrationFailureReport(error);
      if (blocked == null) rethrow;
      return blocked;
    }

    var pushed = 0;
    if (registration.isActiveWriter) {
      final push = await _pushAsActiveWriter(clientId, timestamp);
      pushed = push.pushed;
      if (push.stopState case final stopState?) {
        return _stopAfterPush(stopState, pushed);
      }
    }

    late final int pulled;
    try {
      pulled = await _pullAll();
    } on ApiException catch (error) {
      final blocked = await _pullFailureReport(error, pushed);
      if (blocked == null) rethrow;
      return blocked;
    }
    if (!registration.isActiveWriter) {
      return SyncRunReport(
        state: SyncRunState.inactiveClient,
        pushed: pushed,
        pulledBatches: pulled,
      );
    }
    return _reportAfterPull(
      pushed: pushed,
      pulled: pulled,
      timestamp: timestamp,
    );
  }

  Future<SyncRunReport> _blockAuthorization(
    String code, {
    int pushed = 0,
  }) async {
    await _markStatuses(
      {LocalMutationStatus.pending, LocalMutationStatus.syncing},
      LocalMutationStatus.authBlocked,
      code,
    );
    return SyncRunReport(
      state: SyncRunState.authBlocked,
      pushed: pushed,
      pulledBatches: 0,
    );
  }

  Future<SyncRunReport?> _registrationFailureReport(ApiException error) async {
    if (error.statusCode == 401) {
      return _blockAuthorization('authentication_required');
    }
    if (error.code == 'account_changed') {
      return _blockAuthorization(error.code);
    }
    if (error.code == 'upgrade_required') {
      await _markStatuses(
        {LocalMutationStatus.pending, LocalMutationStatus.syncing},
        LocalMutationStatus.upgradeRequired,
        error.code,
      );
      return const SyncRunReport(
        state: SyncRunState.upgradeRequired,
        pushed: 0,
        pulledBatches: 0,
      );
    }
    return null;
  }

  Future<SyncRunReport?> _pullFailureReport(
    ApiException error,
    int pushed,
  ) async {
    if (error.statusCode == 401 || error.code == 'account_changed') {
      return _blockAuthorization(
        error.code == 'account_changed'
            ? error.code
            : 'authentication_required',
        pushed: pushed,
      );
    }
    return null;
  }

  Future<({int pushed, SyncRunState? stopState})> _pushAsActiveWriter(
    String clientId,
    DateTime timestamp,
  ) async {
    var pushed = 0;
    await _resumeInactiveAndAuthenticated();
    await _prepareSequences();
    final candidates = await _oldestReadyPerAggregate(timestamp);
    for (final record in candidates) {
      await _refreshSyncLease();
      // Claim re-reads the entry in a transaction: the body sent is the one
      // stored now, and no later edit can coalesce into it once it is claimed.
      final syncing = await store.claimMutationForSending(
        record.mutationId,
        now: timestamp,
      );
      if (syncing == null) continue;
      try {
        final request = _toRequest(syncing, clientId);
        final response = await api.pushMutation(
          mutationId: syncing.mutationId,
          mutation: request,
          expectedAccountId: store.accountId,
        );
        if (response.mutationId != syncing.mutationId) {
          throw const FormatException(
            'Sync response mutation id does not match the request.',
          );
        }
        // Keep the same id/payload until pull applies the canonical server
        // batch. This makes a timeout/retry safe under server idempotency.
        await store.updateMutation(
          _copyMutation(
            syncing,
            status: LocalMutationStatus.clean,
            clearError: true,
          ),
        );
        pushed++;
      } on ApiException catch (error) {
        final shouldStop = await _handlePushError(syncing, error, timestamp);
        if (shouldStop != null) {
          return (pushed: pushed, stopState: shouldStop);
        }
      }
    }
    return (pushed: pushed, stopState: null);
  }

  Future<SyncRunReport> _stopAfterPush(SyncRunState state, int pushed) async {
    final pulled = state == SyncRunState.authBlocked ? 0 : await _pullAll();
    return SyncRunReport(state: state, pushed: pushed, pulledBatches: pulled);
  }

  Future<SyncRunReport> _reportAfterPull({
    required int pushed,
    required int pulled,
    required DateTime timestamp,
  }) async {
    final pending = (await store.readOutbox()).where(
      (mutation) => mutation.status == LocalMutationStatus.pending,
    );
    if (pending.isNotEmpty) {
      final retryAt = pending
          .map((mutation) => mutation.nextAttemptAtUtc ?? timestamp)
          .reduce((left, right) => left.isBefore(right) ? left : right);
      return SyncRunReport(
        state: SyncRunState.retryPending,
        pushed: pushed,
        pulledBatches: pulled,
        nextRetryAtUtc: retryAt,
      );
    }
    final state = pushed > 0 || pulled > 0
        ? SyncRunState.synced
        : SyncRunState.idle;
    return SyncRunReport(state: state, pushed: pushed, pulledBatches: pulled);
  }

  Future<void> resumeAfterAuthentication() async {
    final records = await store.readOutbox();
    for (final record in records.where(
      (m) => m.status == LocalMutationStatus.authBlocked,
    )) {
      await store.updateMutation(
        _copyMutation(
          record,
          status: LocalMutationStatus.pending,
          clearError: true,
        ),
      );
    }
  }

  @override
  Future<BeginSyncHandoverResponse> beginHandover({
    required String requestId,
  }) => _handover.begin(requestId: requestId);

  @override
  Future<CompleteSyncHandoverResponse> completeHandover({
    required String handoverId,
    required String oneTimeCode,
    required int frozenRevision,
    required String sourceClientId,
    required DateTime expiresAtUtc,
  }) => _handover.complete(
    handoverId: handoverId,
    oneTimeCode: oneTimeCode,
    frozenRevision: frozenRevision,
    sourceClientId: sourceClientId,
    expiresAtUtc: expiresAtUtc,
  );

  @override
  Future<bool> recoverExpiredTargetHandover() =>
      _handover.recoverExpiredTargetHandover();

  @override
  Future<void> cancelHandover({required String handoverId}) =>
      _handover.cancel(handoverId: handoverId);
  Future<void> _assertCurrentSessionMatchesStore() async {
    await store.ensureAccountBound();
    final session = await api.getSession();
    if (session == null) {
      throw const ApiException(
        statusCode: 401,
        code: 'authentication_required',
        message: 'An authenticated session is required for handover.',
      );
    }
    if (session.userId.toLowerCase() != store.accountId.toLowerCase()) {
      throw const ApiException(
        statusCode: 409,
        code: 'account_changed',
        message: 'Authenticated API session does not match the local account database.',
      );
    }
  }

  Future<void> _prepareSequences() async {
    final database = store.database;
    await database.transaction(() async {
      final rows =
          await (database.select(database.localOutbox)
                ..where((t) => t.accountId.equals(store.accountId))
                ..orderBy([
                  (t) => OrderingTerm.asc(t.createdAtUtc),
                  (t) => OrderingTerm.asc(t.sequence),
                ]))
              .get();
      final sequenceRow = await (database.select(
        database.localSyncMetadata,
      )..where((t) => t.key.equals('next-client-sequence'))).getSingleOrNull();
      var next = sequenceRow == null
          ? 0
          : (jsonDecode(sequenceRow.valueJson) as int);
      final lastMutationByAggregate = <String, String>{};
      for (final row in rows) {
        final aggregateKey = '${row.aggregateType}:${row.aggregateId}';
        final knownDependency =
            row.dependsOnMutationId ?? lastMutationByAggregate[aggregateKey];
        if (row.clientSequence == null) {
          next++;
          await (database.update(database.localOutbox)..where(
                (t) =>
                    t.accountId.equals(store.accountId) &
                    t.mutationId.equals(row.mutationId),
              ))
              .write(
                LocalOutboxCompanion(
                  clientSequence: Value(next),
                  dependsOnMutationId: Value(knownDependency),
                ),
              );
        }
        lastMutationByAggregate[aggregateKey] = row.mutationId;
      }
      await database
          .into(database.localSyncMetadata)
          .insertOnConflictUpdate(
            LocalSyncMetadataCompanion.insert(
              key: 'next-client-sequence',
              valueJson: jsonEncode(next),
            ),
          );
    });
  }

  Future<List<LocalMutation>> _oldestReadyPerAggregate(DateTime now) async {
    final records = await store.readOutbox();
    final result = <LocalMutation>[];
    final seen = <String>{};
    for (final record in records) {
      if (!seen.add(record.aggregateKey)) continue;
      if (record.status == LocalMutationStatus.pending &&
          (record.nextAttemptAtUtc == null ||
              !record.nextAttemptAtUtc!.isAfter(now))) {
        result.add(record);
      }
    }
    return result;
  }

  Future<int> _pullAll() async {
    var applied = 0;
    while (true) {
      final cursorValue = await store.readSyncMetadata(_pullCursorKey);
      final cursor = cursorValue is int ? cursorValue : 0;
      final response = await _fetchPullPage(cursor);
      _validatePullResponse(response, cursor);
      if (response.batches.isEmpty) {
        if (response.nextCursor != cursor) {
          await store.writeSyncMetadata(_pullCursorKey, response.nextCursor);
        }
        break;
      }
      for (final batch in response.batches) {
        await _applyBatch(batch);
        applied++;
      }
      if (!response.hasMore) break;
    }
    return applied;
  }

  Future<SyncPullResponse> _fetchPullPage(int cursor) async {
    try {
      await _refreshSyncLease();
      return await api.pullChanges(
        after: cursor,
        limit: 200,
        expectedAccountId: store.accountId,
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.code == 'account_changed') {
        await _markStatuses(
          {LocalMutationStatus.pending, LocalMutationStatus.syncing},
          LocalMutationStatus.authBlocked,
          error.code == 'account_changed'
              ? error.code
              : 'authentication_required',
        );
      }
      rethrow;
    }
  }

  void _validatePullResponse(SyncPullResponse response, int cursor) {
    if (response.protocolVersion != nativeSyncProtocolVersion) {
      throw const FormatException(
        'Unsupported sync protocol version in pull response.',
      );
    }
    if (response.nextCursor < cursor) {
      throw const FormatException('Sync cursor cannot move backwards.');
    }
  }

  Future<void> _applyBatch(SyncChangeBatchResponse batch) async {
    final database = store.database;
    await database.transaction(() async {
      for (final change in batch.changes) {
        final aggregateType = SyncPayloadCodec.aggregateTypeForResource(
          change.resourceType,
        );
        if (aggregateType == null) {
          throw FormatException(
            'Unsupported sync resource type ${change.resourceType}; pull cursor was not advanced.',
          );
        }
        if (change.isTombstone) {
          await _applyTombstone(batch, change, aggregateType);
          continue;
        }
        await _applyUpsert(batch, change, aggregateType);
      }
      if (batch.originMutationId != null) {
        await (database.delete(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(store.accountId) &
                  t.mutationId.equals(batch.originMutationId!),
            ))
            .go();
      }
      await database
          .into(database.localSyncMetadata)
          .insertOnConflictUpdate(
            LocalSyncMetadataCompanion.insert(
              key: _pullCursorKey,
              valueJson: jsonEncode(batch.revision),
            ),
          );
    });
  }

  Future<void> _applyTombstone(
    SyncChangeBatchResponse batch,
    SyncChangeResponse change,
    String aggregateType,
  ) async {
    final database = store.database;
    final pending =
        await (database.select(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(store.accountId) &
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(change.resourceId) &
                  t.status.isNotValue(LocalMutationStatus.clean.name),
            ))
            .get();
    if (pending.isNotEmpty) {
      final old =
          await (database.select(database.localResources)..where(
                (t) =>
                    t.aggregateType.equals(aggregateType) &
                    t.aggregateId.equals(change.resourceId),
              ))
              .getSingleOrNull();
      if (old != null) {
        final envelope = LocalAggregateEnvelope<Object?>.fromJson(
          jsonDecode(old.envelopeJson) as Map<String, dynamic>,
        );
        final conflicted = LocalAggregateEnvelope(
          aggregateId: envelope.aggregateId,
          serverSnapshot: null,
          workingCopy: envelope.workingCopy,
          serverVersion: null,
          optimisticVersion: envelope.optimisticVersion,
          syncState: LocalSyncState.conflict,
        );
        await (database.update(database.localResources)..where(
              (t) =>
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(change.resourceId),
            ))
            .write(
              LocalResourcesCompanion(envelopeJson: Value(conflicted.encode())),
            );
      }
      await database
          .into(database.localConflicts)
          .insertOnConflictUpdate(
            LocalConflictsCompanion.insert(
              conflictId:
                  'tombstone:${change.resourceType}:${change.resourceId}:${batch.revision}',
              aggregateType: aggregateType,
              aggregateId: change.resourceId,
              createdAtUtc: DateTime.now().toUtc().toIso8601String(),
              code: 'server_deleted_local_pending',
              detailJson: jsonEncode({
                'revision': batch.revision,
                'resourceType': change.resourceType,
              }),
            ),
          );
      for (final row in pending) {
        await (database.update(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(store.accountId) &
                  t.mutationId.equals(row.mutationId),
            ))
            .write(
              const LocalOutboxCompanion(
                status: Value('conflict'),
                lastErrorCode: Value('server_deleted'),
              ),
            );
      }
    } else {
      await (database.delete(database.localResources)..where(
            (t) =>
                t.aggregateType.equals(aggregateType) &
                t.aggregateId.equals(change.resourceId),
          ))
          .go();
    }
    await database
        .into(database.localTombstones)
        .insertOnConflictUpdate(
          LocalTombstonesCompanion.insert(
            resourceType: change.resourceType,
            resourceId: change.resourceId,
            revision: batch.revision,
          ),
        );
  }

  Future<void> _applyUpsert(
    SyncChangeBatchResponse batch,
    SyncChangeResponse change,
    String aggregateType,
  ) async {
    final database = store.database;
    final existing =
        await (database.select(database.localResources)..where(
              (t) =>
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(change.resourceId),
            ))
            .getSingleOrNull();
    final pending =
        await (database.select(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(store.accountId) &
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(change.resourceId) &
                  t.status.isNotValue(LocalMutationStatus.clean.name),
            ))
            .get();
    final snapshot = SyncPayloadCodec.normalizeSnapshot(
      change.resourceType,
      change.snapshot,
    );
    SyncPayloadCodec.verifyTrainingSnapshot(change.resourceType, snapshot);
    LocalAggregateEnvelope<Object?> envelope;
    if (existing != null && pending.isNotEmpty) {
      final old = LocalAggregateEnvelope<Object?>.fromJson(
        jsonDecode(existing.envelopeJson) as Map<String, dynamic>,
      );
      envelope = LocalAggregateEnvelope(
        aggregateId: old.aggregateId,
        serverSnapshot: snapshot,
        workingCopy: old.workingCopy,
        serverVersion: change.version,
        optimisticVersion: old.optimisticVersion,
        syncState:
            pending.any(
              (row) => row.status == LocalMutationStatus.conflict.name,
            )
            ? LocalSyncState.conflict
            : LocalSyncState.pending,
      );
    } else {
      envelope = serverEnvelope(
        aggregateId: change.resourceId,
        snapshot: snapshot,
        version: change.version,
      );
    }
    await database
        .into(database.localResources)
        .insertOnConflictUpdate(
          LocalResourcesCompanion.insert(
            aggregateType: aggregateType,
            aggregateId: change.resourceId,
            envelopeJson: envelope.encode(),
            updatedAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
    await (database.delete(database.localTombstones)..where(
          (t) =>
              t.resourceType.equals(change.resourceType) &
              t.resourceId.equals(change.resourceId),
        ))
        .go();
    if (batch.originMutationId != null) {
      await _advanceNextMutationBase(
        aggregateType: aggregateType,
        aggregateId: change.resourceId,
        originMutationId: batch.originMutationId!,
        version: change.version,
      );
    }
  }

  Future<void> _advanceNextMutationBase({
    required String aggregateType,
    required String aggregateId,
    required String originMutationId,
    required int version,
  }) async {
    final database = store.database;
    final rows =
        await (database.select(database.localOutbox)
              ..where(
                (t) =>
                    t.accountId.equals(store.accountId) &
                    t.aggregateType.equals(aggregateType) &
                    t.aggregateId.equals(aggregateId) &
                    t.mutationId.isNotValue(originMutationId),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
            .get();
    if (rows.isEmpty) return;
    final row = rows.first;
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    payload['baseVersion'] = version;
    await (database.update(database.localOutbox)..where(
          (t) =>
              t.accountId.equals(store.accountId) &
              t.mutationId.equals(row.mutationId),
        ))
        .write(
          LocalOutboxCompanion(
            baseVersion: Value(version),
            payloadJson: Value(jsonEncode(payload)),
          ),
        );
  }

  Future<SyncRunState?> _handlePushError(
    LocalMutation mutation,
    ApiException error,
    DateTime now,
  ) async {
    if (error.code == 'account_changed') {
      await _markStatuses(
        {LocalMutationStatus.pending, LocalMutationStatus.syncing},
        LocalMutationStatus.authBlocked,
        error.code,
      );
      return SyncRunState.authBlocked;
    }
    if (error.statusCode == 401) {
      await _markStatuses(
        {LocalMutationStatus.pending, LocalMutationStatus.syncing},
        LocalMutationStatus.authBlocked,
        'authentication_required',
      );
      return SyncRunState.authBlocked;
    }
    if (error.code == 'inactive_client') {
      await _markStatuses(
        {LocalMutationStatus.pending, LocalMutationStatus.syncing},
        LocalMutationStatus.inactiveClient,
        error.code,
      );
      return SyncRunState.inactiveClient;
    }
    if (error.code == 'upgrade_required') {
      await _markStatuses(
        {LocalMutationStatus.pending, LocalMutationStatus.syncing},
        LocalMutationStatus.upgradeRequired,
        error.code,
      );
      return SyncRunState.upgradeRequired;
    }
    if (error.statusCode == 409) {
      if ({
        'concurrent_mutation',
        'concurrent_handover',
        'handover_in_progress',
      }.contains(error.code)) {
        await _scheduleRetry(mutation, error, now);
        return null;
      }
      await store.upsertConflict(
        LocalConflictRecord(
          conflictId: mutation.mutationId,
          aggregateType: mutation.aggregateType,
          aggregateId: mutation.aggregateId,
          createdAtUtc: now,
          code: error.code,
          detail: {'message': error.message, 'mutationId': mutation.mutationId},
        ),
      );
      await store.updateMutation(
        _copyMutation(
          mutation,
          status: LocalMutationStatus.conflict,
          lastErrorCode: error.code,
        ),
      );
      return null;
    }
    if (error.statusCode == 422 && error.code == 'validation_failed') {
      // Field errors cannot be fixed by resending the same payload, so they
      // stay visible as a conflict on the aggregate until the user decides.
      await store.upsertConflict(
        LocalConflictRecord(
          conflictId: mutation.mutationId,
          aggregateType: mutation.aggregateType,
          aggregateId: mutation.aggregateId,
          createdAtUtc: now,
          code: error.code,
          detail: {
            'message': error.message,
            'mutationId': mutation.mutationId,
            'errors': error.errors ?? const {},
          },
        ),
      );
      await store.updateMutation(
        _copyMutation(
          mutation,
          status: LocalMutationStatus.conflict,
          lastErrorCode: error.code,
        ),
      );
      return null;
    }
    if (error.statusCode == 422) {
      await store.updateMutation(
        _copyMutation(
          mutation,
          status: LocalMutationStatus.failed,
          lastErrorCode: error.code,
        ),
      );
      return null;
    }
    await _scheduleRetry(mutation, error, now);
    return null;
  }

  Future<void> _scheduleRetry(
    LocalMutation mutation,
    ApiException error,
    DateTime now,
  ) async {
    final attempts = mutation.attemptCount + 1;
    final delay = Duration(
      milliseconds: min(60000, 1000 * (1 << min(attempts - 1, 6))),
    );
    await store.updateMutation(
      _copyMutation(
        mutation,
        status: LocalMutationStatus.pending,
        attemptCount: attempts,
        nextAttemptAtUtc: now.add(delay),
        lastErrorCode: error.code,
      ),
    );
  }

  Future<void> _refreshSyncLease() async {
    final database = store.database;
    await database.transaction(() async {
      final row = await (database.select(
        database.localSyncMetadata,
      )..where((t) => t.key.equals(_syncLeaseKey))).getSingleOrNull();
      if (row == null) return;
      final value = jsonDecode(row.valueJson);
      if (value is! Map<String, dynamic> || value['ownerId'] != _leaseOwnerId) {
        throw StateError('This sync run no longer owns the local sync lease.');
      }
      await database
          .into(database.localSyncMetadata)
          .insertOnConflictUpdate(
            LocalSyncMetadataCompanion.insert(
              key: _syncLeaseKey,
              valueJson: jsonEncode({
                'ownerId': _leaseOwnerId,
                'expiresAtUtc': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 2))
                    .toIso8601String(),
              }),
            ),
          );
    });
  }

  Future<void> _markStatuses(
    Set<LocalMutationStatus> from,
    LocalMutationStatus to,
    String code,
  ) async {
    final records = await store.readOutbox();
    for (final record in records.where((row) => from.contains(row.status))) {
      await store.updateMutation(
        _copyMutation(record, status: to, lastErrorCode: code),
      );
    }
  }

  Future<void> _resumeInactiveAndAuthenticated() async {
    final records = await store.readOutbox();
    for (final record in records.where(
      (row) =>
          row.status == LocalMutationStatus.inactiveClient ||
          row.status == LocalMutationStatus.authBlocked ||
          row.status == LocalMutationStatus.syncing,
    )) {
      await store.updateMutation(
        _copyMutation(
          record,
          status: LocalMutationStatus.pending,
          clearError: true,
          clearRetry:
              record.status == LocalMutationStatus.syncing ||
              record.status == LocalMutationStatus.authBlocked ||
              record.status == LocalMutationStatus.inactiveClient,
        ),
      );
    }
  }

  SyncMutationRequest _toRequest(LocalMutation mutation, String clientId) {
    if (mutation.clientSequence == null) {
      throw StateError('Mutation sequence was not prepared.');
    }
    final body = mutation.body;
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Sync mutation payload must be an object.');
    }
    final resourceType = _resourceTypeForAggregate(mutation.aggregateType);
    final baseVersion = mutation.baseVersion ?? 0;
    final resources = <SyncResourceVersionRequest>[
      SyncResourceVersionRequest(
        resourceType: resourceType,
        resourceId: mutation.aggregateId,
        baseVersion: baseVersion,
      ),
    ];
    if (mutation.aggregateType == 'body-goal' &&
        body['expectedActiveGoalId'] is String &&
        body['expectedActiveGoalVersion'] is int) {
      resources.add(
        SyncResourceVersionRequest(
          resourceType: 'BodyGoal',
          resourceId: body['expectedActiveGoalId'] as String,
          baseVersion: body['expectedActiveGoalVersion'] as int,
        ),
      );
    }
    if (mutation.operation == LocalMutationOperation.reorder) {
      // The reorder mutation locks every plan it reorders, not only the first.
      resources.clear();
      for (final plan in body['plans'] as List<Object?>) {
        final map = plan! as Map<String, dynamic>;
        resources.add(
          SyncResourceVersionRequest(
            resourceType: 'TrainingPlan',
            resourceId: map['planId'] as String,
            baseVersion: map['baseVersion'] as int,
          ),
        );
      }
    }
    if (mutation.operation == LocalMutationOperation.merge &&
        body['targetBaseVersion'] is int) {
      resources.add(
        SyncResourceVersionRequest(
          resourceType: 'CustomExercise',
          resourceId: body['targetExerciseId'] as String,
          baseVersion: body['targetBaseVersion'] as int,
        ),
      );
    }
    return SyncMutationRequest(
      protocolVersion: nativeSyncProtocolVersion,
      clientId: clientId,
      clientSequence: mutation.clientSequence!,
      operation: SyncPayloadCodec.serverOperation(mutation, body),
      resources: resources,
      dependsOnMutationId: mutation.dependsOnMutationId,
      payload: SyncPayloadCodec.serverPayload(mutation, body, baseVersion),
    );
  }
}

LocalMutation _copyMutation(
  LocalMutation source, {
  LocalMutationStatus? status,
  int? clientSequence,
  String? dependsOnMutationId,
  int? attemptCount,
  DateTime? nextAttemptAtUtc,
  String? lastErrorCode,
  int? baseVersion,
  bool clearRetry = false,
  bool clearError = false,
  bool clearDependency = false,
}) => LocalMutation(
  mutationId: source.mutationId,
  accountId: source.accountId,
  aggregateType: source.aggregateType,
  aggregateId: source.aggregateId,
  sequence: source.sequence,
  status: status ?? source.status,
  createdAtUtc: source.createdAtUtc,
  operation: source.operation,
  baseVersion: baseVersion ?? source.baseVersion,
  body: source.body,
  clientSequence: clientSequence ?? source.clientSequence,
  dependsOnMutationId: clearDependency
      ? null
      : (dependsOnMutationId ?? source.dependsOnMutationId),
  attemptCount: attemptCount ?? source.attemptCount,
  nextAttemptAtUtc: clearRetry
      ? null
      : (nextAttemptAtUtc ?? source.nextAttemptAtUtc),
  lastErrorCode: clearError ? null : (lastErrorCode ?? source.lastErrorCode),
);

String _resourceTypeForAggregate(String aggregateType) =>
    switch (aggregateType) {
      'body-goal' => 'BodyGoal',
      'daily-check-in' => 'DailyCheckIn',
      'custom-exercise' => 'CustomExercise',
      'exercise-category' => 'ExerciseCategory',
      'training-plan' => 'TrainingPlan',
      'workout-rotation' => 'WorkoutRotation',
      'workout' => 'Workout',
      'nutrition-day' => 'NutritionDay',
      'reusable-meal' => 'ReusableMeal',
      'nutrition-target-schedule' => 'NutritionTargetSchedule',
      _ => throw ArgumentError.value(
        aggregateType,
        'aggregateType',
        'Unsupported sync aggregate.',
      ),
    };

String _newLeaseOwnerId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
