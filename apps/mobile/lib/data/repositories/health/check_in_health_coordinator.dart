import 'package:flutter/foundation.dart';

import '../../services/platform/platform_ports.dart';

/// Health-Werte für einen Check-in-Tag. Leere Werte heißen „keine Daten oder
/// kein Zugriff“; HealthKit verrät keine Lese-Berechtigung.
class CheckInHealthSnapshot {
  const CheckInHealthSnapshot({
    this.weightKg,
    this.weightChecked = false,
    this.hasForeignWeight = false,
    this.steps,
    this.sleep,
    this.sleepChecked = false,
  });

  static const empty = CheckInHealthSnapshot();

  /// Jüngster Gewichtswert des Tages (beliebige Quelle).
  final double? weightKg;

  /// Das Lesen des Gewichts war erfolgreich; nur dann wird später geschrieben.
  final bool weightChecked;

  /// Für den Tag liegt eine Probe einer anderen Quelle als Gainer vor.
  final bool hasForeignWeight;

  final int? steps;
  final HealthSleepWindow? sleep;
  final bool sleepChecked;

  bool get hasForeignSleep => sleep != null && !sleep!.fromGainer;
}

/// Liest Gewicht, Schritte und Schlaf für den Check-in und schreibt Gewicht und
/// Schlaf nach Apple Health zurück. Fehler blockieren nie das Speichern.
class CheckInHealthCoordinator {
  CheckInHealthCoordinator({
    required this.platform,
    required this.accountId,
    DateTime Function()? clock,
    void Function(Object error)? onError,
  }) : _clock = clock ?? DateTime.now,
       _onError = onError ?? _logError;

  final HealthPlatform platform;
  final String accountId;
  final DateTime Function() _clock;
  final void Function(Object error) _onError;

  /// Tag: lokale Mitternacht bis Mitternacht, heute höchstens bis jetzt.
  /// HealthKit lehnt ein Ende in der Zukunft ab.
  ({DateTime from, DateTime to})? dayWindow(String localDate) {
    final day = DateTime.parse(localDate);
    return _capped(
      DateTime(day.year, day.month, day.day),
      DateTime(day.year, day.month, day.day + 1),
    );
  }

  /// Nacht zum Check-in-Tag: 18:00 des Vortags bis 14:00 des Tags (lokal).
  ({DateTime from, DateTime to})? nightWindow(String localDate) {
    final day = DateTime.parse(localDate);
    return _capped(
      DateTime(day.year, day.month, day.day - 1, 18),
      DateTime(day.year, day.month, day.day, 14),
    );
  }

  ({DateTime from, DateTime to})? _capped(DateTime from, DateTime to) {
    final now = _clock();
    final end = to.isAfter(now) ? now : to;
    if (!end.isAfter(from)) return null;
    return (from: from.toUtc(), to: end.toUtc());
  }

  /// Fragt die Berechtigung an und liest die Tageswerte; wirft nie.
  Future<CheckInHealthSnapshot> load(String localDate) async {
    try {
      if (!await platform.isAvailable()) return CheckInHealthSnapshot.empty;
      await platform.requestCheckInAuthorization();
    } catch (error) {
      _onError(error);
      return CheckInHealthSnapshot.empty;
    }
    final day = dayWindow(localDate);
    final night = nightWindow(localDate);

    double? weight;
    var weightChecked = false;
    var foreignWeight = false;
    int? steps;
    HealthSleepWindow? sleep;
    var sleepChecked = false;

    if (day != null) {
      try {
        final samples = [
          for (final sample in await platform.readBodyMassSamples(
            fromUtc: day.from,
            toUtc: day.to,
          ))
            if (sample.weightKilograms.isFinite &&
                sample.weightKilograms > 0 &&
                !sample.measuredAtUtc.isBefore(day.from) &&
                sample.measuredAtUtc.isBefore(day.to))
              sample,
        ]..sort((a, b) => a.measuredAtUtc.compareTo(b.measuredAtUtc));
        weightChecked = true;
        foreignWeight = samples.any((sample) => !sample.isFromGainer);
        weight = samples.isEmpty ? null : samples.last.weightKilograms;
      } catch (error) {
        _onError(error);
      }
      try {
        final count = await platform.readStepCount(
          fromUtc: day.from,
          toUtc: day.to,
        );
        steps = count != null && count > 0 ? count : null;
      } catch (error) {
        _onError(error);
      }
    }
    if (night != null) {
      try {
        final window = await platform.readSleep(
          fromUtc: night.from,
          toUtc: night.to,
        );
        sleepChecked = true;
        sleep = window != null && window.wakeUtc.isAfter(window.bedtimeUtc)
            ? window
            : null;
      } catch (error) {
        _onError(error);
      }
    }
    return CheckInHealthSnapshot(
      weightKg: weight,
      weightChecked: weightChecked,
      hasForeignWeight: foreignWeight,
      steps: steps,
      sleep: sleep,
      sleepChecked: sleepChecked,
    );
  }

  /// Schreibt Gewicht und Schlaf nach Health, sofern keine fremde Probe
  /// vorliegt. Fehler und fehlende Berechtigung werden nur protokolliert.
  Future<void> writeBack({
    required String localDate,
    required CheckInHealthSnapshot snapshot,
    required double weightKg,
    DateTime? bedtime,
    DateTime? wake,
  }) async {
    final now = _clock();
    if (snapshot.weightChecked &&
        !snapshot.hasForeignWeight &&
        weightKg.isFinite &&
        weightKg > 0) {
      final day = DateTime.parse(localDate);
      final isToday =
          day.year == now.year && day.month == now.month && day.day == now.day;
      // Heute zählt der Speicherzeitpunkt, frühere Tage mittags.
      final measuredAt = isToday
          ? now
          : DateTime(day.year, day.month, day.day, 12);
      try {
        await platform.writeBodyMass(
          kilograms: weightKg,
          measuredAtUtc: measuredAt.toUtc(),
          syncIdentifier: _syncIdentifier(localDate, 'weight'),
        );
      } catch (error) {
        _onError(error);
      }
    }
    if (snapshot.sleepChecked &&
        !snapshot.hasForeignSleep &&
        bedtime != null &&
        wake != null &&
        wake.isAfter(bedtime) &&
        !wake.isAfter(now)) {
      try {
        await platform.writeSleep(
          bedtimeUtc: bedtime.toUtc(),
          wakeUtc: wake.toUtc(),
          syncIdentifier: _syncIdentifier(localDate, 'sleep'),
        );
      } catch (error) {
        _onError(error);
      }
    }
  }

  String _syncIdentifier(String localDate, String kind) =>
      '$checkInSyncPrefix$accountId-$localDate-$kind';

  static void _logError(Object error) =>
      debugPrint('Apple Health (Check-in): $error');
}
