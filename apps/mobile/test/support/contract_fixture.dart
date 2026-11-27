import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/training_statistics.dart';

/// Gemeinsame Vertrags-Fixtures für App und Backend unter `contracts/fixtures`.
/// Der Pfad ist relativ zum Paketverzeichnis `apps/mobile`.
List<Map<String, Object?>> loadFixtureCases(String fileName) {
  final fixture = jsonDecode(
    File('../../contracts/fixtures/$fileName').readAsStringSync(),
  ) as Map<String, Object?>;
  return [
    for (final item in fixture['cases']! as List<Object?>)
      item! as Map<String, Object?>,
  ];
}

List<Object?> fixtureList(Object? value) =>
    value == null ? const [] : value as List<Object?>;

/// Vergleicht auf zwei Nachkommastellen gerundet; `null` muss exakt passen.
void expectFixtureNumber(num? actual, Object? expected, String label) {
  if (expected == null) {
    expect(actual, isNull, reason: label);
    return;
  }
  expect(actual, isNotNull, reason: label);
  expect(
    roundToTwoDecimals(actual!.toDouble()),
    closeTo((expected as num).toDouble(), 1e-9),
    reason: label,
  );
}

/// Kalendertag in Europe/Berlin (Sommerzeit vom letzten Sonntag im März bis
/// zum letzten Sonntag im Oktober, je 01:00 UTC), unabhängig von der
/// Zeitzone des Testrechners.
LocalDay berlinDayOf(DateTime instant) {
  final utc = instant.toUtc();
  final summerTime =
      !utc.isBefore(_lastSundayAt1Utc(utc.year, 3)) &&
      utc.isBefore(_lastSundayAt1Utc(utc.year, 10));
  final local = utc.add(Duration(hours: summerTime ? 2 : 1));
  return LocalDay(local.year, local.month, local.day);
}

DateTime _lastSundayAt1Utc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  final sunday = lastDay.subtract(Duration(days: lastDay.weekday % 7));
  return sunday.add(const Duration(hours: 1));
}
