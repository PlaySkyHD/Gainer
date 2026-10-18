import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_analysis.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_draft.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_zones.dart';

CardioSession session(List<int> bpm, {List<int> rr = const []}) =>
    CardioSession(
      sessionId: '00000000-0000-4000-8000-000000000001',
      startedAtUtc: DateTime.utc(2026, 10, 18, 10),
      endedAtUtc: DateTime.utc(2026, 10, 18, 10, 0, 25),
      targetZone: const CardioTargetZone(lowBpm: 120, highBpm: 140),
      heartRateBpm: bpm,
      rrIntervalsMs: rr,
      createdAtUtc: DateTime.utc(2026, 10, 18, 10, 1),
      updatedAtUtc: DateTime.utc(2026, 10, 18, 10, 1),
    );

void main() {
  group('CardioSession', () {
    test('json round trip omits null optionals', () {
      final value = session([100, 0, 130]);
      final json = value.toJson();
      expect(json.containsKey('notes'), isFalse);
      expect(json['activityType'], 'IndoorCycling');
      final back = CardioSession.fromJson(
        Map<String, dynamic>.from(
          (json..['distanceKm'] = 14.2).cast<String, dynamic>(),
        ),
      );
      expect(back.heartRateBpm, [100, 0, 130]);
      expect(back.distanceKm, 14.2);
      expect(
        back.targetZone,
        const CardioTargetZone(lowBpm: 120, highBpm: 140),
      );
      expect(CardioActivityType.indoorCycling.label, 'Rad-Ergometer');
    });
  });

  group('CardioAnalysis', () {
    test('spec example: avg, max and time in zone ignore no-signal values', () {
      final analysis = CardioAnalysis.of(session([118, 125, 0, 141, 130]));
      expect(analysis.averageBpm, 128.5);
      expect(analysis.maxBpm, 141);
      expect(analysis.timeInZone, const Duration(seconds: 10));
      expect(analysis.zoneShare, 0.5);
      expect(analysis.activeDuration, const Duration(seconds: 25));
      expect(analysis.rmssdMs, isNull);
    });

    test('no signal gives no average', () {
      final analysis = CardioAnalysis.of(session([0, 0]));
      expect(analysis.averageBpm, isNull);
      expect(analysis.maxBpm, isNull);
      expect(analysis.zoneShare, isNull);
    });

    List<int> alternating(int pairs) => [
      for (var i = 0; i < pairs; i++) ...[800, 820],
    ];

    test('RMSSD from valid differences', () {
      expect(CardioAnalysis.rmssd(alternating(20)), 20);
    });

    test('RMSSD drops artefacts and their differences', () {
      final rr = alternating(20)..insert(20, 2400);
      expect(CardioAnalysis.rmssd(rr), 20);
    });

    test('RMSSD drops jumps over 20 percent', () {
      final rr = alternating(20)..insert(20, 1200);
      // 1200 is a valid value but jumps by far more than 20 %.
      expect(CardioAnalysis.rmssd(rr), 20);
    });

    test('fewer than 30 differences give no value', () {
      expect(CardioAnalysis.rmssd(alternating(15)), isNull);
    });
  });

  group('CardioZones', () {
    test('without resting heart rate', () {
      final zones = CardioZones.compute(190);
      expect(zones[1], const CardioZone(number: 2, lowBpm: 114, highBpm: 133));
      expect(zones[0].highBpm, zones[1].lowBpm);
      expect(zones, hasLength(5));
    });

    test('Karvonen with resting heart rate', () {
      final zone2 = CardioZones.compute(190, 60)[1];
      expect((zone2.lowBpm, zone2.highBpm), (138, 151));
    });

    test('from age', () {
      final max = CardioZones.maxHeartRateFor(30);
      expect(max, 187);
      final zone2 = CardioZones.compute(max)[1];
      expect((zone2.lowBpm, zone2.highBpm), (112, 131));
    });
  });

  group('CardioBucketer', () {
    final start = DateTime.utc(2026, 10, 18, 10);
    CardioDraft draft() =>
        CardioDraft(sessionId: 'a', startedAtUtc: start, warmupSeconds: 0);
    CardioSample sample(int seq, int seconds, int bpm, [List<int>? rr]) =>
        CardioSample(
          sequence: seq,
          atUtc: start.add(Duration(seconds: seconds)),
          bpm: bpm,
          rrIntervalsMs: rr ?? const [],
        );

    test('means per bucket, gaps become 0, open bucket stays open', () {
      final folded = CardioBucketer.fold(draft(), [
        sample(1, 1, 100),
        sample(2, 3, 111),
        sample(3, 6, 130),
        sample(4, 16, 140, [800]),
      ], nowUtc: start.add(const Duration(seconds: 17)));
      expect(folded.buckets, [106, 130, 0]);
      expect(folded.openCount, 1);
      expect(folded.rrIntervalsMs, [800]);
      expect(folded.lastSequence, 4);
      final later = CardioBucketer.fold(
        folded,
        const [],
        nowUtc: start.add(const Duration(seconds: 20)),
      );
      expect(later.buckets, [106, 130, 0, 140]);
    });

    test('time passing without samples finalizes zeros', () {
      final folded = CardioBucketer.fold(
        draft(),
        const [],
        nowUtc: start.add(const Duration(seconds: 12)),
      );
      expect(folded.buckets, [0, 0]);
    });

    test('ignores old sequences and out-of-range bpm becomes 0', () {
      var d = CardioBucketer.fold(draft(), [
        sample(1, 1, 300),
      ], nowUtc: start.add(const Duration(seconds: 6)));
      expect(d.buckets, [0]);
      d = CardioBucketer.fold(d, [
        sample(1, 7, 120),
      ], nowUtc: start.add(const Duration(seconds: 10)));
      expect(d.buckets, [0, 0]);
    });

    test('finish includes the partial bucket', () {
      final folded = CardioBucketer.fold(draft(), [
        sample(1, 1, 100),
        sample(2, 6, 120),
      ], nowUtc: start.add(const Duration(seconds: 7)));
      expect(
        CardioBucketer.finish(folded, start.add(const Duration(seconds: 8))),
        [100, 120],
      );
    });

    test('draft json round trip', () {
      final folded = CardioBucketer.fold(draft(), [
        sample(1, 1, 100, [700, 710]),
      ], nowUtc: start.add(const Duration(seconds: 2)));
      final back = CardioDraft.fromJson(
        Map<String, dynamic>.from(
          (folded
              .copyWith(
                targetZone: () =>
                    const CardioTargetZone(lowBpm: 100, highBpm: 120),
              )
              .toJson()),
        ),
      );
      expect(back.openSum, 100);
      expect(back.rrIntervalsMs, [700, 710]);
      expect(back.targetZone?.highBpm, 120);
    });
  });
}
