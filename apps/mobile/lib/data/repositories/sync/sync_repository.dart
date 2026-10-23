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
    var pulled = 0;
    // Zweiter Durchgang nur, wenn die Selbstheilung nach dem Pull etwas neu
    // eingereiht hat.
    for (var round = 0; round < 2; round++) {
      if (registration.isActiveWriter) {
        final push = await _pushAsActiveWriter(clientId, timestamp);
        pushed += push.pushed;
        if (push.stopState case final stopState?) {
          return _stopAfterPush(stopState, pushed);
        }
      }
      try {
        pulled += await _pullAll();
      } on ApiException catch (error) {
        final blocked = await _pullFailureReport(error, pushed);
        if (blocked == null) rethrow;
        return blocked;
      }
      if (!registration.isActiveWriter || await _healStaleConflicts() == 0) {
        break;
      }
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
    // Mehrere Durchgänge: Selbstheilung reiht neue Einträge ein, und
    // Einträge mit wartender Referenz kommen erst nach deren Bestätigung dran.
    // Jede Mutation wird je Lauf höchstens einmal versucht.
    final attempted = <String>{};
    while (true) {
      await _prepareSequences();
      final outbox = await store.readOutbox();
      final waiting = _unconfirmedCreates(outbox);
      final candidates = _oldestReadyPerAggregate(
        outbox,
        timestamp,
      ).where((record) => !attempted.contains(record.mutationId)).toList();
      var progressed = false;
      for (final record in candidates) {
        // Wartende Referenz: überspringen, pending lassen, kein Konflikt und
        // kein Backoff, damit der Rest weiterläuft (D3).
        if (SyncPayloadCodec.referencedAggregateIds(record)
            .any(waiting.contains)) {
          continue;
        }
        attempted.add(record.mutationId);
        progressed = true;
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
          await store.deleteSyncMetadata(
            _healGuardKey(syncing.aggregateType, syncing.aggregateId),
          );
          if (syncing.operation == LocalMutationOperation.create) {
            waiting.remove(syncing.aggregateId);
          }
          pushed++;
        } on ApiException catch (error) {
          final shouldStop = await _handlePushError(syncing, error, timestamp);
          if (shouldStop != null) {
            return (pushed: pushed, stopState: shouldStop);
          }
        }
      }
      if (!progressed) break;
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

  List<LocalMutation> _oldestReadyPerAggregate(
    List<LocalMutation> records,
    DateTime now,
  ) {
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

  /// Ressourcen, deren Anlegen der Server noch nicht bestätigt hat: Wer auf sie
  /// verweist, muss warten.
  Set<String> _unconfirmedCreates(List<LocalMutation> outbox) => {
    for (final mutation in outbox)
      if (mutation.operation == LocalMutationOperation.create &&
          mutation.status != LocalMutationStatus.clean)
        mutation.aggregateId,
  };

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
    if (pending.isNotEmpty &&
        _recreatableAggregateTypes.contains(aggregateType) &&
        await _isOwnMutation(batch.originMutationId, aggregateType, change)) {
      // Die eigene Löschung ist bestätigt, danach wurde neu gespeichert: kein
      // Konflikt. Der wartende Stand baut auf der Version der Löschung auf.
      await _keepAfterOwnDelete(aggregateType, change, keepWorkingCopy: true);
      await _advanceNextMutationBase(
        aggregateType: aggregateType,
        aggregateId: change.resourceId,
        originMutationId: batch.originMutationId!,
        version: change.version,
      );
    } else if (pending.isEmpty &&
        _recreatableAggregateTypes.contains(aggregateType)) {
      // Löschmarke mit der Version der Löschung behalten, damit ein neuer
      // Stand dieselbe ID mit der richtigen Basis speichert.
      await _keepAfterOwnDelete(aggregateType, change, keepWorkingCopy: false);
    } else if (pending.isNotEmpty) {
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

  Future<bool> _isOwnMutation(
    String? originMutationId,
    String aggregateType,
    SyncChangeResponse change,
  ) async {
    if (originMutationId == null) return false;
    final database = store.database;
    final row =
        await (database.select(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(store.accountId) &
                  t.mutationId.equals(originMutationId) &
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(change.resourceId),
            ))
            .getSingleOrNull();
    return row != null;
  }

  /// Schreibt die Zeile einer gelöschten, neu speicherbaren Ressource mit
  /// der Version der Löschung. Mit [keepWorkingCopy] bleibt ein wartender
  /// neuer Stand erhalten, sonst bleibt nur eine Löschmarke.
  Future<void> _keepAfterOwnDelete(
    String aggregateType,
    SyncChangeResponse change, {
    required bool keepWorkingCopy,
  }) async {
    final database = store.database;
    final existing =
        await (database.select(database.localResources)..where(
              (t) =>
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(change.resourceId),
            ))
            .getSingleOrNull();
    final old = existing == null
        ? null
        : LocalAggregateEnvelope<Object?>.fromJson(
            jsonDecode(existing.envelopeJson) as Map<String, dynamic>,
          );
    final envelope = LocalAggregateEnvelope<Object?>(
      aggregateId: change.resourceId,
      serverSnapshot: null,
      workingCopy: keepWorkingCopy && old != null
          ? old.workingCopy
          : {
              'deletedAtUtc':
                  (old?.workingCopy is Map
                      ? (old!.workingCopy! as Map)['deletedAtUtc']
                      : null) ??
                  DateTime.now().toUtc().toIso8601String(),
            },
      serverVersion: change.version,
      optimisticVersion: old?.optimisticVersion ?? change.version,
      syncState: keepWorkingCopy
          ? LocalSyncState.pending
          : LocalSyncState.clean,
    );
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
    await _flagForeignChange(batch, aggregateType, change.resourceId);
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

  /// Ablehnungen, die ein veralteter Zwischenstand verursacht haben kann (D2).
  static const _healableCodes = {
    'active_workout_exists',
    'validation_failed',
    'stale_base_version',
    'resource_not_found',
  };

  static String _healGuardKey(String aggregateType, String aggregateId) =>
      'auto-heal:$aggregateType:$aggregateId';

  /// Löst eindeutige Ablehnungen ohne Rückfrage. Gibt `true` zurück, wenn der
  /// Eintrag erledigt oder neu eingereiht ist und kein Konflikt entstehen soll.
  /// `stale_base_version` entscheidet erst [_healStaleConflicts] nach dem Pull,
  /// weil erst dann der Serverstand bekannt ist.
  Future<bool> _tryAutoHeal(LocalMutation mutation, ApiException error) async {
    final type = mutation.aggregateType;
    final id = mutation.aggregateId;
    if (!forceableAggregateTypes.contains(type)) return false;
    final envelope = await store.readAggregate(type, id);
    if (envelope == null ||
        await store.hasTombstone(_resourceTypeForAggregate(type), id)) {
      return false;
    }
    final rows = await _aggregateRows(type, id);
    if (rows.any(_spansResources)) return false;
    final working = envelope.workingCopy;
    final deleted =
        rows.lastOrNull?.operation == LocalMutationOperation.delete ||
        (working is Map && working['deletedAtUtc'] != null);
    if (deleted && envelope.serverVersion == null) {
      await store.discardLocalResource(type, id);
      return true;
    }
    if (error.code == 'validation_failed') {
      final outbox = await store.readOutbox();
      if (SyncPayloadCodec.referencedAggregateIds(mutation)
          .any(_unconfirmedCreates(outbox).contains)) {
        await store.updateMutation(
          _copyMutation(
            mutation,
            status: LocalMutationStatus.pending,
            clearError: true,
          ),
        );
        return true;
      }
    }
    if (error.code == 'stale_base_version') return false;
    return _requeueIfNewer(mutation, rows, working, error.code);
  }

  /// Reiht den aktuellen lokalen Stand einmal neu ein, wenn er neuer ist als
  /// der abgelehnte. Je Ressource und Code nur ein Versuch (Schleifenschutz).
  Future<bool> _requeueIfNewer(
    LocalMutation rejected,
    List<LocalMutation> rows,
    Object? working,
    String code,
  ) async {
    final newer =
        rows.any((row) => row.sequence > rejected.sequence) ||
        !_sameJson(working, rejected.body);
    if (!newer) return false;
    final key = _healGuardKey(rejected.aggregateType, rejected.aggregateId);
    final tried = await store.readSyncMetadata(key);
    final codes = tried is List ? tried.whereType<String>().toList() : [];
    if (codes.contains(code)) return false;
    await store.writeSyncMetadata(key, [...codes, code]);
    try {
      await store.requeueLocalState(
        aggregateType: rejected.aggregateType,
        aggregateId: rejected.aggregateId,
        replacementMutationId: newUuidV4(),
        createdAtUtc: DateTime.now().toUtc(),
      );
    } on StateError {
      return false;
    }
    return true;
  }

  Future<List<LocalMutation>> _aggregateRows(String type, String id) async => [
    for (final row in await store.readOutbox(aggregateType: type))
      if (row.aggregateId == id) row,
  ];

  bool _spansResources(LocalMutation mutation) =>
      mutation.operation == LocalMutationOperation.merge ||
      mutation.operation == LocalMutationOperation.reorder;

  /// Nach dem Pull: veraltete Basisversion, die nur der eigene Stand erklärt.
  /// Der Server hat die Ressource seit dem letzten bekannten Stand nicht durch
  /// ein anderes Gerät geändert, und lokal liegt ein neuerer Stand vor.
  Future<int> _healStaleConflicts() async {
    var healed = 0;
    for (final conflict in await readConflicts()) {
      final detail = conflict.detail;
      if (conflict.code != 'stale_base_version' ||
          detail is! Map ||
          detail['foreignChange'] == true ||
          ((detail['baseVersion'] as int?) ?? 0) !=
              ((detail['knownServerVersion'] as int?) ?? 0)) {
        continue;
      }
      final type = conflict.aggregateType;
      if (!forceableAggregateTypes.contains(type)) continue;
      final envelope = await store.readAggregate(type, conflict.aggregateId);
      if (envelope == null ||
          await store.hasTombstone(
            _resourceTypeForAggregate(type),
            conflict.aggregateId,
          )) {
        continue;
      }
      final rows = await _aggregateRows(type, conflict.aggregateId);
      final rejected = rows
          .where((row) => row.mutationId == conflict.conflictId)
          .firstOrNull;
      if (rejected == null || rows.any(_spansResources)) continue;
      if (await _requeueIfNewer(
        rejected,
        rows,
        envelope.workingCopy,
        conflict.code,
      )) {
        healed++;
      }
    }
    return healed;
  }

  /// Hält fest, dass ein anderes Gerät die Ressource geändert hat; die
  /// Selbstheilung von `stale_base_version` greift dann nicht mehr.
  Future<void> _flagForeignChange(
    SyncChangeBatchResponse batch,
    String aggregateType,
    String aggregateId,
  ) async {
    final database = store.database;
    final conflicts =
        await (database.select(database.localConflicts)..where(
              (t) =>
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(aggregateId) &
                  t.code.equals('stale_base_version'),
            ))
            .get();
    if (conflicts.isEmpty) return;
    final origin = batch.originMutationId;
    final own =
        origin != null &&
        await (database.select(database.localOutbox)..where(
                  (t) =>
                      t.accountId.equals(store.accountId) &
                      t.mutationId.equals(origin),
                ))
                .getSingleOrNull() !=
            null;
    if (own) return;
    for (final conflict in conflicts) {
      final detail = jsonDecode(conflict.detailJson);
      if (detail is! Map<String, dynamic>) continue;
      detail['foreignChange'] = true;
      await (database.update(
        database.localConflicts,
      )..where((t) => t.conflictId.equals(conflict.conflictId))).write(
        LocalConflictsCompanion(detailJson: Value(jsonEncode(detail))),
      );
    }
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
    if ((error.statusCode == 409 || error.statusCode == 422) &&
        _healableCodes.contains(error.code) &&
        await _tryAutoHeal(mutation, error)) {
      return null;
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
      final known = error.code == 'stale_base_version'
          ? (await store.readAggregate(
              mutation.aggregateType,
              mutation.aggregateId,
            ))?.serverVersion
          : null;
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
            if (error.code == 'stale_base_version') ...{
              'baseVersion': mutation.baseVersion,
              'knownServerVersion': known,
            },
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

/// Ressourcen, die nach dem Löschen unter derselben ID neu gespeichert
/// werden; ihre Löschmarke behält die Version der Löschung.
const _recreatableAggregateTypes = {'training-schedule'};

String _resourceTypeForAggregate(String aggregateType) =>
    switch (aggregateType) {
      'body-goal' => 'BodyGoal',
      'daily-check-in' => 'DailyCheckIn',
      'custom-exercise' => 'CustomExercise',
      'exercise-category' => 'ExerciseCategory',
      'training-plan' => 'TrainingPlan',
      'training-schedule' => 'TrainingSchedule',
      'workout' => 'Workout',
      'nutrition-day' => 'NutritionDay',
      'reusable-meal' => 'ReusableMeal',
      'nutrition-target-schedule' => 'NutritionTargetSchedule',
      'nutrition-day-template' => 'NutritionDayTemplate',
      'cardio-session' => 'CardioSession',
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

/// Strukturgleichheit von JSON-Werten, unabhängig von der Schlüsselreihenfolge.
bool _sameJson(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _sameJson(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_sameJson(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}
