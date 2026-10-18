import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/warmup.dart';
import 'package:gainer_mobile/domain/models/training/workout_input.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

List<WarmupTarget> _targets(
  double baseKg, {
  List<WarmupStep> steps = defaultWarmupSteps,
  double rounding = 2.5,
  WeightUnit unit = WeightUnit.kg,
}) =>
    warmupTargets(baseKg: baseKg, steps: steps, rounding: rounding, unit: unit);

void main() {
  group('Standardwerte', () {
    test('Hinweis an, Wiederholungen aus, 50 % und 80 %', () {
      const settings = WarmupSettings();

      expect(settings.enabled, isTrue);
      expect(settings.showRepetitions, isFalse);
      expect(settings.steps, const [
        WarmupStep(percent: 50),
        WarmupStep(percent: 80),
      ]);
      expect(defaultWarmupRounding(WeightUnit.kg), 2.5);
      expect(defaultWarmupRounding(WeightUnit.lbs), 5);
    });

    test('Einstellungen überstehen JSON, auch eine leere Stufenliste', () {
      const settings = WarmupSettings(
        enabled: false,
        showRepetitions: true,
        steps: [WarmupStep(percent: 40, repetitions: 10)],
      );

      expect(WarmupSettings.fromJson(settings.toJson()), settings);
      expect(
        WarmupSettings.fromJson(const WarmupSettings(steps: []).toJson()).steps,
        isEmpty,
      );
    });

    test('fehlende oder kaputte Felder fallen auf den Standard zurück', () {
      expect(WarmupSettings.fromJson(null), const WarmupSettings());
      expect(WarmupSettings.fromJson(<String, Object?>{}).steps, [
        for (final step in defaultWarmupSteps) step,
      ]);
      expect(
        WarmupSettings.fromJson(<String, Object?>{'enabled': 'ja'}).enabled,
        isTrue,
      );
    });
  });

  group('Grenzen', () {
    test('Stufen außerhalb von 1–100 % und 1–50 Wdh. werden verworfen', () {
      expect(WarmupStep.tryFromJson({'percent': 0}), isNull);
      expect(WarmupStep.tryFromJson({'percent': 101}), isNull);
      expect(WarmupStep.tryFromJson({'percent': 50, 'repetitions': 0}), isNull);
      expect(
        WarmupStep.tryFromJson({'percent': 50, 'repetitions': 51}),
        isNull,
      );
      expect(WarmupStep.tryFromJson({'percent': 'x'}), isNull);
      expect(WarmupStep.tryFromJson('x'), isNull);
      expect(
        WarmupStep.tryFromJson({'percent': 100, 'repetitions': 50}),
        const WarmupStep(percent: 100, repetitions: 50),
      );
      expect(
        WarmupStep.tryFromJson({'percent': 1, 'repetitions': 1}),
        const WarmupStep(percent: 1, repetitions: 1),
      );
    });

    test('gespeichert werden höchstens fünf gültige Stufen', () {
      final settings = WarmupSettings.fromJson({
        'steps': [
          for (var i = 1; i <= 7; i++) {'percent': i * 10},
        ],
      });

      expect(settings.steps, hasLength(maxWarmupSteps));
      expect(settings.steps.last.percent, 50);
    });
  });

  group('Übungsabweichung und Vererbung', () {
    test('ohne Abweichung gelten die globalen Werte', () {
      final resolved = resolveWarmup(
        const WarmupSettings(showRepetitions: true),
        null,
        WeightUnit.kg,
      );

      expect(resolved.enabled, isTrue);
      expect(resolved.steps, defaultWarmupSteps);
      expect(resolved.rounding, 2.5);
      expect(resolved.showRepetitions, isTrue);
    });

    test('eigene Felder überschreiben, fehlende erben', () {
      const override = ExerciseWarmupOverride(
        exerciseId: 'curl',
        steps: [WarmupStep(percent: 60)],
        rounding: 1,
      );

      final resolved = resolveWarmup(
        const WarmupSettings(),
        override,
        WeightUnit.kg,
      );

      expect(resolved.enabled, isTrue);
      expect(resolved.steps, const [WarmupStep(percent: 60)]);
      expect(resolved.rounding, 1);
    });

    test('Übung aus oder global aus schaltet den Hinweis ab', () {
      const off = ExerciseWarmupOverride(exerciseId: 'curl', enabled: false);

      expect(
        resolveWarmup(const WarmupSettings(), off, WeightUnit.kg).enabled,
        isFalse,
      );
      expect(
        resolveWarmup(
          const WarmupSettings(enabled: false),
          const ExerciseWarmupOverride(exerciseId: 'curl', enabled: true),
          WeightUnit.kg,
        ).enabled,
        isFalse,
      );
    });

    test(
      'eine in der Einheit nicht erlaubte Rundung fällt auf den Standard',
      () {
        const override = ExerciseWarmupOverride(
          exerciseId: 'a',
          rounding: 1.25,
        );

        expect(
          resolveWarmup(
            const WarmupSettings(),
            override,
            WeightUnit.lbs,
          ).rounding,
          5,
        );
        expect(
          resolveWarmup(
            const WarmupSettings(),
            override,
            WeightUnit.kg,
          ).rounding,
          1.25,
        );
      },
    );

    test('Abweichungen überstehen JSON; leere gelten als nicht vorhanden', () {
      const override = ExerciseWarmupOverride(
        exerciseId: 'bench',
        enabled: false,
        steps: [WarmupStep(percent: 30, repetitions: 5)],
        rounding: 0.5,
      );

      expect(
        ExerciseWarmupOverride.tryFromJson('bench', override.toJson()),
        override,
      );
      expect(
        ExerciseWarmupOverride.tryFromJson(
          'bench',
          const ExerciseWarmupOverride(exerciseId: 'bench').toJson(),
        ),
        isNull,
      );
      expect(ExerciseWarmupOverride.tryFromJson('bench', 3), isNull);
      expect(const ExerciseWarmupOverride(exerciseId: 'bench').isEmpty, isTrue);
    });

    test('copyWith kann Felder gezielt leeren', () {
      const override = ExerciseWarmupOverride(
        exerciseId: 'a',
        enabled: false,
        steps: [WarmupStep(percent: 30)],
        rounding: 1,
      );

      final cleared = override.copyWith(
        enabled: () => null,
        steps: () => null,
        rounding: () => null,
      );

      expect(cleared.isEmpty, isTrue);
      expect(
        cleared.hashCode,
        const ExerciseWarmupOverride(exerciseId: 'a').hashCode,
      );
    });
  });

  group('warmupTargets', () {
    test('80 kg mit 50 % und 80 % ergibt 40 und 65 kg', () {
      final targets = _targets(80);

      expect([for (final t in targets) t.weightKg], [40, 65]);
    });

    test('Wiederholungen bleiben je Stufe erhalten', () {
      final targets = _targets(
        100,
        steps: const [
          WarmupStep(percent: 80, repetitions: 3),
          WarmupStep(percent: 50, repetitions: 8),
        ],
      );

      expect(targets, const [
        WarmupTarget(weightKg: 50, repetitions: 8),
        WarmupTarget(weightKg: 80, repetitions: 3),
      ]);
    });

    test('rundet auf das nächste Vielfache, auch bei anderer Rundung', () {
      expect(
        [for (final t in _targets(83, rounding: 2.5)) t.weightKg],
        [42.5, 67.5],
      );
      expect([for (final t in _targets(83, rounding: 1)) t.weightKg], [42, 66]);
      expect(
        [for (final t in _targets(83, rounding: 0.5)) t.weightKg],
        [41.5, 66.5],
      );
      expect([for (final t in _targets(83, rounding: 5)) t.weightKg], [40, 65]);
    });

    test('rechnet in lb und liefert kg', () {
      final base = WeightUnit.lbs.toKg(225);

      final targets = _targets(base, rounding: 5, unit: WeightUnit.lbs);

      expect(
        [for (final t in targets) WeightUnit.lbs.fromKg(t.weightKg)],
        [closeTo(115, 1e-6), closeTo(180, 1e-6)],
      );
    });

    test('Stufen mit Ergebnis 0 oder mindestens Basis entfallen', () {
      expect(_targets(80, steps: const [WarmupStep(percent: 100)]), isEmpty);
      expect(
        _targets(
          20,
          steps: const [WarmupStep(percent: 5), WarmupStep(percent: 50)],
        ),
        const [WarmupTarget(weightKg: 10)],
      );
      expect(
        _targets(
          20,
          steps: const [WarmupStep(percent: 99), WarmupStep(percent: 50)],
        ),
        const [WarmupTarget(weightKg: 10)],
      );
    });

    test('gleiche Gewichte werden zusammengefasst', () {
      final targets = _targets(
        20,
        steps: const [
          WarmupStep(percent: 50, repetitions: 8),
          WarmupStep(percent: 52, repetitions: 5),
        ],
      );

      expect(targets, const [WarmupTarget(weightKg: 10, repetitions: 8)]);
    });

    test('ohne Basis, Rundung oder Stufen gibt es nichts', () {
      expect(_targets(0), isEmpty);
      expect(_targets(80, rounding: 0), isEmpty);
      expect(_targets(80, steps: const []), isEmpty);
    });
  });

  group('Basis und Text', () {
    test('Basis ist der erste normale Vorwert-Satz mit Gewicht', () {
      expect(
        warmupBaseKg(const [
          null,
          LoggedSet(setId: 'a', setType: SetType.warmup, weightKg: 40),
          LoggedSet(setId: 'b', weightKg: 0),
          LoggedSet(setId: 'c'),
          LoggedSet(setId: 'd', weightKg: 80),
          LoggedSet(setId: 'e', weightKg: 90),
        ]),
        80,
      );
      expect(warmupBaseKg(const [null]), isNull);
      expect(warmupBaseKg(const []), isNull);
    });

    test('Text mit deutschem Komma, optional mit Wiederholungen', () {
      const targets = [
        WarmupTarget(weightKg: 40, repetitions: 8),
        WarmupTarget(weightKg: 62.5),
      ];

      expect(
        formatWarmupHint(targets, WeightUnit.kg, showRepetitions: false),
        'Aufwärmen 40 kg · 62,5 kg',
      );
      expect(
        formatWarmupHint(targets, WeightUnit.kg, showRepetitions: true),
        'Aufwärmen 40 kg × 8 · 62,5 kg',
      );
    });
  });
}
