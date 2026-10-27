import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../../services/local/local_database.dart';
import 'local_conflict_recovery.dart' show forceableAggregateTypes;

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

/// Erwartet beim Commit, dass kein anderes Aggregat vom Typ [aggregateType]
/// als [aggregateId] im Arbeitsstand das Feld [field] mit [value] hat. Für
/// Aggregate mit fachlichem Schlüssel (ein Check-in je Tag): Ein Pull zwischen
/// Lesen und Commit kann die Serverzeile desselben Schlüssels unter einer
/// anderen ID schreiben; die ID-Erwartung allein bemerkt das nicht.
class LocalUniqueFieldExpectation extends LocalResourceExpectation {
  const LocalUniqueFieldExpectation({
    required super.aggregateType,
    required super.aggregateId,
    required this.field,
    required this.value,
  }) : super(optimisticVersion: null, serverVersion: null);

  final String field;
  final Object value;
}

const _resourceChangedMessage =
    'A local resource changed during the transaction.';

/// Eine [LocalResourceExpectation] stimmte beim Commit nicht mehr; nichts
/// wurde geschrieben. Aufrufer lesen neu und versuchen es erneut. Bleibt ein
/// [StateError], damit bestehende Behandlungen weiter greifen.
class LocalResourceChangedException extends StateError {
  LocalResourceChangedException() : super(_resourceChangedMessage);
}

/// Lokale Änderungen sind während einer Geräteübergabe eingefroren; nichts
/// wurde geschrieben.
class LocalWritesFrozenException extends StateError {
  LocalWritesFrozenException()
    : super('Local edits are frozen while sync ownership is handed over.');
}

const _localWritesFrozenKey = 'local-writes-frozen';
const _accountOwnerIdKey = 'account-owner-id';
const pullCursorMetadataKey = 'pull-cursor';

/// Local aggregate types of the training model before the rebuild, plus the
/// new ones. Tombstones store server resource names instead.
const _trainingAggregateTypes = [
  'workout',
  'workout-template',
  'training-schedule',
  'custom-exercise',
  'training-plan',
  'exercise-category',
];

/// Ressourcen, die nach dem Löschen unter derselben ID neu gespeichert
/// werden (höchstens eine je Nutzer, z. B. der Trainingsrhythmus).
const _recreatableAggregateTypes = {'training-schedule'};

const _trainingResourceTypes = [
  'Workout',
  'WorkoutTemplate',
  'TrainingSchedule',
  'CustomExercise',
  'TrainingPlan',
  'ExerciseCategory',
];

void _requireMutationGuard(bool Function()? mutationGuard) {
  if (mutationGuard != null && !mutationGuard()) {
    throw StateError('The active account session changed before local commit.');
  }
}

void _validateHealthLedgerKeys(
  Iterable<String> keys,
  String parameterName,
  String message,
) {
  for (final key in keys) {
    if (!key.startsWith('health-ledger:') || key.length > 160) {
      throw ArgumentError.value(key, parameterName, message);
    }
  }
}

List<(String, LocalAggregateEnvelope<Object?>, String)> _encodeRelatedEnvelopes(
  String aggregateId,
  List<(String, LocalAggregateEnvelope<Object?>)> relatedEnvelopes,
) {
  final relatedJson = <(String, LocalAggregateEnvelope<Object?>, String)>[];
  for (final (relatedType, related) in relatedEnvelopes) {
    if (related.aggregateId == aggregateId ||
        related.syncState != LocalSyncState.pending ||
        relatedType.trim().isEmpty ||
        !RegExp(LocalDatabase.accountIdPattern).hasMatch(related.aggregateId)) {
      throw ArgumentError('A related mutation envelope is invalid.');
    }
    relatedJson.add((relatedType, related, related.encode()));
  }
  return relatedJson;
}

/// Everything [LocalSyncStore.commitMutation] needs to persist one local edit
/// and its outbox entry atomically.
class MutationDraft {
  const MutationDraft({
    required this.mutationId,
    required this.aggregateType,
    required this.aggregateId,
    required this.operation,
    required this.baseVersion,
    required this.body,
    required this.envelope,
    this.relatedEnvelopes = const [],
    this.dependsOnMutationId,
    this.createdAtUtc,
    this.localMetadataWrites = const {},
    this.localMetadataExpectations = const {},
    this.resourceExpectations = const [],
    this.mutationGuard,
    this.afterEnvelopeWriteForTesting,
  });

  final String mutationId;
  final String aggregateType;
  final String aggregateId;
  final LocalMutationOperation operation;
  final int? baseVersion;
  final Object? body;
  final LocalAggregateEnvelope<Object?> envelope;
  final List<(String, LocalAggregateEnvelope<Object?>)> relatedEnvelopes;
  final String? dependsOnMutationId;
  final DateTime? createdAtUtc;
  final Map<String, Object?> localMetadataWrites;
  final Map<String, Object?> localMetadataExpectations;
  final List<LocalResourceExpectation> resourceExpectations;
  final bool Function()? mutationGuard;
  final void Function()? afterEnvelopeWriteForTesting;
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

  Future<LocalMutation> commitMutation(MutationDraft draft) async {
    final mutationId = draft.mutationId;
    final aggregateType = draft.aggregateType;
    final aggregateId = draft.aggregateId;
    final operation = draft.operation;
    final baseVersion = draft.baseVersion;
    final body = draft.body;
    final envelope = draft.envelope;
    final relatedEnvelopes = draft.relatedEnvelopes;
    final dependsOnMutationId = draft.dependsOnMutationId;
    final createdAtUtc = draft.createdAtUtc;
    final localMetadataWrites = draft.localMetadataWrites;
    final localMetadataExpectations = draft.localMetadataExpectations;
    final resourceExpectations = draft.resourceExpectations;
    final mutationGuard = draft.mutationGuard;
    final afterEnvelopeWriteForTesting = draft.afterEnvelopeWriteForTesting;
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
    _validateHealthLedgerKeys(
      localMetadataWrites.keys,
      'localMetadataWrites',
      'Only purpose-bound Health ledger metadata may be written here.',
    );
    _validateHealthLedgerKeys(
      localMetadataExpectations.keys,
      'localMetadataExpectations',
      'Only purpose-bound Health ledger metadata may be checked here.',
    );

    final created = (createdAtUtc ?? DateTime.now()).toUtc();
    // Encode before entering the transaction so caller mutation after this
    // point cannot alter the durable operation body.
    final payloadJson = jsonEncode({
      'operation': operation.name,
      'baseVersion': baseVersion,
      'body': body,
    });
    final envelopeJson = envelope.encode();
    final relatedJson = _encodeRelatedEnvelopes(aggregateId, relatedEnvelopes);

    final committed = await database.transaction(() async {
      await _bindAccountInTransaction();
      _requireMutationGuard(mutationGuard);
      await _verifyResourceExpectations(resourceExpectations);
      await _verifyMetadataExpectations(localMetadataExpectations);
      final frozenRow = await (database.select(
        database.localSyncMetadata,
      )..where((t) => t.key.equals(_localWritesFrozenKey))).getSingleOrNull();
      if (frozenRow != null && jsonDecode(frozenRow.valueJson) == true) {
        throw LocalWritesFrozenException();
      }
      final sequence = await _nextOutboxSequence(aggregateType, aggregateId);
      final tail = await _coalescingTail(
        aggregateType,
        aggregateId,
        operation,
        body,
      );

      await _writeResources(
        removesResource: tail?.removesResource ?? false,
        aggregateType: aggregateType,
        aggregateId: aggregateId,
        envelopeJson: envelopeJson,
        relatedJson: relatedJson,
        updatedAtEpochMs: created.millisecondsSinceEpoch,
      );
      afterEnvelopeWriteForTesting?.call();
      final LocalMutation committedMutation;
      if (tail != null && tail.removesResource) {
        await (database.delete(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.mutationId.equals(tail.row.mutationId),
            ))
            .go();
        await (database.update(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.dependsOnMutationId.equals(tail.row.mutationId),
            ))
            .write(
              const LocalOutboxCompanion(
                dependsOnMutationId: Value<String?>(null),
              ),
            );
        committedMutation = LocalMutation(
          mutationId: mutationId,
          accountId: accountId,
          aggregateType: aggregateType,
          aggregateId: aggregateId,
          sequence: tail.row.sequence,
          status: LocalMutationStatus.pending,
          createdAtUtc: created,
          operation: operation,
          baseVersion: baseVersion,
          body: jsonDecode(payloadJson)['body'],
        );
      } else if (tail != null) {
        // Zusammengefasst: Der wartende Eintrag behält Mutation-ID, Sequenz und
        // Basisversion; nur Operation und Body ändern sich.
        final tailBaseVersion =
            (jsonDecode(tail.row.payloadJson)
                    as Map<String, dynamic>)['baseVersion']
                as int?;
        await (database.update(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.mutationId.equals(tail.row.mutationId),
            ))
            .write(
              LocalOutboxCompanion(
                payloadJson: Value(
                  jsonEncode({
                    'operation': tail.operation.name,
                    'baseVersion': tailBaseVersion,
                    'body': body,
                  }),
                ),
              ),
            );
        committedMutation = _mutationFromRow(
          await (database.select(database.localOutbox)
                ..where((t) => t.mutationId.equals(tail.row.mutationId)))
              .getSingle(),
        );
      } else {
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
        committedMutation = LocalMutation(
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
      }
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
      _requireMutationGuard(mutationGuard);
      return committedMutation;
    });
    _committedMutations.add(committed);
    return committed;
  }

  Future<void> _verifyResourceExpectations(
    List<LocalResourceExpectation> expectations,
  ) async {
    for (final expectation in expectations) {
      if (expectation is LocalUniqueFieldExpectation) {
        await _verifyUniqueField(expectation);
      } else {
        await _verifyResourceVersion(expectation);
      }
    }
  }

  Future<void> _verifyResourceVersion(
    LocalResourceExpectation expectation,
  ) async {
    final row =
        await (database.select(database.localResources)..where(
              (t) =>
                  t.aggregateType.equals(expectation.aggregateType) &
                  t.aggregateId.equals(expectation.aggregateId),
            ))
            .getSingleOrNull();
    if (expectation.optimisticVersion == null) {
      if (row != null) {
        throw LocalResourceChangedException();
      }
    } else if (row == null) {
      throw LocalResourceChangedException();
    } else {
      final value = LocalAggregateEnvelope<Object?>.fromJson(
        jsonDecode(row.envelopeJson) as Map<String, dynamic>,
      );
      if (value.optimisticVersion != expectation.optimisticVersion ||
          value.serverVersion != expectation.serverVersion) {
        throw LocalResourceChangedException();
      }
    }
  }

  Future<void> _verifyUniqueField(
    LocalUniqueFieldExpectation expectation,
  ) async {
    final rows =
        await (database.select(database.localResources)..where(
              (t) =>
                  t.aggregateType.equals(expectation.aggregateType) &
                  t.aggregateId.equals(expectation.aggregateId).not(),
            ))
            .get();
    for (final row in rows) {
      final workingCopy = LocalAggregateEnvelope<Object?>.fromJson(
        jsonDecode(row.envelopeJson) as Map<String, dynamic>,
      ).workingCopy;
      if (workingCopy is Map &&
          workingCopy[expectation.field] == expectation.value) {
        throw LocalResourceChangedException();
      }
    }
  }

  Future<void> _verifyMetadataExpectations(
    Map<String, Object?> expectations,
  ) async {
    for (final entry in expectations.entries) {
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
  }

  Future<int> _nextOutboxSequence(
    String aggregateType,
    String aggregateId,
  ) async {
    final prior =
        await (database.select(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(aggregateId),
            ))
            .get();
    return prior.fold<int>(
          0,
          (max, row) => row.sequence > max ? row.sequence : max,
        ) +
        1;
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

  /// Moves a pending entry to `syncing` and returns the stored copy in one
  /// transaction. The sender must use the returned copy: it carries the body
  /// that is persisted now, and a coalesced edit cannot land after the claim.
  Future<LocalMutation?> claimMutationForSending(
    String mutationId, {
    required DateTime now,
  }) {
    return database.transaction(() async {
      await _bindAccountInTransaction();
      final row =
          await (database.select(database.localOutbox)..where(
                (t) =>
                    t.accountId.equals(accountId) &
                    t.mutationId.equals(mutationId),
              ))
              .getSingleOrNull();
      if (row == null || row.status != LocalMutationStatus.pending.name) {
        return null;
      }
      final nextAttempt = row.nextAttemptAtUtc;
      if (nextAttempt != null &&
          DateTime.parse(nextAttempt).toUtc().isAfter(now.toUtc())) {
        return null;
      }
      await (database.update(database.localOutbox)..where(
            (t) =>
                t.accountId.equals(accountId) & t.mutationId.equals(mutationId),
          ))
          .write(
            LocalOutboxCompanion(
              status: Value(LocalMutationStatus.syncing.name),
              lastErrorCode: const Value<String?>(null),
              sentAtUtc: Value(row.sentAtUtc ?? now.toUtc().toIso8601String()),
            ),
          );
      return _mutationFromRow(
        await (database.select(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.mutationId.equals(mutationId),
            ))
            .getSingle(),
      );
    });
  }

  /// Status writes never touch the body. Stale copies held by a sender must
  /// not overwrite a body that a later edit coalesced into the pending entry.
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
          ),
        );
  }

  Future<void> _writeResources({
    required bool removesResource,
    required String aggregateType,
    required String aggregateId,
    required String envelopeJson,
    required List<(String, LocalAggregateEnvelope<Object?>, String)>
    relatedJson,
    required int updatedAtEpochMs,
  }) async {
    if (removesResource) {
      // Angelegt und vor dem Senden gelöscht: Der Server erfährt nie von der
      // Ressource, also bleibt auch lokal nichts zurück.
      await (database.delete(database.localResources)..where(
            (t) =>
                t.aggregateType.equals(aggregateType) &
                t.aggregateId.equals(aggregateId),
          ))
          .go();
    } else {
      await database
          .into(database.localResources)
          .insertOnConflictUpdate(
            LocalResourcesCompanion.insert(
              aggregateType: aggregateType,
              aggregateId: aggregateId,
              envelopeJson: envelopeJson,
              updatedAtEpochMs: updatedAtEpochMs,
            ),
          );
    }
    for (final (relatedType, related, relatedEnvelopeJson) in relatedJson) {
      await database
          .into(database.localResources)
          .insertOnConflictUpdate(
            LocalResourcesCompanion.insert(
              aggregateType: relatedType,
              aggregateId: related.aggregateId,
              envelopeJson: relatedEnvelopeJson,
              updatedAtEpochMs: updatedAtEpochMs,
            ),
          );
    }
  }

  /// Der letzte Outbox-Eintrag der Ressource, wenn er noch nie geclaimt oder
  /// gesendet wurde und die neue Änderung hineinpasst (D1). Gesendete Einträge
  /// behalten ihren Body, damit Wiederholungen idempotent bleiben.
  ///
  /// | wartend | neu    | Ergebnis                                  |
  /// |---------|--------|-------------------------------------------|
  /// | create  | update | create mit neuem Body                     |
  /// | create  | delete | beide entfallen, Ressource wird entfernt  |
  /// | update  | update | update mit neuem Body                     |
  /// | update  | delete | delete mit Basisversion des Wartenden     |
  /// | delete  | update | update mit Basisversion des Wartenden,    |
  /// |         |        | nur für [_recreatableAggregateTypes]      |
  Future<_CoalescingTail?> _coalescingTail(
    String aggregateType,
    String aggregateId,
    LocalMutationOperation operation,
    Object? body,
  ) async {
    if (!forceableAggregateTypes.contains(aggregateType) ||
        (operation != LocalMutationOperation.update &&
            operation != LocalMutationOperation.delete)) {
      return null;
    }
    final tail =
        await (database.select(database.localOutbox)
              ..where(
                (t) =>
                    t.accountId.equals(accountId) &
                    t.aggregateType.equals(aggregateType) &
                    t.aggregateId.equals(aggregateId),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.sequence)])
              ..limit(1))
            .getSingleOrNull();
    if (tail == null ||
        tail.status != LocalMutationStatus.pending.name ||
        tail.sentAtUtc != null ||
        tail.attemptCount != 0 ||
        tail.nextAttemptAtUtc != null ||
        tail.lastErrorCode != null) {
      return null;
    }
    final waiting =
        (jsonDecode(tail.payloadJson) as Map<String, dynamic>)['operation'];
    if (waiting == LocalMutationOperation.create.name) {
      if (operation == LocalMutationOperation.delete) {
        return _CoalescingTail(tail, LocalMutationOperation.create, true);
      }
      // Archivieren steckt nicht in der Anlegen-Nutzlast und ginge verloren.
      if (body is Map && body['isArchived'] == true) return null;
      return _CoalescingTail(tail, LocalMutationOperation.create, false);
    }
    if (waiting == LocalMutationOperation.update.name) {
      return _CoalescingTail(tail, operation, false);
    }
    // Eine ungesendete Löschung, nach der der Nutzer neu speichert, ersetzt
    // der neue Stand: Der Server erfährt nie von der Löschung.
    if (waiting == LocalMutationOperation.delete.name &&
        operation == LocalMutationOperation.update &&
        _recreatableAggregateTypes.contains(aggregateType)) {
      return _CoalescingTail(tail, LocalMutationOperation.update, false);
    }
    return null;
  }

  /// One-time reset of training data after the training rebuild (D11). Runs
  /// before any other access; it removes training envelopes, outbox entries,
  /// conflicts and tombstones and resets the global pull cursor so the server
  /// delivers the current training state again. Other areas are untouched.
  /// Idempotent: once the schema version is stored, nothing changes.
  Future<void> migrateTrainingSchema({
    void Function()? afterFirstDeleteForTesting,
  }) {
    return database.transaction(() async {
      await _bindAccountInTransaction();
      final versionRow =
          await (database.select(database.localSyncMetadata)
                ..where((t) => t.key.equals(trainingSchemaVersionKey)))
              .getSingleOrNull();
      final stored = versionRow == null
          ? null
          : jsonDecode(versionRow.valueJson);
      if (stored is int && stored >= currentTrainingSchemaVersion) return;

      await (database.delete(
        database.localResources,
      )..where((t) => t.aggregateType.isIn(_trainingAggregateTypes))).go();
      afterFirstDeleteForTesting?.call();
      await (database.delete(
        database.localOutbox,
      )..where((t) => t.aggregateType.isIn(_trainingAggregateTypes))).go();
      await (database.delete(
        database.localConflicts,
      )..where((t) => t.aggregateType.isIn(_trainingAggregateTypes))).go();
      await (database.delete(
        database.localTombstones,
      )..where((t) => t.resourceType.isIn(_trainingResourceTypes))).go();
      await (database.delete(
        database.localSyncMetadata,
      )..where((t) => t.key.equals(pullCursorMetadataKey))).go();
      await database
          .into(database.localSyncMetadata)
          .insertOnConflictUpdate(
            LocalSyncMetadataCompanion.insert(
              key: trainingSchemaVersionKey,
              valueJson: jsonEncode(currentTrainingSchemaVersion),
            ),
          );
    });
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

  /// Entfernt einen Metadateneintrag; fehlt er, passiert nichts.
  Future<void> deleteSyncMetadata(String key) async {
    _validateWritableMetadataKey(key);
    await (database.delete(
      database.localSyncMetadata,
    )..where((t) => t.key.equals(key))).go();
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
  /// The account session opens its store through this call, so the training
  /// reset also runs on app start before any repository reads local data.
  Future<void> ensureAccountBound() async {
    await database.transaction(_bindAccountInTransaction);
    await migrateTrainingSchema();
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
              key: _localWritesFrozenKey,
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
              key: _localWritesFrozenKey,
              valueJson: jsonEncode(false),
            ),
          );
    });
  }

  Future<void> _bindAccountInTransaction() async {
    final owner = await (database.select(
      database.localSyncMetadata,
    )..where((t) => t.key.equals(_accountOwnerIdKey))).getSingleOrNull();
    if (owner == null) {
      await database
          .into(database.localSyncMetadata)
          .insert(
            LocalSyncMetadataCompanion.insert(
              key: _accountOwnerIdKey,
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
      _accountOwnerIdKey,
      _localWritesFrozenKey,
      trainingSchemaVersionKey,
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

class _CoalescingTail {
  const _CoalescingTail(this.row, this.operation, this.removesResource);

  final LocalOutboxData row;

  /// Operation des zusammengefassten Eintrags.
  final LocalMutationOperation operation;
  final bool removesResource;
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
      final id = newUuidV4();
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

String newUuidV4() {
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
