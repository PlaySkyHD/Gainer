import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../../services/local/local_database.dart';
import 'local_sync_store.dart';

extension LocalConflictRecovery on LocalSyncStore {
  /// Replaces the local working copy with the last known server copy and
  /// removes all queued edits for that aggregate atomically.
  Future<void> acceptConflictServerState(String conflictId) async {
    await ensureAccountBound();
    await database.transaction(() async {
      final conflict = await (database.select(
        database.localConflicts,
      )..where((t) => t.conflictId.equals(conflictId))).getSingleOrNull();
      if (conflict == null) {
        throw StateError('Conflict is no longer available.');
      }
      final hasTombstone =
          await (database.select(database.localTombstones)..where(
                (t) =>
                    t.resourceType.equals(_serverType(conflict.aggregateType)) &
                    t.resourceId.equals(conflict.aggregateId),
              ))
              .getSingleOrNull();
      if (hasTombstone != null) {
        await (database.delete(database.localResources)..where(
              (t) =>
                  t.aggregateType.equals(conflict.aggregateType) &
                  t.aggregateId.equals(conflict.aggregateId),
            ))
            .go();
        await (database.delete(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.aggregateType.equals(conflict.aggregateType) &
                  t.aggregateId.equals(conflict.aggregateId),
            ))
            .go();
        await (database.delete(
          database.localConflicts,
        )..where((t) => t.conflictId.equals(conflictId))).go();
        return;
      }
      final resource =
          await (database.select(database.localResources)..where(
                (t) =>
                    t.aggregateType.equals(conflict.aggregateType) &
                    t.aggregateId.equals(conflict.aggregateId),
              ))
              .getSingleOrNull();
      if (resource == null) {
        throw StateError('No retained server state is available.');
      }
      final envelope = LocalAggregateEnvelope<Object?>.fromJson(
        jsonDecode(resource.envelopeJson) as Map<String, dynamic>,
      );
      if (envelope.serverSnapshot == null || envelope.serverVersion == null) {
        throw StateError('No retained server state is available.');
      }
      final accepted = serverEnvelope(
        aggregateId: envelope.aggregateId,
        snapshot: envelope.serverSnapshot,
        version: envelope.serverVersion!,
      );
      await (database.update(database.localResources)..where(
            (t) =>
                t.aggregateType.equals(conflict.aggregateType) &
                t.aggregateId.equals(conflict.aggregateId),
          ))
          .write(
            LocalResourcesCompanion(envelopeJson: Value(accepted.encode())),
          );
      await (database.delete(database.localOutbox)..where(
            (t) =>
                t.accountId.equals(accountId) &
                t.aggregateType.equals(conflict.aggregateType) &
                t.aggregateId.equals(conflict.aggregateId),
          ))
          .go();
      await (database.delete(
        database.localConflicts,
      )..where((t) => t.conflictId.equals(conflictId))).go();
    });
  }

  /// Explicitly reapplies a local operation against the retained current
  /// server version with a fresh idempotency key. Tombstones are never revived.
  Future<String> retryConflictOnCurrentServerVersion({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  }) async {
    await ensureAccountBound();
    if (!RegExp(LocalDatabase.accountIdPattern)
        .hasMatch(replacementMutationId)) {
      throw ArgumentError.value(replacementMutationId, 'replacementMutationId');
    }
    return database.transaction(() async {
      final conflict = await (database.select(
        database.localConflicts,
      )..where((t) => t.conflictId.equals(conflictId))).getSingleOrNull();
      if (conflict == null) {
        throw StateError('Conflict is no longer available.');
      }
      final resourceType = _serverType(conflict.aggregateType);
      final tombstone =
          await (database.select(database.localTombstones)..where(
                (t) =>
                    t.resourceType.equals(resourceType) &
                    t.resourceId.equals(conflict.aggregateId),
              ))
              .getSingleOrNull();
      if (tombstone != null) {
        throw StateError(
          'A server-deleted resource cannot be restored silently.',
        );
      }
      final resource =
          await (database.select(database.localResources)..where(
                (t) =>
                    t.aggregateType.equals(conflict.aggregateType) &
                    t.aggregateId.equals(conflict.aggregateId),
              ))
              .getSingleOrNull();
      if (resource == null) {
        throw StateError('Local conflict copy is unavailable.');
      }
      final envelope = LocalAggregateEnvelope<Object?>.fromJson(
        jsonDecode(resource.envelopeJson) as Map<String, dynamic>,
      );
      if (envelope.serverVersion == null) {
        throw StateError('No current server version is available.');
      }
      final rows =
          await (database.select(database.localOutbox)
                ..where(
                  (t) =>
                      t.accountId.equals(accountId) &
                      t.aggregateType.equals(conflict.aggregateType) &
                      t.aggregateId.equals(conflict.aggregateId),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
              .get();
      if (rows.isEmpty) {
        throw StateError('Local mutation is no longer available.');
      }
      final old = rows.first;
      if (conflict.aggregateType == 'workout' &&
          envelope.workingCopy is Map<String, dynamic> &&
          ['completed', 'discarded'].contains(
            ((envelope.workingCopy as Map<String, dynamic>)['status'] ?? '')
                .toString()
                .toLowerCase(),
          )) {
        throw StateError(
          'Completed or discarded workouts cannot be reapplied.',
        );
      }
      final payload = jsonDecode(old.payloadJson) as Map<String, dynamic>;
      payload['baseVersion'] = envelope.serverVersion;
      await (database.delete(database.localOutbox)..where(
            (t) =>
                t.accountId.equals(accountId) &
                t.mutationId.equals(old.mutationId),
          ))
          .go();
      await database
          .into(database.localOutbox)
          .insert(
            LocalOutboxCompanion.insert(
              mutationId: replacementMutationId,
              accountId: accountId,
              aggregateType: old.aggregateType,
              aggregateId: old.aggregateId,
              sequence: old.sequence,
              status: LocalMutationStatus.pending.name,
              createdAtUtc: createdAtUtc.toUtc().toIso8601String(),
              payloadJson: jsonEncode(payload),
              baseVersion: Value(envelope.serverVersion),
              dependsOnMutationId: Value(old.mutationId),
            ),
          );
      final pending = LocalAggregateEnvelope(
        aggregateId: envelope.aggregateId,
        serverSnapshot: envelope.serverSnapshot,
        workingCopy: envelope.workingCopy,
        serverVersion: envelope.serverVersion,
        optimisticVersion: envelope.optimisticVersion,
        syncState: LocalSyncState.pending,
      );
      await (database.update(database.localResources)..where(
            (t) =>
                t.aggregateType.equals(conflict.aggregateType) &
                t.aggregateId.equals(conflict.aggregateId),
          ))
          .write(
            LocalResourcesCompanion(envelopeJson: Value(pending.encode())),
          );
      await (database.delete(
        database.localConflicts,
      )..where((t) => t.conflictId.equals(conflictId))).go();
      return replacementMutationId;
    });
  }
}

String _serverType(String aggregateType) => switch (aggregateType) {
  'body-goal' => 'BodyGoal',
  'daily-check-in' => 'DailyCheckIn',
  'custom-exercise' => 'CustomExercise',
  'workout-template' => 'WorkoutTemplate',
  'workout-rotation' => 'WorkoutRotation',
  'workout' => 'Workout',
  'nutrition-day' => 'NutritionDay',
  'reusable-meal' => 'ReusableMeal',
  'nutrition-target-schedule' => 'NutritionTargetSchedule',
  _ => throw ArgumentError.value(aggregateType, 'aggregateType'),
};
