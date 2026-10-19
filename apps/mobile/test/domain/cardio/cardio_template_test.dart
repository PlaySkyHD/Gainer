import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_analysis.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_draft.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_template.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_zones.dart';

CardioSession withPhases(
  List<int> bpm,
  List<CardioPhase> phases, {
  String? templateName,
}) => CardioSession(
  sessionId: '00000000-0000-4000-8000-000000000001',
  startedAtUtc: DateTime.utc(2026, 10, 18, 10),
  endedAtUtc: DateTime.utc(2026, 10, 18, 10, 0, 10),
  heartRateBpm: bpm,
  rrIntervalsMs: const [],
  templateName: templateName,
  phases: phases,
  createdAtUtc: DateTime.utc(2026, 10, 18, 10, 1),
  updatedAtUtc: DateTime.utc(2026, 10, 18, 10, 1),
);

void main() {
  group('CardioTemplate', () {
    test('4x4 has nine phases and resolves Z4 to 152-171 for max 190', () {
      final phases = CardioTemplate.norwegian.resolve(CardioZones.compute(190));
      expect(phases, hasLength(9));
      expect(phases.first.name, 'Aufwärmen');
      expect(phases.first.durationSeconds, 600);
      final load = phases[1];
      expect(load.name, 'Belastung');
      expect(load.startOffsetSeconds, 600);
      expect(load.zone, const CardioTargetZone(lowBpm: 152, highBpm: 171));
      expect(phases[2].name, 'Erholung');
      expect(phases[2].durationSeconds, 180);
      expect(phases.last.name, 'Ausfahren');
      expect(phases.last.durationSeconds, 300);
      expect(phases.last.endOffsetSeconds, 600 + 4 * 240 + 3 * 180 + 300);
      expect(CardioPhase.isValidList(phases), isTrue);
      expect(CardioTemplate.norwegian.validate(), isNull);
    });

    test('Zone 2 - 30 min is one phase', () {
      final phases = CardioTemplate.zone2.resolve(CardioZones.compute(190));
      expect(phases, hasLength(1));
      expect(phases.single.durationSeconds, 1800);
      expect(
        phases.single.zone,
        const CardioTargetZone(lowBpm: 114, highBpm: 133),
      );
    });

    test('zone targets without zones fail, bpm and none targets do not', () {
      expect(
        () => CardioTemplate.norwegian.resolve(const []),
        throwsA(isA<CardioTemplateResolutionException>()),
      );
      const custom = CardioTemplate(
        id: 'a',
        name: 'Fest',
        phases: [
          CardioTemplatePhase(
            name: 'A',
            durationSeconds: 60,
            target: CardioBpmTarget(120, 140),
          ),
          CardioTemplatePhase(name: 'B', durationSeconds: 60),
        ],
      );
      expect(custom.needsZones, isFalse);
      final phases = custom.resolve(const []);
      expect(phases[0].zone, const CardioTargetZone(lowBpm: 120, highBpm: 140));
      expect(phases[1].zone, isNull);
      expect(phases[1].startOffsetSeconds, 60);
    });

    test('json round trip', () {
      final back = CardioTemplate.fromJson(
        CardioTemplate.norwegian.toJson().cast<String, dynamic>(),
      );
      expect(back.phases, CardioTemplate.norwegian.phases);
      expect(back.name, CardioTemplate.norwegian.name);
    });

    test('validate follows the data contract', () {
      CardioTemplate make(List<CardioTemplatePhase> phases, {String? name}) =>
          CardioTemplate(id: 'a', name: name ?? 'T', phases: phases);
      const ok = CardioTemplatePhase(name: 'A', durationSeconds: 60);
      expect(make(const [ok]).validate(), isNull);
      expect(make(const [ok], name: ' ').validate(), isNotNull);
      expect(make(const []).validate(), isNotNull);
      expect(
        make([for (var i = 0; i < 31; i++) ok]).validate(),
        contains('30'),
      );
      expect(
        make(const [CardioTemplatePhase(name: 'A', durationSeconds: 29)])
            .validate(),
        contains('Dauer'),
      );
      expect(
        make(const [CardioTemplatePhase(name: 'A', durationSeconds: 3601)])
            .validate(),
        contains('Dauer'),
      );
      expect(
        make(const [CardioTemplatePhase(name: '', durationSeconds: 60)])
            .validate(),
        contains('Namen'),
      );
      expect(
        make(const [
          CardioTemplatePhase(
            name: 'A',
            durationSeconds: 60,
            target: CardioBpmTarget(150, 140),
          ),
        ]).validate(),
        contains('Pulsbereich'),
      );
      expect(
        make(const [
          CardioTemplatePhase(
            name: 'A',
            durationSeconds: 60,
            target: CardioBpmTarget(30, 140),
          ),
        ]).validate(),
        isNotNull,
      );
      // 5 x 3000 s = 4 h 10 min.
      expect(
        make([
          for (var i = 0; i < 5; i++)
            const CardioTemplatePhase(name: 'A', durationSeconds: 3000),
        ]).validate(),
        contains('4 Stunden'),
      );
    });

    test('longestPhaseZone picks the zone of the longest phase', () {
      final phases = CardioTemplate.norwegian.resolve(CardioZones.compute(190));
      // Aufwärmen (10 min, Zone 2) ist die längste Phase.
      expect(
        longestPhaseZone(phases),
        const CardioTargetZone(lowBpm: 114, highBpm: 133),
      );
      expect(longestPhaseZone(const []), isNull);
    });
  });

  group('CardioAnalysis with phases', () {
    const phases = [
      CardioPhase(
        startOffsetSeconds: 0,
        durationSeconds: 5,
        name: 'A',
        lowBpm: 110,
        highBpm: 130,
      ),
      CardioPhase(
        startOffsetSeconds: 5,
        durationSeconds: 5,
        name: 'B',
        lowBpm: 150,
        highBpm: 170,
      ),
    ];

    test('time in zone uses the phase valid at each interval (spec)', () {
      final analysis = CardioAnalysis.of(withPhases([120, 160], phases));
      expect(analysis.timeInZone, const Duration(seconds: 10));
      expect(analysis.zoneShare, 1);
    });

    test('values outside the phase zone do not count', () {
      final analysis = CardioAnalysis.of(withPhases([160, 120], phases));
      expect(analysis.timeInZone, Duration.zero);
      expect(analysis.zoneShare, 0);
    });

    test(
      'intervals after the last phase and phases without target are skipped',
      () {
        final analysis = CardioAnalysis.of(
          withPhases(
            [120, 120, 120],
            const [
              CardioPhase(
                startOffsetSeconds: 0,
                durationSeconds: 5,
                name: 'A',
                lowBpm: 110,
                highBpm: 130,
              ),
              CardioPhase(startOffsetSeconds: 5, durationSeconds: 5, name: 'B'),
            ],
          ),
        );
        expect(analysis.timeInZone, const Duration(seconds: 5));
        expect(analysis.zoneShare, 1);
      },
    );
  });

  group('CardioSession with phases', () {
    final phases = CardioTemplate.norwegian.resolve(CardioZones.compute(190));

    test('json round trip keeps templateName and phases', () {
      final value = withPhases([120, 130], phases, templateName: '4×4');
      final json = value.toJson();
      expect(json['templateName'], '4×4');
      expect((json['phases'] as List), hasLength(9));
      final back = CardioSession.fromJson(json.cast<String, dynamic>());
      expect(back.templateName, '4×4');
      expect(back.phases, phases);
    });

    test('free sessions omit both fields', () {
      final json = withPhases([120], const []).toJson();
      expect(json.containsKey('templateName'), isFalse);
      expect(json.containsKey('phases'), isFalse);
      final back = CardioSession.fromJson(json.cast<String, dynamic>());
      expect(back.phases, isEmpty);
      expect(back.templateName, isNull);
    });

    test('copyWith keeps phases and can clear the template name', () {
      final value = withPhases([120], phases, templateName: 'x');
      expect(value.copyWith(notes: () => 'n').phases, phases);
      expect(value.copyWith(templateName: () => null).templateName, isNull);
    });

    test('draft json round trip restores template and phases', () {
      final draft = CardioDraft(
        sessionId: 'a',
        startedAtUtc: DateTime.utc(2026, 10, 18, 10),
        warmupSeconds: 60,
        templateName: '4×4',
        phases: phases,
      );
      final back = CardioDraft.fromJson(draft.toJson().cast<String, dynamic>());
      expect(back.templateName, '4×4');
      expect(back.phases, phases);
      expect(back.copyWith(lastSequence: 3).phases, phases);
    });

    test('sanitize keeps valid phases and trims names', () {
      final clean = CardioRepository.sanitize(
        withPhases(
          [120, 130],
          [
            const CardioPhase(
              startOffsetSeconds: 0,
              durationSeconds: 60,
              name: '  Warm  ',
            ),
          ],
          templateName: '${'x' * 150} ',
        ),
      );
      expect(clean.templateName, hasLength(100));
      expect(clean.phases.single.name, 'Warm');
    });

    test('sanitize drops invalid phase lists as a whole', () {
      CardioSession build(List<CardioPhase> list) =>
          CardioRepository.sanitize(withPhases([120, 130], list));
      const base = CardioPhase(
        startOffsetSeconds: 0,
        durationSeconds: 60,
        name: 'A',
      );
      // Überlappend.
      expect(
        build([
          base,
          const CardioPhase(
            startOffsetSeconds: 30,
            durationSeconds: 60,
            name: 'B',
          ),
        ]).phases,
        isEmpty,
      );
      // Zone nur halb.
      expect(
        build([
          const CardioPhase(
            startOffsetSeconds: 0,
            durationSeconds: 60,
            name: 'A',
            lowBpm: 120,
          ),
        ]).phases,
        isEmpty,
      );
      // Mehr als 30 Phasen.
      expect(
        build([
          for (var i = 0; i < 31; i++)
            CardioPhase(
              startOffsetSeconds: i * 60,
              durationSeconds: 60,
              name: 'P$i',
            ),
        ]).phases,
        isEmpty,
      );
      expect(build([base]).phases, [base]);
    });
  });
}
