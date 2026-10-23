import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/nutrition/day_target.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition_averages.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

// Donnerstag, 22. Oktober 2026.
final _today = LocalDay(2026, 10, 22);

TrainingPlanModel _plan(String id) => TrainingPlanModel(
  planId: id,
  name: id,
  previousValueSource: PreviousValueSource.exercise,
);

final _plans = [_plan('Push'), _plan('Pull'), _plan('Beine')];

var _counter = 0;

Workout _workout(LocalDay day, {String? planId, bool deleted = false}) {
  final start = DateTime(day.year, day.month, day.day, 18).toUtc();
  return Workout(
    workoutId: 'w${_counter++}',
    title: planId ?? 'Training',
    startedAtUtc: start,
    endedAtUtc: start.add(const Duration(hours: 1)),
    previousValueSource: PreviousValueSource.exercise,
    sourcePlanId: planId,
    deletedAtUtc: deleted ? start.add(const Duration(hours: 2)) : null,
  );
}

/// Feste Tage Mo–So; null ist ein Ruhetag.
TrainingSchedule _weekly(List<String?> planIds) => TrainingSchedule.create(
  scheduleId: 'schedule',
  mode: TrainingScheduleMode.weekly,
  slots: [for (final id in planIds) TrainingScheduleSlot(planId: id)],
  today: LocalDay(2026, 10, 1),
);

TrainingScheduleProjection _project(
  TrainingSchedule? schedule, {
  List<Workout> workouts = const [],
}) => TrainingScheduleProjection(
  schedule: schedule,
  plans: _plans,
  workouts: workouts,
  today: _today,
);

const _rest = NutritionDayTarget(
  inputMode: NutritionTargetInputMode.grams,
  kilocalories: 2200,
  proteinGrams: 180,
  carbohydrateGrams: 190,
  fatGrams: 80,
);

NutritionTargetVersion _version(
  String from, {
  String? until,
  double kcal = 2600,
  NutritionDayTarget? rest,
}) => NutritionTargetVersion(
  targetVersionId: 'v-$from',
  name: 'Ziele',
  category: NutritionTargetCategory.custom,
  effectiveFrom: from,
  effectiveUntil: until,
  inputMode: NutritionTargetInputMode.grams,
  kilocalories: kcal,
  proteinGrams: 180,
  carbohydrateGrams: 290,
  fatGrams: 80,
  proteinPercent: null,
  carbohydratePercent: null,
  fatPercent: null,
  restDay: rest,
);

NutritionDayTargetResult? _target(
  String date,
  TrainingScheduleProjection projection, {
  NutritionTargetSchedule? targets,
  NutritionDayKind? manual,
}) => dayTarget(
  localDate: date,
  targets:
      targets ??
      NutritionTargetSchedule(versions: [_version('2026-10-01', rest: _rest)]),
  manualKind: manual,
  projection: projection,
);

void main() {
  // Mo Push, Di Pull, Mi Ruhe, Do Beine, Fr Push, Sa/So Ruhe.
  final week = _weekly(['Push', 'Pull', null, 'Beine', 'Push', null, null]);

  group('automaticDayKind', () {
    test('a planned training makes a training day', () {
      expect(
        automaticDayKind(_today, _project(week)),
        NutritionDayKind.training,
      );
    });

    test('a training on a rest day makes a training day', () {
      final restDay = LocalDay(2026, 10, 24);
      expect(automaticDayKind(restDay, _project(week)), NutritionDayKind.rest);
      expect(
        automaticDayKind(
          restDay,
          _project(week, workouts: [_workout(restDay, planId: 'Beine')]),
        ),
        NutritionDayKind.training,
      );
    });

    test('moving a training moves the training day', () {
      final monday = LocalDay(2026, 10, 19);
      final tuesday = LocalDay(2026, 10, 20);
      final moved = week.moveSingle(monday, 'Push', tuesday);
      final projection = _project(moved);
      expect(automaticDayKind(monday, projection), NutritionDayKind.rest);
      expect(automaticDayKind(tuesday, projection), NutritionDayKind.training);
    });

    test('skipping makes a rest day', () {
      expect(
        automaticDayKind(_today, _project(week.skip(_today, 'Beine'))),
        NutritionDayKind.rest,
      );
    });

    test('a missed training still counts as a training day', () {
      final tuesday = LocalDay(2026, 10, 20);
      expect(
        automaticDayKind(tuesday, _project(week)),
        NutritionDayKind.training,
      );
    });

    test('without a schedule only finished workouts count', () {
      expect(automaticDayKind(_today, _project(null)), NutritionDayKind.rest);
      expect(
        automaticDayKind(_today, _project(null, workouts: [_workout(_today)])),
        NutritionDayKind.training,
      );
    });

    test('deleted workouts do not count', () {
      final saturday = LocalDay(2026, 10, 17);
      expect(
        automaticDayKind(
          saturday,
          _project(week, workouts: [_workout(saturday, deleted: true)]),
        ),
        NutritionDayKind.rest,
      );
    });
  });

  group('dayTarget', () {
    test('uses the rest day target on rest days', () {
      final result = _target('2026-10-24', _project(week))!;
      expect(result.target.kilocalories, 2200);
      expect(result.kind, NutritionDayKind.rest);
      expect(result.manual, isFalse);
    });

    test('uses the main target on training days', () {
      final result = _target('2026-10-22', _project(week))!;
      expect(result.target.kilocalories, 2600);
      expect(result.kind, NutritionDayKind.training);
    });

    test('a manual kind wins over the automatic one', () {
      final result = _target(
        '2026-10-22',
        _project(week),
        manual: NutritionDayKind.rest,
      )!;
      expect(result.target.kilocalories, 2200);
      expect(result.manual, isTrue);
    });

    test('without a rest day target the kind does not matter', () {
      final result = _target(
        '2026-10-24',
        _project(week),
        targets: NutritionTargetSchedule(versions: [_version('2026-10-01')]),
        manual: NutritionDayKind.rest,
      )!;
      expect(result.target.kilocalories, 2600);
      expect(result.kind, isNull);
      expect(result.manual, isFalse);
    });

    test('follows the version that applies on the day', () {
      final targets = NutritionTargetSchedule(
        versions: [
          _version('2026-10-01', until: '2026-10-15', kcal: 2400),
          _version('2026-10-16', rest: _rest),
        ],
      );
      // 10.10. ist ein Samstag (Ruhetag), die alte Version kennt keine Ruhe.
      final before = _target('2026-10-10', _project(week), targets: targets)!;
      expect(before.target.kilocalories, 2400);
      expect(before.kind, isNull);
      final after = _target('2026-10-17', _project(week), targets: targets)!;
      expect(after.target.kilocalories, 2200);
      expect(after.kind, NutritionDayKind.rest);
    });

    test(
      'cardio is not part of the projection and never makes a training day',
      () {
        // Cardio-Einheiten sind keine Workouts; ein Ruhetag bleibt Ruhetag.
        expect(
          _target('2026-10-25', _project(week))!.kind,
          NutritionDayKind.rest,
        );
      },
    );

    test('returns null without targets', () {
      expect(
        dayTarget(
          localDate: '2026-10-22',
          targets: null,
          manualKind: null,
          projection: _project(week),
        ),
        isNull,
      );
    });
  });

  test('averages compare each day with its own target', () {
    // Mo 19. Push, Di 20. Pull, Mi 21. Ruhe: 2 Trainingstage, 1 Ruhetag.
    NutritionDay day(String date) => NutritionDay(
      localDate: date,
      entries: [
        NutritionEntry(
          entryId: 'e-$date',
          meal: NutritionMeal.lunch,
          position: 0,
          productName: 'Essen',
          brand: null,
          amountGrams: 100,
          per100Grams: const NutritionTotals(kilocalories: 2600),
          source: null,
        ),
      ],
    );
    final averages = NutritionAverages.compute(
      days: [day('2026-10-19'), day('2026-10-20'), day('2026-10-21')],
      schedule: NutritionTargetSchedule(
        versions: [_version('2026-10-01', rest: _rest)],
      ),
      today: '2026-10-22',
      windowDays: 3,
      projection: _project(week),
    );
    expect(averages.averageTargetKilocalories, closeTo(2466.67, 0.01));
    expect(averages.daysWithinTarget, 2);
    expect(averages.daysWithTarget, 3);
  });

  group('models', () {
    test('day kind and rest day target round-trip through JSON', () {
      final day = NutritionDay(
        localDate: '2026-10-22',
        entries: const [],
        dayKind: NutritionDayKind.rest,
      );
      expect(day.toJson()['dayKind'], 'Rest');
      expect(
        NutritionDay.fromJson(day.toJson()).dayKind,
        NutritionDayKind.rest,
      );
      expect(
        NutritionDay(localDate: '2026-10-22', entries: const []).toJson(),
        isNot(contains('dayKind')),
      );

      final version = _version('2026-10-01', rest: _rest);
      final json = version.toJson();
      expect(json['restDay'], containsPair('kilocalories', 2200.0));
      expect(_version('2026-10-01').toJson(), isNot(contains('restDay')));
    });

    test('an invalid rest day target fails the schedule', () {
      expect(
        () => NutritionTargetSchedule(
          versions: [
            _version(
              '2026-10-01',
              rest: const NutritionDayTarget(
                inputMode: NutritionTargetInputMode.percent,
                kilocalories: 2200,
                proteinGrams: 165,
                carbohydrateGrams: 220,
                fatGrams: 49,
                proteinPercent: 30,
                carbohydratePercent: 40,
                fatPercent: 20,
              ),
            ),
          ],
        ),
        throwsA(
          isA<NutritionValidationException>().having(
            (error) => error.fields.keys,
            'fields',
            contains('versions.0.restDay.percentages'),
          ),
        ),
      );
    });

    test('day mutations keep the chosen day kind', () {
      final entry = NutritionEntry(
        entryId: 'a',
        meal: NutritionMeal.breakfast,
        position: 0,
        productName: 'Hafer',
        brand: null,
        amountGrams: 80,
        per100Grams: const NutritionTotals(kilocalories: 370),
        source: null,
      );
      final day = NutritionDay(
        localDate: '2026-10-22',
        entries: const [],
        dayKind: NutritionDayKind.rest,
      ).replace(entry);
      expect(day.dayKind, NutritionDayKind.rest);
      expect(day.remove('a').dayKind, NutritionDayKind.rest);
    });

    test('a template needs a name and at most 200 entries', () {
      NutritionEntry entry(int index) => NutritionEntry(
        entryId: 'e$index',
        meal: NutritionMeal.snacks,
        position: index,
        productName: 'Nuss',
        brand: null,
        amountGrams: 5,
        per100Grams: const NutritionTotals(kilocalories: 600),
        source: null,
      );
      expect(
        () => NutritionDayTemplate(
          templateId: 't',
          name: ' ',
          dayKind: null,
          entries: [entry(0)],
        ),
        throwsA(isA<NutritionValidationException>()),
      );
      expect(
        () => NutritionDayTemplate(
          templateId: 't',
          name: 'Viel',
          dayKind: null,
          entries: [for (var index = 0; index < 201; index++) entry(index)],
        ),
        throwsA(isA<NutritionValidationException>()),
      );
      final template = NutritionDayTemplate(
        templateId: 't',
        name: 'Ruhetag',
        dayKind: NutritionDayKind.rest,
        entries: [entry(0)],
      );
      final parsed = NutritionDayTemplate.fromJson(template.toJson());
      expect(parsed.dayKind, NutritionDayKind.rest);
      expect(parsed.totals.kilocalories, 30);
    });
  });
}
