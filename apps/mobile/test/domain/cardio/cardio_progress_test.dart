import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_draft.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_progress.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_zones.dart';
import 'package:gainer_mobile/domain/models/cardio/resting_measurement.dart';

const _zone = CardioTargetZone(lowBpm: 120, highBpm: 140);

var _counter = 0;

/// Einheit mit [inZoneMinutes] im Zielbereich und dem Rest unter dem Bereich.
CardioSession session(
  DateTime startLocal, {
  required int lengthMinutes,
  int? inZoneMinutes,
  int bpm = 130,
  double? power,
  int? recoveryStart,
  int? recoveryEnd,
}) {
  final total = lengthMinutes * 12;
  final inZone = (inZoneMinutes ?? lengthMinutes) * 12;
  final start = startLocal.toUtc();
  return CardioSession(
    sessionId:
        '00000000-0000-4000-8000-${(++_counter).toString().padLeft(12, '0')}',
    startedAtUtc: start,
    endedAtUtc: start.add(Duration(minutes: lengthMinutes)),
    targetZone: _zone,
    heartRateBpm: [for (var i = 0; i < total; i++) i < inZone ? bpm : 100],
    rrIntervalsMs: const [],
    averagePowerWatts: power,
    recoveryStartBpm: recoveryStart,
    recoveryEndBpm: recoveryEnd,
    createdAtUtc: start,
    updatedAtUtc: start,
  );
}

void main() {
  // Mittwoch, 21.10.2026, lokal.
  final now = DateTime(2026, 10, 21, 12);

  group('CardioProgress Wochen', () {
    test('Spec: 95 / 150 min, 3 Einheiten, 1:42 h', () {
      final progress = CardioProgress.compute([
        session(
          DateTime(2026, 10, 19, 8),
          lengthMinutes: 32,
          inZoneMinutes: 30,
        ),
        session(
          DateTime(2026, 10, 20, 8),
          lengthMinutes: 38,
          inZoneMinutes: 35,
        ),
        session(
          DateTime(2026, 10, 21, 8),
          lengthMinutes: 32,
          inZoneMinutes: 30,
        ),
      ], now: now);
      expect(progress.weeks, hasLength(8));
      expect(progress.currentWeek.targetMinutes, 95);
      expect(progress.currentWeek.sessionCount, 3);
      expect(progress.currentWeek.totalDuration, const Duration(minutes: 102));
      expect(
        progress.currentWeekSummary(),
        'Diese Woche 95 / 150 min · 3 Einheiten · 1:42 h',
      );
      expect(progress.hasSessions, isTrue);
      expect(progress.hasZone2, isFalse);
    });

    test('Wochen laufen von Montag bis Sonntag lokal', () {
      final progress = CardioProgress.compute([
        // Sonntag 23:30 gehört zur Vorwoche, Montag 00:10 zur neuen Woche.
        session(DateTime(2026, 10, 18, 23, 30), lengthMinutes: 20),
        session(DateTime(2026, 10, 19, 0, 10), lengthMinutes: 10),
        // Älter als 8 Wochen: zählt nicht.
        session(DateTime(2026, 8, 20, 8), lengthMinutes: 40),
      ], now: now);
      expect(progress.weeks.first.start, DateTime(2026, 8, 31));
      expect(progress.weeks.last.start, DateTime(2026, 10, 19));
      expect(progress.weeks[6].targetMinutes, 20);
      expect(progress.currentWeek.targetMinutes, 10);
      expect(
        progress.weeks.map((w) => w.sessionCount).reduce((a, b) => a + b),
        2,
      );
    });

    test('ohne Einheiten: leer, das Wochenziel bleibt', () {
      final progress = CardioProgress.compute(
        const [],
        now: now,
        weeklyTargetMinutes: 200,
      );
      expect(progress.hasSessions, isFalse);
      expect(progress.currentWeek.sessionCount, 0);
      expect(
        progress.currentWeekSummary(),
        'Diese Woche 0 / 200 min · 0 Einheiten · 0:00 h',
      );
      expect(progress.efficiency, isEmpty);
      expect(progress.samePower, isNull);
      expect(progress.recoveryAverageBpm, isNull);
    });

    test('Zone 2 aus den gespeicherten Reihen mit den aktuellen Zonen', () {
      // HFmax 180 ohne Ruhepuls: Zone 2 = 108 bis 126.
      final zones = CardioZones.compute(180);
      final progress = CardioProgress.compute(
        [
          session(DateTime(2026, 10, 20, 8), lengthMinutes: 40, bpm: 115),
          // 130 bpm liegt im Zielbereich, aber nicht in Zone 2.
          session(DateTime(2026, 10, 21, 8), lengthMinutes: 30, bpm: 130),
        ],
        now: now,
        zones: zones,
      );
      expect(progress.hasZone2, isTrue);
      expect(progress.currentWeek.zone2Minutes, 40);
      expect(progress.currentWeek.targetMinutes, 30);
      expect(
        progress.currentWeekSummary(zone2: true),
        startsWith('Diese Woche 40 / 150 min · 2 Einheiten'),
      );
    });
  });

  group('CardioProgress aerobe Form', () {
    test('Effizienzfaktor auf zwei Nachkommastellen', () {
      final progress = CardioProgress.compute([
        session(
          DateTime(2026, 10, 20, 8),
          lengthMinutes: 30,
          bpm: 138,
          power: 150,
        ),
        session(DateTime(2026, 10, 21, 8), lengthMinutes: 30, bpm: 130),
      ], now: now);
      // Nur die Einheit mit Leistung zählt.
      expect(progress.efficiency, hasLength(1));
      expect(progress.efficiency.single.efficiency, 1.09);
    });

    test('Spec: bei 150 W: 138 → 131 bpm', () {
      final progress = CardioProgress.compute([
        session(
          DateTime(2026, 10, 5, 8),
          lengthMinutes: 30,
          bpm: 138,
          power: 148,
        ),
        session(
          DateTime(2026, 10, 9, 8),
          lengthMinutes: 30,
          bpm: 136,
          power: 152,
        ),
        session(
          DateTime(2026, 10, 14, 8),
          lengthMinutes: 30,
          bpm: 133,
          power: 150,
        ),
        session(
          DateTime(2026, 10, 20, 8),
          lengthMinutes: 30,
          bpm: 131,
          power: 151,
        ),
      ], now: now);
      final comparison = progress.samePower!;
      expect(comparison.powerWatts, 150);
      expect((comparison.firstBpm, comparison.lastBpm), (138, 131));
      expect(comparison.sessionCount, 4);
    });

    test('unter drei Einheiten je Stufe gibt es keinen Vergleich', () {
      final progress = CardioProgress.compute([
        session(
          DateTime(2026, 10, 5, 8),
          lengthMinutes: 30,
          bpm: 138,
          power: 150,
        ),
        session(
          DateTime(2026, 10, 9, 8),
          lengthMinutes: 30,
          bpm: 136,
          power: 150,
        ),
        session(
          DateTime(2026, 10, 14, 8),
          lengthMinutes: 30,
          bpm: 133,
          power: 170,
        ),
      ], now: now);
      expect(progress.samePower, isNull);
      expect(progress.efficiency, hasLength(3));
    });

    test('die häufigste Stufe gewinnt, bei Gleichstand die höhere', () {
      final progress = CardioProgress.compute([
        for (var i = 0; i < 3; i++)
          session(
            DateTime(2026, 10, 1 + i, 8),
            lengthMinutes: 30,
            bpm: 130,
            power: 100,
          ),
        for (var i = 0; i < 4; i++)
          session(
            DateTime(2026, 10, 5 + i, 8),
            lengthMinutes: 30,
            bpm: 130,
            power: 120,
          ),
      ], now: now);
      expect(progress.samePower!.powerWatts, 120);
      final tie = CardioProgress.compute([
        for (var i = 0; i < 3; i++)
          session(
            DateTime(2026, 10, 1 + i, 8),
            lengthMinutes: 30,
            bpm: 130,
            power: 100,
          ),
        for (var i = 0; i < 3; i++)
          session(
            DateTime(2026, 10, 5 + i, 8),
            lengthMinutes: 30,
            bpm: 130,
            power: 120,
          ),
      ], now: now);
      expect(tie.samePower!.powerWatts, 120);
    });

    test('der Verlauf hält die letzten 20 Einheiten', () {
      final progress = CardioProgress.compute([
        for (var i = 0; i < 25; i++)
          session(
            DateTime(2026, 9, 1).add(Duration(days: i)),
            lengthMinutes: 20,
            bpm: 130,
            power: 100.0 + i,
          ),
      ], now: now);
      expect(progress.efficiency, hasLength(20));
      expect(progress.efficiency.last.powerWatts, 124);
      expect(progress.efficiency.first.powerWatts, 105);
    });
  });

  group('CardioProgress Erholung', () {
    test('Mittel der letzten 5 Einheiten mit Erholung', () {
      final progress = CardioProgress.compute([
        // Älteste (zählt nicht): −50.
        session(
          DateTime(2026, 9, 20, 8),
          lengthMinutes: 20,
          recoveryStart: 150,
          recoveryEnd: 100,
        ),
        session(
          DateTime(2026, 10, 1, 8),
          lengthMinutes: 20,
          recoveryStart: 150,
          recoveryEnd: 124,
        ),
        session(
          DateTime(2026, 10, 5, 8),
          lengthMinutes: 20,
          recoveryStart: 150,
          recoveryEnd: 124,
        ),
        // Ohne Erholung: übersprungen.
        session(DateTime(2026, 10, 8, 8), lengthMinutes: 20),
        session(
          DateTime(2026, 10, 12, 8),
          lengthMinutes: 20,
          recoveryStart: 150,
          recoveryEnd: 124,
        ),
        session(
          DateTime(2026, 10, 15, 8),
          lengthMinutes: 20,
          recoveryStart: 150,
          recoveryEnd: 124,
        ),
        session(
          DateTime(2026, 10, 20, 8),
          lengthMinutes: 20,
          recoveryStart: 154,
          recoveryEnd: 128,
        ),
      ], now: now);
      expect(progress.recoverySampleCount, 5);
      expect(progress.recoveryAverageBpm, -26);
    });
  });

  group('RestingMeasurement', () {
    final t0 = DateTime.utc(2026, 10, 19, 6);

    List<CardioSample> samples(List<int> bpm, List<int> rr) => [
      for (var i = 0; i < bpm.length; i++)
        CardioSample(
          sequence: i + 1,
          atUtc: t0.add(Duration(seconds: i)),
          bpm: bpm[i],
          rrIntervalsMs: i == 0 ? rr : const [],
        ),
    ];

    test('Median bei ungerader und gerader Anzahl', () {
      expect(RestingMeasurement.median([60, 58, 70]), 60);
      expect(RestingMeasurement.median([60, 58, 70, 62]), 61);
      expect(RestingMeasurement.median(const []), isNull);
    });

    test('Ruhepuls ist der Median, Signal 0 zählt nicht', () {
      final result = RestingMeasurement.of(
        samples([58, 0, 60, 62, 59], const []),
      );
      expect(result.restingHeartRateBpm, 59.5.round());
      expect(result.rmssdMs, isNull);
      expect(result.isStorable, isFalse);
    });

    test('RMSSD und Artefaktanteil', () {
      // 40 saubere Differenzen von 20 ms: RMSSD 20.
      final clean = [for (var i = 0; i < 41; i++) i.isEven ? 800 : 820];
      final ok = RestingMeasurement.of(samples([58, 59, 60], clean));
      expect(ok.rmssdMs, 20);
      expect(ok.artifactRatio, 0);
      expect(ok.isNoisy, isFalse);
      expect(ok.isStorable, isTrue);
      expect(ok.validRrCount, 41);

      // 5 Ausreißer verwerfen je zwei Differenzen: 10 von 40 = 25 %.
      final noisy = [...clean];
      for (final index in [3, 11, 19, 27, 35]) {
        noisy[index] = 1500;
      }
      final result = RestingMeasurement.of(samples([58, 59, 60], noisy));
      expect(result.artifactRatio, 0.25);
      expect(result.isNoisy, isTrue);
    });

    test('Ruhepuls außerhalb 25 bis 150 ist nicht speicherbar', () {
      final clean = [for (var i = 0; i < 41; i++) i.isEven ? 800 : 820];
      final result = RestingMeasurement.of(samples([160, 165, 170], clean));
      expect(result.restingHeartRateBpm, 165);
      expect(result.isStorable, isFalse);
    });
  });
}
