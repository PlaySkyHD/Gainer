import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/models/cardio/cardio_session.dart';
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
      // Resending the same payload cannot fix these; the user must change data first.
      if (const {
        'active_workout_exists',
        'validation_failed',
      }.contains(conflict.code)) {
        throw StateError('This conflict cannot be retried automatically.');
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

  /// Ersetzt alle wartenden Änderungen der Ressource durch genau eine, die den
  /// aktuellen lokalen Stand überträgt (anlegen, speichern oder löschen). Ist
  /// die Ressource lokal gelöscht und dem Server unbekannt, wird nichts
  /// gesendet. Server-Löschmarken werden nie wiederbelebt.
  ///
  /// Die Ersatzzeile behält Zeitstempel und Sequenz der ältesten ersetzten
  /// Zeile, damit die Sendereihenfolge zwischen Ressourcen erhalten bleibt;
  /// [createdAtUtc] gilt nur, wenn keine Zeile mehr vorhanden ist.
  Future<void> forceLocalState({
    required String conflictId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  }) async {
    await ensureAccountBound();
    if (!RegExp(LocalDatabase.accountIdPattern)
        .hasMatch(replacementMutationId)) {
      throw ArgumentError.value(replacementMutationId, 'replacementMutationId');
    }
    await database.transaction(() async {
      final conflict = await (database.select(
        database.localConflicts,
      )..where((t) => t.conflictId.equals(conflictId))).getSingleOrNull();
      if (conflict == null) {
        throw StateError('Conflict is no longer available.');
      }
      await _requeueLocalState(
        conflict.aggregateType,
        conflict.aggregateId,
        replacementMutationId,
        createdAtUtc,
      );
    });
  }

  /// Wie [forceLocalState], aber ohne Konfliktdatensatz: Selbstheilung nach
  /// einer Ablehnung, die der Push eindeutig auflösen kann.
  Future<void> requeueLocalState({
    required String aggregateType,
    required String aggregateId,
    required String replacementMutationId,
    required DateTime createdAtUtc,
  }) async {
    await ensureAccountBound();
    if (!RegExp(LocalDatabase.accountIdPattern)
        .hasMatch(replacementMutationId)) {
      throw ArgumentError.value(replacementMutationId, 'replacementMutationId');
    }
    await database.transaction(
      () => _requeueLocalState(
        aggregateType,
        aggregateId,
        replacementMutationId,
        createdAtUtc,
      ),
    );
  }

  /// Ressource lokal gelöscht und dem Server unbekannt: Outbox, Ressource und
  /// Konflikte entfernen, es gibt nichts zu senden.
  Future<void> discardLocalResource(
    String aggregateType,
    String aggregateId,
  ) async {
    await ensureAccountBound();
    await database.transaction(() async {
      await (database.delete(database.localOutbox)..where(
            (t) =>
                t.accountId.equals(accountId) &
                t.aggregateType.equals(aggregateType) &
                t.aggregateId.equals(aggregateId),
          ))
          .go();
      await (database.delete(database.localConflicts)..where(
            (t) =>
                t.aggregateType.equals(aggregateType) &
                t.aggregateId.equals(aggregateId),
          ))
          .go();
      await (database.delete(database.localResources)..where(
            (t) =>
                t.aggregateType.equals(aggregateType) &
                t.aggregateId.equals(aggregateId),
          ))
          .go();
    });
  }

  Future<void> _requeueLocalState(
    String aggregateType,
    String aggregateId,
    String replacementMutationId,
    DateTime createdAtUtc,
  ) async {
    if (!forceableAggregateTypes.contains(aggregateType)) {
      throw StateError('This resource type cannot be forced.');
    }
    final tombstone =
        await (database.select(database.localTombstones)..where(
              (t) =>
                  t.resourceType.equals(_serverType(aggregateType)) &
                  t.resourceId.equals(aggregateId),
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
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(aggregateId),
            ))
            .getSingleOrNull();
    if (resource == null) {
      throw StateError('Local conflict copy is unavailable.');
    }
    final envelope = LocalAggregateEnvelope<Object?>.fromJson(
      jsonDecode(resource.envelopeJson) as Map<String, dynamic>,
    );
    final rows = await _outboxRows(aggregateType, aggregateId);
    final operations = [for (final row in rows) _operationOf(row)];
    if (operations.any(_spansResources)) {
      throw StateError('This mutation spans several resources.');
    }
    final workingCopy = envelope.workingCopy;
    final deleted =
        operations.lastOrNull == LocalMutationOperation.delete.name ||
        (workingCopy is Map && workingCopy['deletedAtUtc'] != null);
    final serverVersion = envelope.serverVersion;

    await (database.delete(database.localOutbox)..where(
          (t) =>
              t.accountId.equals(accountId) &
              t.aggregateType.equals(aggregateType) &
              t.aggregateId.equals(aggregateId),
        ))
        .go();
    await (database.delete(database.localConflicts)..where(
          (t) =>
              t.aggregateType.equals(aggregateType) &
              t.aggregateId.equals(aggregateId),
        ))
        .go();

    if (deleted && serverVersion == null) {
      await (database.delete(database.localResources)..where(
            (t) =>
                t.aggregateType.equals(aggregateType) &
                t.aggregateId.equals(aggregateId),
          ))
          .go();
      return;
    }

    final operation = deleted
        ? LocalMutationOperation.delete
        : serverVersion == null
        ? LocalMutationOperation.create
        : LocalMutationOperation.update;
    final baseVersion = serverVersion ?? 0;
    await database
        .into(database.localOutbox)
        .insert(
          LocalOutboxCompanion.insert(
            mutationId: replacementMutationId,
            accountId: accountId,
            aggregateType: aggregateType,
            aggregateId: aggregateId,
            sequence: rows.isEmpty ? 1 : rows.first.sequence,
            status: LocalMutationStatus.pending.name,
            createdAtUtc: rows.isEmpty
                ? createdAtUtc.toUtc().toIso8601String()
                : rows.first.createdAtUtc,
            payloadJson: jsonEncode({
              'operation': operation.name,
              'baseVersion': baseVersion,
              'body': workingCopy,
            }),
            baseVersion: Value(baseVersion),
          ),
        );
    final pending = LocalAggregateEnvelope(
      aggregateId: envelope.aggregateId,
      serverSnapshot: envelope.serverSnapshot,
      workingCopy: workingCopy,
      serverVersion: serverVersion,
      optimisticVersion: envelope.optimisticVersion,
      syncState: LocalSyncState.pending,
    );
    await (database.update(database.localResources)..where(
          (t) =>
              t.aggregateType.equals(aggregateType) &
              t.aggregateId.equals(aggregateId),
        ))
        .write(LocalResourcesCompanion(envelopeJson: Value(pending.encode())));
  }

  /// Anzeige- und Aktionsdaten je Konflikt, ohne den Zustand zu verändern.
  Future<Map<String, ConflictResourceInfo>> readConflictResourceInfos() async {
    await ensureAccountBound();
    final conflicts = await database.select(database.localConflicts).get();
    final result = <String, ConflictResourceInfo>{};
    for (final conflict in conflicts) {
      final type = conflict.aggregateType;
      final resource =
          await (database.select(database.localResources)..where(
                (t) =>
                    t.aggregateType.equals(type) &
                    t.aggregateId.equals(conflict.aggregateId),
              ))
              .getSingleOrNull();
      final envelope = resource == null
          ? null
          : LocalAggregateEnvelope<Object?>.fromJson(
              jsonDecode(resource.envelopeJson) as Map<String, dynamic>,
            );
      final hasTombstone = _hasServerType(type)
          ? await (database.select(database.localTombstones)..where(
                      (t) =>
                          t.resourceType.equals(_serverType(type)) &
                          t.resourceId.equals(conflict.aggregateId),
                    ))
                    .getSingleOrNull() !=
                null
          : false;
      final rows = await _outboxRows(type, conflict.aggregateId);
      result[conflict.conflictId] = ConflictResourceInfo(
        title: envelope == null
            ? null
            : _resourceTitle(type, envelope.workingCopy),
        hasServerState:
            hasTombstone ||
            (envelope?.serverSnapshot != null &&
                envelope?.serverVersion != null),
        canForceLocal:
            envelope != null &&
            !hasTombstone &&
            forceableAggregateTypes.contains(type) &&
            !rows.map(_operationOf).any(_spansResources),
        firstQueuedAtUtc: rows.isEmpty
            ? null
            : DateTime.parse(rows.first.createdAtUtc).toUtc(),
        firstSequence: rows.isEmpty ? 0 : rows.first.sequence,
      );
    }
    return result;
  }

  Future<List<LocalOutboxData>> _outboxRows(
    String aggregateType,
    String aggregateId,
  ) =>
      (database.select(database.localOutbox)
            ..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.aggregateType.equals(aggregateType) &
                  t.aggregateId.equals(aggregateId),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
          .get();
}

/// Aggregattypen, deren Mutationsnutzlast der Arbeitskopie entspricht. Bei
/// Körperzielen (erwartetes aktives Ziel), wiederverwendbaren Mahlzeiten
/// (Archivstatus im Body) und Zielplänen fehlt diese Gleichheit.
const forceableAggregateTypes = {
  'workout',
  'training-plan',
  'training-schedule',
  'custom-exercise',
  'exercise-category',
  'daily-check-in',
  'nutrition-day',
  'nutrition-day-template',
  'cardio-session',
};

class ConflictResourceInfo {
  const ConflictResourceInfo({
    required this.title,
    required this.hasServerState,
    required this.canForceLocal,
    required this.firstQueuedAtUtc,
    required this.firstSequence,
  });

  /// Anzeigename aus der Arbeitskopie, `null` ohne lokale Kopie.
  final String? title;

  /// Serverkopie oder Löschmarke vorhanden; nur dann ist „Serverstand nutzen“
  /// möglich.
  final bool hasServerState;
  final bool canForceLocal;

  /// Alter und Sequenz der ersten wartenden Änderung (Sendereihenfolge).
  final DateTime? firstQueuedAtUtc;
  final int firstSequence;
}

Object? _operationOf(LocalOutboxData row) =>
    (jsonDecode(row.payloadJson) as Map<String, dynamic>)['operation'];

/// Zusammenführen und Umsortieren betreffen mehrere Ressourcen und lassen sich
/// nicht aus der Arbeitskopie einer einzelnen Ressource ableiten.
bool _spansResources(Object? operation) =>
    operation == LocalMutationOperation.merge.name ||
    operation == LocalMutationOperation.reorder.name;

bool _hasServerType(String aggregateType) => switch (aggregateType) {
  'body-goal' ||
  'daily-check-in' ||
  'custom-exercise' ||
  'exercise-category' ||
  'training-plan' ||
  'training-schedule' ||
  'workout' ||
  'nutrition-day' ||
  'reusable-meal' ||
  'nutrition-target-schedule' ||
  'nutrition-day-template' ||
  'cardio-session' => true,
  _ => false,
};

String? _resourceTitle(String aggregateType, Object? workingCopy) {
  if (workingCopy is! Map) return null;
  String? text(String key) {
    final value = workingCopy[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  switch (aggregateType) {
    case 'workout':
      final title = text('title');
      final started = DateTime.tryParse(text('startedAtUtc') ?? '')?.toLocal();
      final date = started == null
          ? null
          : '${started.day.toString().padLeft(2, '0')}.'
                '${started.month.toString().padLeft(2, '0')}.${started.year}';
      final parts = [?title, ?date];
      return parts.isEmpty ? null : parts.join(' · ');
    case 'daily-check-in' || 'nutrition-day':
      return text('localDate');
    case 'cardio-session':
      final started = DateTime.tryParse(text('startedAtUtc') ?? '')?.toLocal();
      final label = CardioActivityType.values
          .where((type) => type.wireName == text('activityType'))
          .firstOrNull
          ?.label;
      final date = started == null
          ? null
          : '${started.day.toString().padLeft(2, '0')}.'
                '${started.month.toString().padLeft(2, '0')}.${started.year}';
      final parts = [?label, ?date];
      return parts.isEmpty ? null : parts.join(' · ');
    case 'training-schedule':
      return 'Rhythmus';
    default:
      return text('name') ?? text('title');
  }
}

String _serverType(String aggregateType) => switch (aggregateType) {
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
  _ => throw ArgumentError.value(aggregateType, 'aggregateType'),
};
