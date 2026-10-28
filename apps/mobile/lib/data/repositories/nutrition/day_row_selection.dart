import '../../models/local/local_aggregate.dart';

/// Lokales Datum der Tageszeile; null, wenn die Zeile keines trägt.
String? dayRowDate(LocalAggregateEnvelope<Object?> row) {
  final working = row.workingCopy;
  if (working is! Map) return null;
  final date = working['localDate'];
  return date is String ? date : null;
}

/// Zeile von [localDate] aus [rows]. Eine vom Server bestätigte Zeile geht
/// vor: Übernahm der Pull einen lokalen Tag nicht, gehen Lesen und Ändern an
/// die Serverzeile statt an die abgelehnte Anlage. Danach gilt [preferred],
/// zuletzt die erste Zeile.
LocalAggregateEnvelope<Object?>? pickDayRow(
  Iterable<LocalAggregateEnvelope<Object?>> rows,
  String localDate, {
  bool Function(LocalAggregateEnvelope<Object?> row)? preferred,
}) {
  final days = rows.where((row) => dayRowDate(row) == localDate).toList();
  return days.where((row) => row.serverVersion != null).firstOrNull ??
      (preferred == null ? null : days.where(preferred).firstOrNull) ??
      days.firstOrNull;
}

/// Je lokalem Datum genau eine Zeile (bestätigte zuerst), in der Reihenfolge
/// des ersten Auftretens. Zeilen ohne Datum bleiben unverändert erhalten.
List<LocalAggregateEnvelope<Object?>> onePerLocalDate(
  Iterable<LocalAggregateEnvelope<Object?>> rows,
) {
  final undated = <LocalAggregateEnvelope<Object?>>[];
  final byDate = <String, LocalAggregateEnvelope<Object?>>{};
  for (final row in rows) {
    final date = dayRowDate(row);
    if (date == null) {
      undated.add(row);
      continue;
    }
    final kept = byDate[date];
    if (kept == null ||
        (kept.serverVersion == null && row.serverVersion != null)) {
      byDate[date] = row;
    }
  }
  return [...byDate.values, ...undated];
}
