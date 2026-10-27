import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../../services/local/local_database.dart';
import 'local_sync_store.dart' show newUuidV4;

const dailyCheckInAggregateType = 'daily-check-in';

/// Führt einen lokalen, vom Server nie bestätigten Check-in in den gezogenen
/// Server-Check-in desselben Tages über.
///
/// Der Server erlaubt einen Check-in je Tag. Legt dieses Gerät offline einen
/// Check-in X an und zieht danach den Check-in Y desselben Tages, lehnt der
/// Server X dauerhaft ab und der Eintrag hinge in der Outbox. Stattdessen
/// werden die lokalen Werte zu einer wartenden Änderung auf Y mit der
/// Serverversion als Basis; X verschwindet samt Outbox-Einträgen und
/// Konflikten. So bleibt ein wartender Stand je Ressource.
///
/// Läuft in der Transaktion des Pulls. Gibt die neue Hülle für [serverId]
/// zurück oder `null`, wenn es nichts zu übernehmen gibt (dann gilt der
/// Serverstand wie bisher).
Future<LocalAggregateEnvelope<Object?>?> adoptLocalCheckInForDay({
  required LocalDatabase database,
  required String accountId,
  required String serverId,
  required Object? snapshot,
  required int version,
}) async {
  if (snapshot is! Map<String, dynamic>) return null;
  final local = await _unconfirmedCheckInForDay(
    database,
    serverId,
    snapshot['localDate'],
  );
  if (local == null) return null;
  final rows = await _waitingRows(database, accountId, local.aggregateId);
  // Ein Eintrag im Versand wird von seiner Antwort abgeschlossen.
  if (rows.isEmpty ||
      rows.any((row) => row.status == LocalMutationStatus.syncing.name)) {
    return null;
  }
  final merged = _mergedWorkingCopy(snapshot, local.workingCopy);
  await _dropLocalCheckIn(database, accountId, local.aggregateId, rows);
  await database
      .into(database.localOutbox)
      .insert(
        LocalOutboxCompanion.insert(
          // Neue ID: Eine schon gesendete Mutation-ID behält ihren Body.
          mutationId: newUuidV4(),
          accountId: accountId,
          aggregateType: dailyCheckInAggregateType,
          aggregateId: serverId,
          sequence: await _nextSequence(database, accountId, serverId),
          status: LocalMutationStatus.pending.name,
          createdAtUtc: rows.first.createdAtUtc,
          payloadJson: jsonEncode({
            'operation': LocalMutationOperation.update.name,
            'baseVersion': version,
            'body': merged,
          }),
          baseVersion: Value(version),
        ),
      );
  return LocalAggregateEnvelope(
    aggregateId: serverId,
    serverSnapshot: snapshot,
    workingCopy: merged,
    serverVersion: version,
    optimisticVersion: version + 1,
    syncState: LocalSyncState.pending,
  );
}

/// Serverwerte, überschrieben von allen lokal gesetzten Werten. Die
/// Anlagezeit bleibt die des Servers.
Map<String, Object?> _mergedWorkingCopy(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> local,
) => {
  ...snapshot,
  for (final entry in local.entries)
    if (entry.value != null) entry.key: entry.value,
  if (snapshot['createdAtUtc'] != null)
    'createdAtUtc': snapshot['createdAtUtc'],
};

Future<({String aggregateId, Map<String, dynamic> workingCopy})?>
_unconfirmedCheckInForDay(
  LocalDatabase database,
  String serverId,
  Object? localDate,
) async {
  if (localDate is! String) return null;
  final rows =
      await (database.select(database.localResources)..where(
            (t) =>
                t.aggregateType.equals(dailyCheckInAggregateType) &
                t.aggregateId.equals(serverId).not(),
          ))
          .get();
  for (final row in rows) {
    final envelope = LocalAggregateEnvelope<Object?>.fromJson(
      jsonDecode(row.envelopeJson) as Map<String, dynamic>,
    );
    final workingCopy = envelope.workingCopy;
    if (envelope.serverVersion == null &&
        workingCopy is Map<String, dynamic> &&
        workingCopy['localDate'] == localDate) {
      return (aggregateId: row.aggregateId, workingCopy: workingCopy);
    }
  }
  return null;
}

Future<List<LocalOutboxData>> _waitingRows(
  LocalDatabase database,
  String accountId,
  String aggregateId,
) =>
    (database.select(database.localOutbox)
          ..where(
            (t) =>
                t.accountId.equals(accountId) &
                t.aggregateType.equals(dailyCheckInAggregateType) &
                t.aggregateId.equals(aggregateId) &
                t.status.isNotValue(LocalMutationStatus.clean.name),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
        .get();

Future<void> _dropLocalCheckIn(
  LocalDatabase database,
  String accountId,
  String aggregateId,
  List<LocalOutboxData> rows,
) async {
  final mutationIds = [for (final row in rows) row.mutationId];
  await (database.delete(database.localOutbox)..where(
        (t) => t.accountId.equals(accountId) & t.mutationId.isIn(mutationIds),
      ))
      .go();
  await (database.delete(database.localConflicts)..where(
        (t) =>
            t.aggregateType.equals(dailyCheckInAggregateType) &
            t.aggregateId.equals(aggregateId),
      ))
      .go();
  await (database.delete(database.localResources)..where(
        (t) =>
            t.aggregateType.equals(dailyCheckInAggregateType) &
            t.aggregateId.equals(aggregateId),
      ))
      .go();
}

Future<int> _nextSequence(
  LocalDatabase database,
  String accountId,
  String aggregateId,
) async {
  final rows =
      await (database.select(database.localOutbox)..where(
            (t) =>
                t.accountId.equals(accountId) &
                t.aggregateType.equals(dailyCheckInAggregateType) &
                t.aggregateId.equals(aggregateId),
          ))
          .get();
  return rows.fold<int>(
        0,
        (max, row) => row.sequence > max ? row.sequence : max,
      ) +
      1;
}
