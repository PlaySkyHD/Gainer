import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../../services/local/local_database.dart';

class LocalResourceExpectation {
  const LocalResourceExpectation({
    required this.aggregateType,
    required this.aggregateId,
    required this.optimisticVersion,
    required this.serverVersion,
  });

  final String aggregateType;
  final String aggregateId;
  final int? optimisticVersion;
  final int? serverVersion;
}

/// Account-scoped durable storage. Every user edit writes its envelope and
/// immutable outbox payload in one SQLite transaction before it may be shown
/// as committed by a caller.
class LocalSyncStore {
  LocalSyncStore({required this.database, required this.accountId}) {
    if (!RegExp(LocalDatabase.accountIdPattern).hasMatch(accountId)) {
      throw ArgumentError.value(accountId, 'accountId', 'Expected a UUID.');
    }
  }

  final LocalDatabase database;
  final String accountId;
  final StreamController<LocalMutation> _committedMutations =
      StreamController<LocalMutation>.broadcast(sync: true);

  Stream<LocalMutation> get committedMutations => _committedMutations.stream;

  Future<LocalAggregateEnvelope<Object?>?> readAggregate(
    String aggregateType,
    String aggregateId,
  ) async {
    await ensureAccountBound();
    final row =
        await (database.select(database.localResources)..where(
              (t) =>
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(aggregateId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return LocalAggregateEnvelope<Object?>.fromJson(
      jsonDecode(row.envelopeJson) as Map<String, dynamic>,
    );
  }

  Future<List<LocalAggregateEnvelope<Object?>>> readAggregates(
    String aggregateType,
  ) async {
    await ensureAccountBound();
    final rows =
        await (database.select(database.localResources)
              ..where((table) => table.aggregateType.equals(aggregateType))
              ..orderBy([(table) => OrderingTerm.asc(table.aggregateId)]))
            .get();
    return rows
        .map(
          (row) => LocalAggregateEnvelope<Object?>.fromJson(
            jsonDecode(row.envelopeJson) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  Future<LocalMutation> commitMutation({
    required String mutationId,
    required String aggregateType,
    required String aggregateId,
    required LocalMutationOperation operation,
    required int? baseVersion,
    required Object? body,
    required LocalAggregateEnvelope<Object?> envelope,
    Map<String, LocalAggregateEnvelope<Object?>> relatedEnvelopes = const {},
    String? dependsOnMutationId,
    DateTime? createdAtUtc,
    Map<String, Object?> localMetadataWrites = const {},
    Map<String, Object?> localMetadataExpectations = const {},
    List<LocalResourceExpectation> resourceExpectations = const [],
    bool Function()? mutationGuard,
    void Function()? afterEnvelopeWriteForTesting,
  }) async {
    _validateMutationInputs(
      mutationId,
      aggregateType,
      aggregateId,
      baseVersion,
    );
    if (envelope.aggregateId != aggregateId ||
        envelope.syncState != LocalSyncState.pending) {
      throw ArgumentError(
        'A committed local edit must be a pending envelope for its aggregate.',
      );
    }
    for (final key in localMetadataWrites.keys) {
      if (!key.startsWith('health-ledger:') || key.length > 160) {
        throw ArgumentError.value(
          key,
          'localMetadataWrites',
          'Only purpose-bound Health ledger metadata may be written here.',
        );
      }
    }
    for (final key in localMetadataExpectations.keys) {
      if (!key.startsWith('health-ledger:') || key.length > 160) {
        throw ArgumentError.value(
          key,
          'localMetadataExpectations',
          'Only purpose-bound Health ledger metadata may be checked here.',
        );
      }
    }

    final created = (createdAtUtc ?? DateTime.now()).toUtc();
    // Encode before entering the transaction so caller mutation after this
    // point cannot alter the durable operation body.
    final payloadJson = jsonEncode({
      'operation': operation.name,
      'baseVersion': baseVersion,
      'body': body,
    });
    final envelopeJson = envelope.encode();
    final relatedJson = <(String, LocalAggregateEnvelope<Object?>, String)>[];
    for (final entry in relatedEnvelopes.entries) {
      final related = entry.value;
      if (related.aggregateId == aggregateId ||
          related.syncState != LocalSyncState.pending ||
          entry.key.trim().isEmpty ||
          !RegExp(LocalDatabase.accountIdPattern)
              .hasMatch(related.aggregateId)) {
        throw ArgumentError('A related mutation envelope is invalid.');
      }
      relatedJson.add((entry.key, related, related.encode()));
    }

    final committed = await database.transaction(() async {
      await _bindAccountInTransaction();
      if (mutationGuard != null && !mutationGuard()) {
        throw StateError(
          'The active account session changed before local commit.',
        );
      }
      for (final expectation in resourceExpectations) {
        final row =
            await (database.select(database.localResources)..where(
                  (t) =>
                      t.aggregateType.equals(expectation.aggregateType) &
                      t.aggregateId.equals(expectation.aggregateId),
                ))
                .getSingleOrNull();
        if (expectation.optimisticVersion == null) {
          if (row != null) {
            throw StateError(
              'A local resource changed during the transaction.',
            );
          }
        } else if (row == null) {
          throw StateError('A local resource changed during the transaction.');
        } else {
          final value = LocalAggregateEnvelope<Object?>.fromJson(
            jsonDecode(row.envelopeJson) as Map<String, dynamic>,
          );
          if (value.optimisticVersion != expectation.optimisticVersion ||
              value.serverVersion != expectation.serverVersion) {
            throw StateError(
              'A local resource changed during the transaction.',
            );
          }
        }
      }
      for (final entry in localMetadataExpectations.entries) {
        final row = await (database.select(
          database.localSyncMetadata,
        )..where((t) => t.key.equals(entry.key))).getSingleOrNull();
        if (row == null) {
          if (entry.value != null) {
            throw StateError(
              'Local Health import state changed during the transaction.',
            );
          }
        } else if (entry.value == null ||
            jsonEncode(jsonDecode(row.valueJson)) != jsonEncode(entry.value)) {
          throw StateError(
            'Local Health import state changed during the transaction.',
          );
        }
      }
      final frozenRow = await (database.select(
        database.localSyncMetadata,
      )..where((t) => t.key.equals('local-writes-frozen'))).getSingleOrNull();
      if (frozenRow != null && jsonDecode(frozenRow.valueJson) == true) {
        throw StateError(
          'Local edits are frozen while sync ownership is handed over.',
        );
      }
      final prior =
          await (database.select(database.localOutbox)..where(
                (t) =>
                    t.accountId.equals(accountId) &
                    t.aggregateType.equals(aggregateType) &
                    t.aggregateId.equals(aggregateId),
              ))
              .get();
      final sequence =
          prior.fold<int>(
            0,
            (max, row) => row.sequence > max ? row.sequence : max,
          ) +
          1;

      await database
          .into(database.localResources)
          .insertOnConflictUpdate(
            LocalResourcesCompanion.insert(
              aggregateType: aggregateType,
              aggregateId: aggregateId,
              envelopeJson: envelopeJson,
              updatedAtEpochMs: created.millisecondsSinceEpoch,
            ),
          );
      for (final (relatedType, related, relatedEnvelopeJson) in relatedJson) {
        await database
            .into(database.localResources)
            .insertOnConflictUpdate(
              LocalResourcesCompanion.insert(
                aggregateType: relatedType,
                aggregateId: related.aggregateId,
                envelopeJson: relatedEnvelopeJson,
                updatedAtEpochMs: created.millisecondsSinceEpoch,
              ),
            );
      }
      afterEnvelopeWriteForTesting?.call();
      await database
          .into(database.localOutbox)
          .insert(
            LocalOutboxCompanion.insert(
              mutationId: mutationId,
              accountId: accountId,
              aggregateType: aggregateType,
              aggregateId: aggregateId,
              sequence: sequence,
              status: LocalMutationStatus.pending.name,
              createdAtUtc: created.toIso8601String(),
              payloadJson: payloadJson,
              baseVersion: Value(baseVersion),
              dependsOnMutationId: Value(dependsOnMutationId),
            ),
          );
      for (final entry in localMetadataWrites.entries) {
        await database
            .into(database.localSyncMetadata)
            .insertOnConflictUpdate(
              LocalSyncMetadataCompanion.insert(
                key: entry.key,
                valueJson: jsonEncode(entry.value),
              ),
            );
      }
      if (mutationGuard != null && !mutationGuard()) {
        throw StateError(
          'The active account session changed before local commit.',
        );
      }
      return LocalMutation(
        mutationId: mutationId,
        accountId: accountId,
        aggregateType: aggregateType,
        aggregateId: aggregateId,
        sequence: sequence,
        status: LocalMutationStatus.pending,
        createdAtUtc: created,
        operation: operation,
        baseVersion: baseVersion,
        body: jsonDecode(payloadJson)['body'],
      );
    });
    _committedMutations.add(committed);
    return committed;
  }

  Future<List<LocalMutation>> readOutbox({String? aggregateType}) async {
    await ensureAccountBound();
    final query = database.select(database.localOutbox)
      ..where((t) => t.accountId.equals(accountId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAtUtc),
        (t) => OrderingTerm.asc(t.sequence),
      ]);
    if (aggregateType != null) {
      query.where((t) => t.aggregateType.equals(aggregateType));
    }
    return (await query.get()).map(_mutationFromRow).toList(growable: false);
  }

  Future<LocalMutation?> readMutation(String mutationId) async {
    await ensureAccountBound();
    final row =
        await (database.select(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.mutationId.equals(mutationId),
            ))
            .getSingleOrNull();
    return row == null ? null : _mutationFromRow(row);
  }

  Future<void> updateMutation(LocalMutation mutation) async {
    await ensureAccountBound();
    if (mutation.accountId != accountId) {
      throw ArgumentError('Mutation belongs to another account database.');
    }
    await (database.update(database.localOutbox)..where(
          (t) =>
              t.accountId.equals(accountId) &
              t.mutationId.equals(mutation.mutationId),
        ))
        .write(
          LocalOutboxCompanion(
            status: Value(mutation.status.name),
            clientSequence: Value(mutation.clientSequence),
            dependsOnMutationId: Value(mutation.dependsOnMutationId),
            attemptCount: Value(mutation.attemptCount),
            nextAttemptAtUtc: Value(
              mutation.nextAttemptAtUtc?.toUtc().toIso8601String(),
            ),
            lastErrorCode: Value(mutation.lastErrorCode),
            baseVersion: Value(mutation.baseVersion),
            payloadJson: Value(mutation.encodePayload()),
          ),
        );
  }

  Future<void> deleteMutation(String mutationId) async {
    await ensureAccountBound();
    await (database.delete(database.localOutbox)..where(
          (t) =>
              t.accountId.equals(accountId) & t.mutationId.equals(mutationId),
        ))
        .go();
  }

  Future<int> nextClientSequence() async {
    final value = await readSyncMetadata('next-client-sequence');
    return value is int ? value + 1 : 1;
  }

  Future<Object?> readSyncMetadata(String key) async {
    await ensureAccountBound();
    final row = await (database.select(
      database.localSyncMetadata,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.valueJson);
  }

  Future<void> writeSyncMetadata(String key, Object? value) async {
    _validateWritableMetadataKey(key);
    await ensureAccountBound();
    await database
        .into(database.localSyncMetadata)
        .insertOnConflictUpdate(
          LocalSyncMetadataCompanion.insert(
            key: key,
            valueJson: jsonEncode(value),
          ),
        );
  }

  Future<void> writeSyncMetadataBatch(Map<String, Object?> values) async {
    for (final key in values.keys) {
      _validateWritableMetadataKey(key);
    }
    await ensureAccountBound();
    await database.transaction(() async {
      for (final entry in values.entries) {
        await database
            .into(database.localSyncMetadata)
            .insertOnConflictUpdate(
              LocalSyncMetadataCompanion.insert(
                key: entry.key,
                valueJson: jsonEncode(entry.value),
              ),
            );
      }
    });
  }

  Future<void> upsertConflict(LocalConflictRecord conflict) async {
    await ensureAccountBound();
    await database
        .into(database.localConflicts)
        .insertOnConflictUpdate(
          LocalConflictsCompanion.insert(
            conflictId: conflict.conflictId,
            aggregateType: conflict.aggregateType,
            aggregateId: conflict.aggregateId,
            createdAtUtc: conflict.createdAtUtc.toUtc().toIso8601String(),
            code: conflict.code,
            detailJson: jsonEncode(conflict.detail),
          ),
        );
  }

  Future<void> upsertTombstone(LocalTombstoneRecord tombstone) async {
    await ensureAccountBound();
    await database
        .into(database.localTombstones)
        .insertOnConflictUpdate(
          LocalTombstonesCompanion.insert(
            resourceType: tombstone.resourceType,
            resourceId: tombstone.resourceId,
            revision: tombstone.revision,
          ),
        );
  }

  Future<bool> hasTombstone(String resourceType, String resourceId) async {
    await ensureAccountBound();
    return await (database.select(database.localTombstones)..where(
              (t) =>
                  t.resourceType.equals(resourceType) &
                  t.resourceId.equals(resourceId),
            ))
            .getSingleOrNull() !=
        null;
  }

  /// Binds this SQLite file to the first authenticated account that opens it.
  /// A copied/restored file can never be used with another account's session.
  Future<void> ensureAccountBound() async {
    await database.transaction(_bindAccountInTransaction);
  }

  /// Freezes local writes only after every mutation has reached the server and
  /// been reconciled through pull. This closes the race before server handover.
  Future<void> freezeWritesIfOutboxEmpty() async {
    await database.transaction(() async {
      await _bindAccountInTransaction();
      final pending = await (database.select(
        database.localOutbox,
      )..where((t) => t.accountId.equals(accountId))).get();
      if (pending.isNotEmpty) {
        throw StateError(
          'Local edits cannot freeze until the outbox is empty.',
        );
      }
      await database
          .into(database.localSyncMetadata)
          .insertOnConflictUpdate(
            LocalSyncMetadataCompanion.insert(
              key: 'local-writes-frozen',
              valueJson: jsonEncode(true),
            ),
          );
    });
  }

  Future<void> unfreezeWrites() async {
    await database.transaction(() async {
      await _bindAccountInTransaction();
      await database
          .into(database.localSyncMetadata)
          .insertOnConflictUpdate(
            LocalSyncMetadataCompanion.insert(
              key: 'local-writes-frozen',
              valueJson: jsonEncode(false),
            ),
          );
    });
  }

  Future<void> _bindAccountInTransaction() async {
    final owner = await (database.select(
      database.localSyncMetadata,
    )..where((t) => t.key.equals('account-owner-id'))).getSingleOrNull();
    if (owner == null) {
      await database
          .into(database.localSyncMetadata)
          .insert(
            LocalSyncMetadataCompanion.insert(
              key: 'account-owner-id',
              valueJson: jsonEncode(accountId),
            ),
          );
      return;
    }
    final savedAccountId = jsonDecode(owner.valueJson);
    if (savedAccountId != accountId) {
      throw StateError('This local database is bound to another account.');
    }
  }

  void _validateWritableMetadataKey(String key) {
    if ({
      'account-owner-id',
      'local-writes-frozen',
      'sync-lease',
    }.contains(key)) {
      throw ArgumentError.value(
        key,
        'key',
        'Account ownership metadata is reserved.',
      );
    }
  }

  Future<void> close() async {
    await _committedMutations.close();
    await database.close();
  }

  LocalMutation _mutationFromRow(LocalOutboxData row) {
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    final operation = LocalMutationOperation.values.firstWhere(
      (value) => value.name == payload['operation'],
      orElse: () => throw const FormatException('Unknown outbox operation.'),
    );
    final status = LocalMutationStatus.values.firstWhere(
      (value) => value.name == row.status,
      orElse: () => throw const FormatException('Unknown outbox status.'),
    );
    return LocalMutation(
      mutationId: row.mutationId,
      accountId: row.accountId,
      aggregateType: row.aggregateType,
      aggregateId: row.aggregateId,
      sequence: row.sequence,
      status: status,
      createdAtUtc: DateTime.parse(row.createdAtUtc).toUtc(),
      operation: operation,
      baseVersion: payload['baseVersion'] as int?,
      body: payload['body'],
      clientSequence: row.clientSequence,
      dependsOnMutationId: row.dependsOnMutationId,
      attemptCount: row.attemptCount,
      nextAttemptAtUtc: row.nextAttemptAtUtc == null
          ? null
          : DateTime.parse(row.nextAttemptAtUtc!).toUtc(),
      lastErrorCode: row.lastErrorCode,
    );
  }

  void _validateMutationInputs(
    String mutationId,
    String aggregateType,
    String aggregateId,
    int? baseVersion,
  ) {
    if (!RegExp(LocalDatabase.accountIdPattern).hasMatch(mutationId)) {
      throw ArgumentError.value(mutationId, 'mutationId', 'Expected a UUID.');
    }
    if (aggregateType.trim().isEmpty ||
        !RegExp(LocalDatabase.accountIdPattern).hasMatch(aggregateId)) {
      throw ArgumentError(
        'Aggregate type must be set and aggregate ID must be a UUID.',
      );
    }
    if (baseVersion != null && baseVersion < 0) {
      throw ArgumentError.value(baseVersion, 'baseVersion');
    }
  }
}

class InstallationIdentityStore {
  InstallationIdentityStore(this.database);

  final LocalDatabase database;

  Future<String> getOrCreateInstallationId() async {
    return database.transaction(() async {
      final existing = await (database.select(
        database.installationMetadata,
      )..where((t) => t.key.equals('installation-id'))).getSingleOrNull();
      if (existing != null &&
          RegExp(LocalDatabase.accountIdPattern).hasMatch(existing.value)) {
        return existing.value;
      }
      final id = _newUuidV4();
      await database
          .into(database.installationMetadata)
          .insertOnConflictUpdate(
            InstallationMetadataCompanion.insert(
              key: 'installation-id',
              value: id,
            ),
          );
      return id;
    });
  }
}

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
