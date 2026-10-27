import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../domain/models/nutrition/nutrition.dart';
import '../../../domain/models/nutrition/water_intake.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../../services/local/local_database.dart';
import 'local_conflict_recovery.dart' show waterIntakeAggregateType;
import 'local_sync_store.dart' show newUuidV4;

const dailyCheckInAggregateType = 'daily-check-in';
const nutritionDayAggregateType = 'nutrition-day';

/// Zusammengeführter Arbeitsstand oder `null`, wenn er ungültig wäre.
typedef _DayMerge = Map<String, Object?>? Function(
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
  if (merged == null) return null;
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
/// angelegten folgen je Mahlzeit dahinter ([NutritionDay.replace]). Der
/// lokale Tag begann leer, alle seine Einträge sind also neu. Wäre der
/// zusammengeführte Tag ungültig (z. B. mehr als 200 Einträge), gibt es
/// nichts zu übernehmen (`null`); der lokale Eintrag bleibt als Konflikt.
Map<String, Object?>? _mergedNutritionDay(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> local,
) {
  try {
    var day = NutritionDay.fromJson(snapshot);
    final known = {for (final entry in day.entries) entry.entryId};
    for (final entry in NutritionDay.fromJson(local).entries) {
      if (!known.contains(entry.entryId)) day = day.replace(entry);
    }
    return {
      ..._mergedWorkingCopy(snapshot, local),
      'entries': day.toJson()['entries'],
    };
  } on NutritionValidationException {
    return null;
  } on FormatException {
    return null;
  }
}

/// Lokaler, nie gesendeter Merker der Wassermenge: Der Tag wurde mit
/// „Menge setzen“ geändert, seine Menge ist also eine absolute Tagessumme
/// und keine Summe von Zugaben ab 0 ml.
const waterAmountSetLocallyKey = 'amountSetLocally';

/// Wie [_mergedWorkingCopy]. Hat der lokale Tag nur Zugaben gesammelt, kommt
/// seine Menge zur Servermenge hinzu, weil er bei 0 ml begann. Wurde die
/// Menge lokal gesetzt, gilt sie als absolute Tagessumme.
Map<String, Object?> _mergedWaterDay(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> local,
) {
  final localAmount = _amount(local['amountMl']);
  return {
    ...(_mergedWorkingCopy(snapshot, local)..remove(waterAmountSetLocallyKey)),
    'amountMl': local[waterAmountSetLocallyKey] == true
        ? localAmount
        : math.min(
            _amount(snapshot['amountMl']) + localAmount,
            WaterIntakeLimits.maxDailyMl,
          ),
  };
}

int _amount(Object? value) => value is num ? value.toInt() : 0;

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
