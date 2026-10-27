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
  ///
  /// Hat der Server die Ressource gelöscht oder nach einer dauerhaften
  /// Ablehnung nie gekannt, ist sein Stand „nicht vorhanden“: Die Ressource
  /// wird lokal verworfen. Ressourcen, die eine verworfene Zusammenführung
  /// oder Umsortierung lokal mitgeändert hat, gehen ebenfalls auf den
  /// Serverstand zurück.
  Future<void> acceptConflictServerState(String conflictId) async {
    await ensureAccountBound();
    await database.transaction(() async {
      final state = await _conflictState(conflictId);
      final info = state.info;
      if (!info.hasServerState) {
        throw StateError('No retained server state is available.');
      }
      final type = state.conflict.aggregateType;
      final id = state.conflict.aggregateId;
      await _resetSpannedResources(state.rows);
      await _redirectDependencies(state.rows, null);
      if (info.serverDeleted || info.discardsLocal) {
        await _deleteLocalResource(type, id);
        return;
      }
      final envelope = state.envelope!;
      final accepted = serverEnvelope(
        aggregateId: envelope.aggregateId,
        snapshot: envelope.serverSnapshot,
        version: envelope.serverVersion!,
      );
      await (database.update(database.localResources)..where(
            (t) => t.aggregateType.equals(type) & t.aggregateId.equals(id),
          ))
          .write(
            LocalResourcesCompanion(envelopeJson: Value(accepted.encode())),
          );
      await _deleteQueueAndConflicts(type, id);
    });
  }

  /// Explicitly reapplies a local operation against the retained current
  /// server version with a fresh idempotency key. Tombstones are never revived.
  /// The replacement keeps the queue position of the rejected row. All later
  /// rows of the resource return to the queue behind it; their base follows
  /// once the server confirms the replacement.
  Future<String> retryConflictOnCurrentServerVersion({
    required String conflictId,
    required String replacementMutationId,
  }) async {
    await ensureAccountBound();
    if (!RegExp(LocalDatabase.accountIdPattern)
        .hasMatch(replacementMutationId)) {
      throw ArgumentError.value(replacementMutationId, 'replacementMutationId');
    }
    return database.transaction(() async {
      final state = await _conflictState(conflictId);
      if (!state.info.canRetry) {
        throw StateError('This conflict cannot be retried.');
      }
      final conflict = state.conflict;
      final envelope = state.envelope!;
      final old = state.rows.first;
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
              // Wie bei [_requeueLocalState]: Zeitstempel der ersetzten Zeile,
              // damit der Ersatz vor späteren Einträgen der Ressource bleibt.
              createdAtUtc: old.createdAtUtc,
              payloadJson: jsonEncode(payload),
              baseVersion: Value(envelope.serverVersion),
              // Keine Abhängigkeit auf die abgelehnte Mutation: Der Server
              // verarbeitet sie nie und lehnte den Ersatz sonst mit
              // `dependency_not_applied` ab.
            ),
          );
      // Ein fremder Batch hält alle wartenden Zeilen an. Blieben die späteren
      // im Konflikt, würden sie nie gesendet und blockierten die Ressource.
      for (final row in state.rows.skip(1)) {
        if (row.status != LocalMutationStatus.conflict.name) continue;
        await (database.update(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.mutationId.equals(row.mutationId),
            ))
            .write(
              LocalOutboxCompanion(
                status: Value(LocalMutationStatus.pending.name),
                lastErrorCode: const Value(null),
                nextAttemptAtUtc: const Value(null),
              ),
            );
      }
      await _redirectDependencies([old], replacementMutationId);
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
      // Alle Zeilen sind wieder in der Warteschlange; kein Konflikt der
      // Ressource bleibt offen.
      await (database.delete(database.localConflicts)..where(
            (t) =>
                t.aggregateType.equals(conflict.aggregateType) &
                t.aggregateId.equals(conflict.aggregateId),
          ))
          .go();
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
      final state = await _conflictState(conflictId);
      if (!state.info.canForceLocal) {
        throw StateError('This conflict cannot be forced.');
      }
      await _requeueLocalState(
        state.conflict.aggregateType,
        state.conflict.aggregateId,
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
      await _redirectDependencies(
        await _outboxRows(aggregateType, aggregateId),
        null,
      );
      await _deleteLocalResource(aggregateType, aggregateId);
    });
  }

  Future<void> _deleteQueueAndConflicts(
    String aggregateType,
    String aggregateId,
  ) async {
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
  }

  /// Spätere Zeilen, die auf eine entfernte Mutation warten, warten auf deren
  /// Ersatz bzw. auf nichts mehr. Der Server verarbeitet die entfernte
  /// Mutation nie und lehnte sie sonst mit `dependency_not_applied` ab.
  Future<void> _redirectDependencies(
    Iterable<LocalOutboxData> removed,
    String? replacementMutationId,
  ) async {
    final ids = [for (final row in removed) row.mutationId];
    if (ids.isEmpty) return;
    await (database.update(database.localOutbox)..where(
          (t) =>
              t.accountId.equals(accountId) & t.dependsOnMutationId.isIn(ids),
        ))
        .write(
          LocalOutboxCompanion(
            dependsOnMutationId: Value(replacementMutationId),
          ),
        );
  }

  /// Zusammenführen und Umsortieren ändern lokal weitere Ressourcen, ohne
  /// für sie eine Outbox-Zeile anzulegen. Wird eine solche Mutation
  /// verworfen, gehen diese Ressourcen auf ihren Serverstand zurück. Hat eine
  /// davon eigene wartende Änderungen, bleibt sie, wie sie ist: Diese
  /// Änderungen senden ihren Stand ohnehin.
  Future<void> _resetSpannedResources(List<LocalOutboxData> discarded) async {
    final candidates = <(String, String)>{};
    for (final row in discarded) {
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      final body = payload['body'];
      if (payload['operation'] == LocalMutationOperation.reorder.name) {
        candidates.addAll(_reorderedPlans(body));
      } else if (payload['operation'] == LocalMutationOperation.merge.name) {
        candidates.addAll(await _mergeCandidates());
      }
    }
    if (candidates.isEmpty) return;
    final queued = {
      for (final row in await (database.select(
        database.localOutbox,
      )..where((t) => t.accountId.equals(accountId))).get())
        if (!discarded.any((gone) => gone.mutationId == row.mutationId))
          (row.aggregateType, row.aggregateId),
    };
    for (final (type, id) in candidates) {
      if (queued.contains((type, id))) continue;
      await _resetToServerState(type, id);
    }
  }

  Iterable<(String, String)> _reorderedPlans(Object? body) {
    final plans = body is Map ? body['plans'] : null;
    return [
      for (final plan in plans is List ? plans : const [])
        if ((plan is Map ? plan['planId'] : null) case final String planId)
          (_trainingPlanType, planId),
    ];
  }

  /// Der Body nennt die umgeschriebenen Trainings und Pläne nicht.
  /// Kandidaten sind alle; zurück gehen nur die ohne eigene Zeile, deren
  /// Stand nur lokal abweicht.
  Future<List<(String, String)>> _mergeCandidates() async {
    final candidates = <(String, String)>[];
    for (final type in const ['workout', _trainingPlanType]) {
      final resources = await (database.select(
        database.localResources,
      )..where((t) => t.aggregateType.equals(type))).get();
      for (final resource in resources) {
        candidates.add((type, resource.aggregateId));
      }
    }
    return candidates;
  }

  Future<void> _resetToServerState(String type, String id) async {
    final resource =
        await (database.select(database.localResources)..where(
              (t) => t.aggregateType.equals(type) & t.aggregateId.equals(id),
            ))
            .getSingleOrNull();
    if (resource == null) return;
    final envelope = LocalAggregateEnvelope<Object?>.fromJson(
      jsonDecode(resource.envelopeJson) as Map<String, dynamic>,
    );
    final version = envelope.serverVersion;
    if (envelope.syncState != LocalSyncState.pending ||
        envelope.serverSnapshot == null ||
        version == null) {
      return;
    }
    final reset = serverEnvelope(
      aggregateId: envelope.aggregateId,
      snapshot: envelope.serverSnapshot,
      version: version,
    );
    await (database.update(database.localResources)..where(
          (t) => t.aggregateType.equals(type) & t.aggregateId.equals(id),
        ))
        .write(LocalResourcesCompanion(envelopeJson: Value(reset.encode())));
  }

  /// Ältere App-Versionen setzten dauerhaft abgelehnte Einträge (422) auf
  /// `failed`, ohne Konflikt. Sie blockierten ihre Ressource unsichtbar und
  /// ließen sich nicht auflösen. Hier werden sie zu dauerhaften Konflikten.
  /// Neuere Versionen setzen `failed` nicht mehr, der Aufruf ist danach leer.
  Future<int> conflictLegacyFailedMutations() async {
    await ensureAccountBound();
    return database.transaction(() async {
      final failed =
          await (database.select(database.localOutbox)..where(
                (t) =>
                    t.accountId.equals(accountId) &
                    t.status.equals(LocalMutationStatus.failed.name),
              ))
              .get();
      final now = DateTime.now().toUtc().toIso8601String();
      for (final row in failed) {
        await database
            .into(database.localConflicts)
            .insertOnConflictUpdate(
              LocalConflictsCompanion.insert(
                conflictId: row.mutationId,
                aggregateType: row.aggregateType,
                aggregateId: row.aggregateId,
                createdAtUtc: now,
                code: row.lastErrorCode ?? 'rejected',
                detailJson: jsonEncode({
                  'mutationId': row.mutationId,
                  permanentRejectionDetailKey: true,
                }),
              ),
            );
        await (database.update(database.localOutbox)..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.mutationId.equals(row.mutationId),
            ))
            .write(
              LocalOutboxCompanion(
                status: Value(LocalMutationStatus.conflict.name),
              ),
            );
      }
      return failed.length;
    });
  }

  Future<void> _deleteLocalResource(
    String aggregateType,
    String aggregateId,
  ) async {
    await _deleteQueueAndConflicts(aggregateType, aggregateId);
    await (database.delete(database.localResources)..where(
          (t) =>
              t.aggregateType.equals(aggregateType) &
              t.aggregateId.equals(aggregateId),
        ))
        .go();
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

    await _deleteQueueAndConflicts(aggregateType, aggregateId);

    if (deleted && serverVersion == null) {
      await _redirectDependencies(rows, null);
      await (database.delete(database.localResources)..where(
            (t) =>
                t.aggregateType.equals(aggregateType) &
                t.aggregateId.equals(aggregateId),
          ))
          .go();
      return;
    }
    await _redirectDependencies(rows, replacementMutationId);

    final LocalMutationOperation operation;
    if (deleted) {
      operation = LocalMutationOperation.delete;
    } else if (serverVersion == null) {
      operation = LocalMutationOperation.create;
    } else {
      operation = LocalMutationOperation.update;
    }
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
    return {
      for (final conflict in conflicts)
        conflict.conflictId: (await _stateOf(conflict)).info,
    };
  }

  Future<_ConflictState> _conflictState(String conflictId) async {
    final conflict = await (database.select(
      database.localConflicts,
    )..where((t) => t.conflictId.equals(conflictId))).getSingleOrNull();
    if (conflict == null) {
      throw StateError('Conflict is no longer available.');
    }
    return _stateOf(conflict);
  }

  /// Einzige Stelle, die entscheidet, welche Aktionen ein Konflikt erlaubt.
  /// Anzeige und Aktionen lesen beide dieses Ergebnis.
  Future<_ConflictState> _stateOf(LocalConflict conflict) async {
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
    final detail = jsonDecode(conflict.detailJson);
    final permanent =
        detail is Map && detail[permanentRejectionDetailKey] == true;
    final serverVersion = envelope?.serverVersion;
    final hasServerCopy =
        envelope?.serverSnapshot != null && serverVersion != null;
    final discardsLocal = permanent && !hasTombstone && serverVersion == null;
    final info = ConflictResourceInfo(
      title: envelope == null
          ? null
          : _resourceTitle(type, envelope.workingCopy),
      hasServerState: hasTombstone || hasServerCopy || discardsLocal,
      discardsLocal: discardsLocal,
      serverDeleted: hasTombstone,
      permanentRejection: permanent,
      canForceLocal:
          !permanent &&
          envelope != null &&
          !hasTombstone &&
          forceableAggregateTypes.contains(type) &&
          !rows.map(_operationOf).any(_spansResources),
      canRetry:
          !permanent &&
          !hasTombstone &&
          serverVersion != null &&
          rows.isNotEmpty &&
          !_retryBlockedCodes.contains(conflict.code),
      firstQueuedAtUtc: rows.isEmpty
          ? null
          : DateTime.parse(rows.first.createdAtUtc).toUtc(),
      firstSequence: rows.isEmpty ? 0 : rows.first.sequence,
    );
    return _ConflictState(conflict, envelope, rows, info);
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

/// Kennzeichen im Konfliktdetail: Der Server lehnt diesen Stand dauerhaft ab
/// (422 und 400 außer `validation_failed`, 413, 415, 403/404 mit fachlichem
/// Code; siehe `SyncRepository._isPermanentRejection`). Erneut senden oder
/// erzwingen scheitert
/// genauso; möglich ist nur der Serverstand bzw. das Verwerfen. Gelesen wird
/// es nur in [LocalConflictRecovery], Ergebnis ist
/// [ConflictResourceInfo.permanentRejection].
const permanentRejectionDetailKey = 'permanent';

/// Erneutes Senden derselben Nutzlast behebt diese Codes nicht; der Nutzer
/// muss die Daten zuerst ändern.
const _retryBlockedCodes = {'active_workout_exists', 'validation_failed'};

class _ConflictState {
  const _ConflictState(this.conflict, this.envelope, this.rows, this.info);

  final LocalConflict conflict;
  final LocalAggregateEnvelope<Object?>? envelope;

  /// Alle Outbox-Zeilen der Ressource, nach Sequenz.
  final List<LocalOutboxData> rows;
  final ConflictResourceInfo info;
}

const _trainingPlanType = 'training-plan';
const _trainingScheduleType = 'training-schedule';
const _customExerciseType = 'custom-exercise';
const _exerciseCategoryType = 'exercise-category';
const _dailyCheckInType = 'daily-check-in';
const _nutritionDayType = 'nutrition-day';
const _cardioSessionType = 'cardio-session';

/// Lokaler Typ der Tagesvorlagen.
const nutritionDayTemplateType = 'nutrition-day-template';

/// Lokaler Typ der Wassermenge eines Tages (Server: `WaterIntakeDay`).
const waterIntakeAggregateType = 'water-intake-day';

/// Aggregattypen, deren Mutationsnutzlast der Arbeitskopie entspricht. Bei
/// Körperzielen (erwartetes aktives Ziel), wiederverwendbaren Mahlzeiten
/// (Archivstatus im Body) und Zielplänen fehlt diese Gleichheit.
const forceableAggregateTypes = {
  'workout',
  _trainingPlanType,
  _trainingScheduleType,
  _customExerciseType,
  _exerciseCategoryType,
  _dailyCheckInType,
  _nutritionDayType,
  nutritionDayTemplateType,
  _cardioSessionType,
  waterIntakeAggregateType,
};

class ConflictResourceInfo {
  const ConflictResourceInfo({
    required this.title,
    required this.hasServerState,
    required this.canForceLocal,
    required this.firstQueuedAtUtc,
    required this.firstSequence,
    this.canRetry = false,
    this.discardsLocal = false,
    this.serverDeleted = false,
    this.permanentRejection = false,
  });

  /// Anzeigename aus der Arbeitskopie, `null` ohne lokale Kopie.
  final String? title;

  /// Serverkopie oder Löschmarke vorhanden, oder der Server kennt die
  /// Ressource nach einer dauerhaften Ablehnung nicht; nur dann ist
  /// „Serverstand nutzen“ möglich (im letzten Fall: [discardsLocal]).
  final bool hasServerState;

  /// Der Server hatte die Ressource nie und lehnt sie dauerhaft ab. „Serverstand
  /// nutzen“ heißt hier „Verwerfen“: Die Ressource verschwindet lokal.
  final bool discardsLocal;

  /// Der Server hat die Ressource gelöscht (Löschmarke).
  final bool serverDeleted;

  /// Der Server lehnt diesen Stand dauerhaft ab; erneut senden und erzwingen
  /// scheitern genauso.
  final bool permanentRejection;
  final bool canForceLocal;

  /// „Lokale Änderung erneut senden“ kann gelingen: Es gibt eine aktuelle
  /// Serverversion, und die Ablehnung hängt nicht an den Daten selbst.
  final bool canRetry;

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
  _dailyCheckInType ||
  _customExerciseType ||
  _exerciseCategoryType ||
  _trainingPlanType ||
  _trainingScheduleType ||
  'workout' ||
  _nutritionDayType ||
  'reusable-meal' ||
  'nutrition-target-schedule' ||
  nutritionDayTemplateType ||
  _cardioSessionType ||
  waterIntakeAggregateType => true,
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
    case _dailyCheckInType || _nutritionDayType || waterIntakeAggregateType:
      return text('localDate');
    case _cardioSessionType:
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
    case _trainingScheduleType:
      return 'Rhythmus';
    default:
      return text('name') ?? text('title');
  }
}

String _serverType(String aggregateType) => switch (aggregateType) {
  'body-goal' => 'BodyGoal',
  _dailyCheckInType => 'DailyCheckIn',
  _customExerciseType => 'CustomExercise',
  _exerciseCategoryType => 'ExerciseCategory',
  _trainingPlanType => 'TrainingPlan',
  _trainingScheduleType => 'TrainingSchedule',
  'workout' => 'Workout',
  _nutritionDayType => 'NutritionDay',
  'reusable-meal' => 'ReusableMeal',
  'nutrition-target-schedule' => 'NutritionTargetSchedule',
  nutritionDayTemplateType => 'NutritionDayTemplate',
  _cardioSessionType => 'CardioSession',
  waterIntakeAggregateType => 'WaterIntakeDay',
  _ => throw ArgumentError.value(aggregateType, 'aggregateType'),
};
