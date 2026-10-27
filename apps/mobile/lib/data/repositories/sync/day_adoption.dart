import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../domain/models/nutrition/water_intake.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../../services/local/local_database.dart';
import 'local_conflict_recovery.dart' show waterIntakeAggregateType;
import 'local_sync_store.dart' show newUuidV4;

const dailyCheckInAggregateType = 'daily-check-in';
const nutritionDayAggregateType = 'nutrition-day';

typedef _DayMerge = Map<String, Object?> Function(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> local,
);

/// Aggregate, von denen der Server je Tag (`localDate`) nur eines erlaubt,
/// und wie die lokalen Werte in den gezogenen Serverstand eingehen.
const Map<String, _DayMerge> _dayMerges = {
  dailyCheckInAggregateType: _mergedWorkingCopy,
  nutritionDayAggregateType: _mergedNutritionDay,
  waterIntakeAggregateType: _mergedWaterDay,
};

/// True, wenn der Server für [aggregateType] ein Aggregat je Tag erlaubt und
/// [adoptLocalDay] einen lokalen Tag übernehmen kann.
bool isDayAggregateType(String aggregateType) =>
    _dayMerges.containsKey(aggregateType);

/// Führt einen lokalen, vom Server nie bestätigten Tag (Check-in,
/// Ernährungstag, Wassertag) in den gezogenen Servertag desselben Datums über.
///
/// Der Server erlaubt ein Aggregat je Tag. Legt dieses Gerät offline den Tag
/// X an und zieht danach den Tag Y desselben Datums, lehnt der Server X
/// dauerhaft ab und der Eintrag hinge in der Outbox. Stattdessen werden die
/// lokalen Werte zu einer wartenden Änderung auf Y mit der Serverversion als
/// Basis; X verschwindet samt Outbox-Einträgen und Konflikten. So bleibt ein
/// wartender Stand je Ressource.
///
/// Läuft in der Transaktion des Pulls. Gibt die neue Hülle für [serverId]
/// zurück oder `null`, wenn es nichts zu übernehmen gibt (dann gilt der
/// Serverstand wie bisher).
Future<LocalAggregateEnvelope<Object?>?> adoptLocalDay({
  required LocalDatabase database,
  required String accountId,
  required String aggregateType,
  required String serverId,
  required Object? snapshot,
  required int version,
}) async {
  final merge = _dayMerges[aggregateType];
  if (merge == null || snapshot is! Map<String, dynamic>) return null;
  final local = await _unconfirmedDay(
    database,
    aggregateType,
    serverId,
    snapshot['localDate'],
  );
  if (local == null) return null;
  final day = (aggregateType: aggregateType, accountId: accountId);
  final rows = await _waitingRows(database, day, local.aggregateId);
  // Ein Eintrag im Versand wird von seiner Antwort abgeschlossen.
  if (rows.isEmpty ||
      rows.any((row) => row.status == LocalMutationStatus.syncing.name)) {
    return null;
  }
  final merged = merge(snapshot, local.workingCopy);
  await _dropLocalDay(database, day, local.aggregateId, rows);
  await database
      .into(database.localOutbox)
      .insert(
        LocalOutboxCompanion.insert(
          // Neue ID: Eine schon gesendete Mutation-ID behält ihren Body.
          mutationId: newUuidV4(),
          accountId: accountId,
          aggregateType: aggregateType,
          aggregateId: serverId,
          sequence: await _nextSequence(database, day, serverId),
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

/// Wie [_mergedWorkingCopy]; die Einträge des Servers bleiben, die lokal
/// angelegten folgen je Mahlzeit dahinter. Der lokale Tag begann leer, alle
/// seine Einträge sind also neu.
Map<String, Object?> _mergedNutritionDay(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> local,
) {
  final server = _entryMaps(snapshot['entries']);
  final known = {for (final entry in server) entry['entryId']};
  final nextPosition = <Object?, int>{};
  for (final entry in server) {
    nextPosition[entry['meal']] = math.max(
      nextPosition[entry['meal']] ?? 0,
      _position(entry) + 1,
    );
  }
  final added = [
    for (final entry in _entryMaps(local['entries']))
      if (!known.contains(entry['entryId']))
        {...entry, 'position': _take(nextPosition, entry['meal'])},
  ];
  return {
    ..._mergedWorkingCopy(snapshot, local),
    'entries': [...server, ...added],
  };
}

/// Wie [_mergedWorkingCopy]; die lokale Menge kommt zur Servermenge hinzu,
/// weil der lokale Tag bei 0 ml begann.
Map<String, Object?> _mergedWaterDay(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> local,
) => {
  ..._mergedWorkingCopy(snapshot, local),
  'amountMl': math.min(
    _amount(snapshot['amountMl']) + _amount(local['amountMl']),
    WaterIntakeLimits.maxDailyMl,
  ),
};

List<Map<String, dynamic>> _entryMaps(Object? entries) => [
  if (entries is List)
    for (final entry in entries)
      if (entry is Map<String, dynamic>) entry,
];

int _position(Map<String, dynamic> entry) {
  final value = entry['position'];
  return value is num ? value.toInt() : 0;
}

int _amount(Object? value) => value is num ? value.toInt() : 0;

/// Nächste freie Position von [meal]; rückt sie danach weiter.
int _take(Map<Object?, int> nextPosition, Object? meal) {
  final position = nextPosition[meal] ?? 0;
  nextPosition[meal] = position + 1;
  return position;
}

typedef _Day = ({String aggregateType, String accountId});

Future<({String aggregateId, Map<String, dynamic> workingCopy})?>
_unconfirmedDay(
  LocalDatabase database,
  String aggregateType,
  String serverId,
  Object? localDate,
) async {
  if (localDate is! String) return null;
  final rows =
      await (database.select(database.localResources)..where(
            (t) =>
                t.aggregateType.equals(aggregateType) &
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
  _Day day,
  String aggregateId,
) =>
    (database.select(database.localOutbox)
          ..where(
            (t) =>
                t.accountId.equals(day.accountId) &
                t.aggregateType.equals(day.aggregateType) &
                t.aggregateId.equals(aggregateId) &
                t.status.isNotValue(LocalMutationStatus.clean.name),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
        .get();

Future<void> _dropLocalDay(
  LocalDatabase database,
  _Day day,
  String aggregateId,
  List<LocalOutboxData> rows,
) async {
  final mutationIds = [for (final row in rows) row.mutationId];
  await (database.delete(database.localOutbox)..where(
        (t) =>
            t.accountId.equals(day.accountId) & t.mutationId.isIn(mutationIds),
      ))
      .go();
  await (database.delete(database.localConflicts)..where(
        (t) =>
            t.aggregateType.equals(day.aggregateType) &
            t.aggregateId.equals(aggregateId),
      ))
      .go();
  await (database.delete(database.localResources)..where(
        (t) =>
            t.aggregateType.equals(day.aggregateType) &
            t.aggregateId.equals(aggregateId),
      ))
      .go();
}

Future<int> _nextSequence(
  LocalDatabase database,
  _Day day,
  String aggregateId,
) async {
  final rows =
      await (database.select(database.localOutbox)..where(
            (t) =>
                t.accountId.equals(day.accountId) &
                t.aggregateType.equals(day.aggregateType) &
                t.aggregateId.equals(aggregateId),
          ))
          .get();
  return rows.fold<int>(
        0,
        (max, row) => row.sequence > max ? row.sequence : max,
      ) +
      1;
}
