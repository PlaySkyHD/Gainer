import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

const accountId = '00000000-0000-4000-8000-000000000001';
String testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

const _training = NutritionDayTarget(
  inputMode: NutritionTargetInputMode.grams,
  kilocalories: 2600,
  proteinGrams: 180,
  carbohydrateGrams: 290,
  fatGrams: 80,
);

const _rest = NutritionDayTarget(
  inputMode: NutritionTargetInputMode.grams,
  kilocalories: 2200,
  proteinGrams: 180,
  carbohydrateGrams: 190,
  fatGrams: 80,
);

NutritionEntry _entry(
  String id,
  NutritionMeal meal,
  int position,
  String name,
) => NutritionEntry(
  entryId: id,
  meal: meal,
  position: position,
  productName: name,
  brand: null,
  amountGrams: 100,
  per100Grams: const NutritionTotals(kilocalories: 150, proteinGrams: 10),
  source: null,
);

void main() {
  late LocalDatabase database;
  late NutritionRepository repository;
  late DateTime now;
  TrainingScheduleProjection? projection;
  var nextId = 10;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    now = DateTime(2026, 10, 22, 9);
    projection = null;
    repository = NutritionRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
      ids: () => testId(nextId++),
      clock: () => now,
      scheduleProjection: () async =>
          projection ??
          TrainingScheduleProjection(
            schedule: null,
            plans: const [],
            workouts: const [],
            today: LocalDay.of(now),
          ),
    );
  });

  tearDown(() => database.close());

  Future<List<NutritionTargetVersion>> versions() async =>
      (await repository.read('2026-10-22')).targetSchedule?.versions ??
      const [];

  group('saveTargets', () {
    test('first targets start today', () async {
      await repository.saveTargets(
        training: _training,
        restDay: _rest,
        saltGrams: null,
        fiberGrams: null,
      );
      final saved = await versions();
      expect(saved, hasLength(1));
      expect(saved.single.effectiveFrom, '2026-10-22');
      expect(saved.single.effectiveUntil, isNull);
      expect(saved.single.name, 'Ziele');
      expect(saved.single.restDay?.kilocalories, 2200);
    });

    test(
      'a change on a later day ends the previous version yesterday',
      () async {
        now = DateTime(2026, 10, 1, 9);
        await repository.saveTargets(
          training: _training,
          restDay: null,
          saltGrams: null,
          fiberGrams: null,
        );
        now = DateTime(2026, 10, 22, 9);
        await repository.saveTargets(
          training: _training,
          restDay: _rest,
          saltGrams: 5,
          fiberGrams: null,
        );
        final saved = await versions();
        expect(
          [for (final v in saved) (v.effectiveFrom, v.effectiveUntil)],
          [('2026-10-01', '2026-10-21'), ('2026-10-22', null)],
        );
        expect(saved.last.saltGrams, 5);
      },
    );

    test('a second change on the same day replaces today\'s version', () async {
      await repository.saveTargets(
        training: _training,
        restDay: _rest,
        saltGrams: null,
        fiberGrams: null,
      );
      final first = (await versions()).single.targetVersionId;
      await repository.saveTargets(
        training: const NutritionDayTarget(
          inputMode: NutritionTargetInputMode.grams,
          kilocalories: 2550,
          proteinGrams: 180,
          carbohydrateGrams: 280,
          fatGrams: 80,
        ),
        restDay: null,
        saltGrams: null,
        fiberGrams: null,
      );
      final saved = await versions();
      expect(saved, hasLength(1));
      expect(saved.single.targetVersionId, first);
      expect(saved.single.kilocalories, 2550);
      expect(saved.single.restDay, isNull);
      final outbox = await repository.store.readOutbox(
        aggregateType: 'nutrition-target-schedule',
      );
      expect((outbox.last.body! as Map)['versions'], hasLength(1));
    });

    test(
      'old phases: the running one is cut, a planned one is dropped',
      () async {
        NutritionTargetVersion phase(String id, String from, String? until) =>
            NutritionTargetVersion(
              targetVersionId: id,
              name: 'Phase $id',
              category: NutritionTargetCategory.cut,
              effectiveFrom: from,
              effectiveUntil: until,
              inputMode: NutritionTargetInputMode.grams,
              kilocalories: 2400,
              proteinGrams: 180,
              carbohydrateGrams: 240,
              fatGrams: 80,
              proteinPercent: null,
              carbohydratePercent: null,
              fatPercent: null,
            );
        await repository.saveTargetSchedule(
          NutritionTargetSchedule(
            versions: [
              phase('a', '2026-10-01', '2026-11-29'),
              phase('b', '2026-11-30', null),
            ],
          ),
        );
        await repository.saveTargets(
          training: _training,
          restDay: _rest,
          saltGrams: null,
          fiberGrams: null,
        );
        final saved = await versions();
        expect(saved, hasLength(2));
        expect(saved.first.targetVersionId, 'a');
        expect(saved.first.effectiveUntil, '2026-10-21');
        expect(saved.last.targetVersionId, isNot('b'));
        expect(saved.last.effectiveFrom, '2026-10-22');
        expect(saved.last.effectiveUntil, isNull);
      },
    );

    test(
      'introducing a rest day target keeps earlier days unchanged',
      () async {
        now = DateTime(2026, 10, 1, 9);
        await repository.saveTargets(
          training: _training,
          restDay: null,
          saltGrams: null,
          fiberGrams: null,
        );
        await repository.saveEntry(
          '2026-10-20',
          _entry(testId(900), NutritionMeal.lunch, 0, 'Reis'),
        );
        now = DateTime(2026, 10, 22, 9);
        await repository.saveTargets(
          training: _training,
          restDay: _rest,
          saltGrams: null,
          fiberGrams: null,
        );

        final earlier = await repository.read('2026-10-20');
        expect(earlier.dayTarget?.target.kilocalories, 2600);
        expect(earlier.dayTarget?.kind, isNull);
        final later = await repository.read('2026-10-24');
        expect(later.dayTarget?.target.kilocalories, 2200);
        expect(later.dayTarget?.kind, NutritionDayKind.rest);
      },
    );
  });

  group('day kind', () {
    test(
      'offline choice and a meal on the same day give one waiting state',
      () async {
        await repository.saveTargets(
          training: _training,
          restDay: _rest,
          saltGrams: null,
          fiberGrams: null,
        );
        await repository.setDayKind('2026-10-23', NutritionDayKind.rest);
        await repository.saveEntry(
          '2026-10-23',
          _entry(testId(901), NutritionMeal.dinner, 0, 'Hähnchen'),
        );
        final outbox = await repository.store.readOutbox(
          aggregateType: 'nutrition-day',
        );
        expect(outbox, hasLength(1));
        expect(outbox.single.body, containsPair('dayKind', 'Rest'));
        final day = await repository.read('2026-10-23');
        expect(day.day.dayKind, NutritionDayKind.rest);
        expect(day.dayTarget?.manual, isTrue);
      },
    );

    test('resetting keeps the day and clears the kind', () async {
      await repository.setDayKind('2026-10-23', NutritionDayKind.training);
      await repository.setDayKind('2026-10-23', null);
      final rows = await repository.store.readAggregates('nutrition-day');
      expect(rows, hasLength(1));
      expect((rows.single.workingCopy! as Map)['dayKind'], isNull);
      expect((await repository.read('2026-10-23')).day.dayKind, isNull);
    });

    test('a schedule makes planned days training days', () async {
      await repository.saveTargets(
        training: _training,
        restDay: _rest,
        saltGrams: null,
        fiberGrams: null,
      );
      projection = TrainingScheduleProjection(
        schedule: TrainingSchedule.create(
          scheduleId: 's',
          mode: TrainingScheduleMode.weekly,
          slots: [
            for (final id in ['Push', null, null, 'Push', null, null, null])
              TrainingScheduleSlot(planId: id),
          ],
          today: LocalDay(2026, 10, 1),
        ),
        plans: [
          TrainingPlanModel(
            planId: 'Push',
            name: 'Push',
            previousValueSource: PreviousValueSource.exercise,
          ),
        ],
        workouts: const [],
        today: LocalDay(2026, 10, 22),
      );
      final thursday = await repository.read('2026-10-22');
      expect(thursday.dayTarget?.kind, NutritionDayKind.training);
      expect(thursday.automaticDayKind, NutritionDayKind.training);
      final friday = await repository.read('2026-10-23');
      expect(friday.dayTarget?.target.kilocalories, 2200);
    });
  });

  group('day templates', () {
    Future<void> fillToday() async {
      await repository.saveEntry(
        '2026-10-22',
        _entry(testId(500), NutritionMeal.breakfast, 0, 'Haferflocken'),
      );
      await repository.saveEntry(
        '2026-10-22',
        _entry(testId(501), NutritionMeal.lunch, 0, 'Reis'),
      );
      await repository.saveEntry(
        '2026-10-22',
        _entry(testId(502), NutritionMeal.lunch, 1, 'Hähnchen'),
      );
    }

    test('saving copies the entries with new ids', () async {
      await fillToday();
      final id = await repository.saveDayAsTemplate(
        '2026-10-22',
        name: 'Trainingstag',
        dayKind: NutritionDayKind.training,
      );
      final template = (await repository.readTemplates()).single;
      expect(template.templateId, id);
      expect(template.name, 'Trainingstag');
      expect(template.entries.map((e) => e.productName), [
        'Haferflocken',
        'Reis',
        'Hähnchen',
      ]);
      expect(
        template.entries.map((e) => e.entryId),
        isNot(containsAll([testId(500), testId(501), testId(502)])),
      );
    });

    test('an empty day cannot become a template', () async {
      expect(
        () => repository.saveDayAsTemplate('2026-10-22', name: 'Leer'),
        throwsA(isA<NutritionValidationException>()),
      );
    });

    test('applying to an empty day copies the entries', () async {
      await fillToday();
      final id = await repository.saveDayAsTemplate(
        '2026-10-22',
        name: 'Trainingstag',
      );
      await repository.applyTemplate(id, '2026-10-23');
      final day = (await repository.read('2026-10-23')).day;
      expect(day.entries.map((e) => (e.meal, e.position, e.productName)), [
        (NutritionMeal.breakfast, 0, 'Haferflocken'),
        (NutritionMeal.lunch, 0, 'Reis'),
        (NutritionMeal.lunch, 1, 'Hähnchen'),
      ]);
    });

    test('replace and append on a filled day, keeping the day kind', () async {
      await fillToday();
      final id = await repository.saveDayAsTemplate(
        '2026-10-22',
        name: 'Trainingstag',
      );
      await repository.saveEntry(
        '2026-10-23',
        _entry(testId(600), NutritionMeal.breakfast, 0, 'Kaffee'),
      );
      await repository.setDayKind('2026-10-23', NutritionDayKind.rest);

      await repository.applyTemplate(
        id,
        '2026-10-23',
        mode: TemplateApplyMode.append,
      );
      var day = (await repository.read('2026-10-23')).day;
      expect(day.entries, hasLength(4));
      expect(
        day.entries
            .where((e) => e.meal == NutritionMeal.breakfast)
            .map((e) => e.productName),
        ['Kaffee', 'Haferflocken'],
      );
      expect(day.dayKind, NutritionDayKind.rest);

      await repository.applyTemplate(
        id,
        '2026-10-23',
        mode: TemplateApplyMode.replace,
      );
      day = (await repository.read('2026-10-23')).day;
      expect(day.entries, hasLength(3));
      expect(day.entries.any((e) => e.productName == 'Kaffee'), isFalse);
      expect(day.dayKind, NutritionDayKind.rest);
    });

    test('applying refuses more than 200 entries per day', () async {
      await fillToday();
      final id = await repository.saveDayAsTemplate(
        '2026-10-22',
        name: 'Trainingstag',
      );
      for (var index = 0; index < 198; index++) {
        await repository.saveEntry(
          '2026-10-24',
          _entry(testId(1000 + index), NutritionMeal.snacks, index, 'Nuss'),
        );
      }
      expect(
        () => repository.applyTemplate(id, '2026-10-24'),
        throwsA(isA<NutritionValidationException>()),
      );
      expect((await repository.read('2026-10-24')).day.entries, hasLength(198));
    });

    test(
      'overwriting keeps name and kind; applied days stay unchanged',
      () async {
        await fillToday();
        final id = await repository.saveDayAsTemplate(
          '2026-10-22',
          name: 'Ruhetag',
          dayKind: NutritionDayKind.rest,
        );
        await repository.applyTemplate(id, '2026-10-21');
        await repository.removeEntry('2026-10-22', testId(500));
        await repository.saveDayAsTemplate('2026-10-22', overwriteId: id);

        final template = (await repository.readTemplates()).single;
        expect(template.name, 'Ruhetag');
        expect(template.dayKind, NutritionDayKind.rest);
        expect(template.entries, hasLength(2));
        expect((await repository.read('2026-10-21')).day.entries, hasLength(3));
      },
    );

    test('updating a template renumbers positions per meal', () async {
      await fillToday();
      final id = await repository.saveDayAsTemplate('2026-10-22', name: 'Alt');
      await repository.applyTemplate(id, '2026-10-23');
      final template = (await repository.readTemplates()).single;
      final lunch = template.entries.where(
        (e) => e.meal == NutritionMeal.lunch,
      );
      await repository.updateTemplate(
        id,
        name: 'Neu',
        dayKind: NutritionDayKind.rest,
        entries: [
          lunch.last,
          template.entries.first.copyWith(meal: NutritionMeal.lunch),
        ],
      );
      final updated = (await repository.readTemplates()).single;
      expect(updated.name, 'Neu');
      expect(updated.dayKind, NutritionDayKind.rest);
      expect(
        [for (final e in updated.entries) (e.meal, e.position, e.productName)],
        [
          (NutritionMeal.lunch, 0, 'Hähnchen'),
          (NutritionMeal.lunch, 1, 'Haferflocken'),
        ],
      );
      expect((await repository.read('2026-10-23')).day.entries, hasLength(3));
    });

    test('deleting an unsent template removes it without a mutation', () async {
      await fillToday();
      final id = await repository.saveDayAsTemplate('2026-10-22', name: 'Weg');
      await repository.applyTemplate(id, '2026-10-23');
      await repository.deleteTemplate(id);
      expect(await repository.readTemplates(), isEmpty);
      expect((await repository.read('2026-10-23')).day.entries, hasLength(3));
      expect(
        await repository.store.readOutbox(
          aggregateType: 'nutrition-day-template',
        ),
        isEmpty,
      );
    });

    test(
      'suggests the latest template matching the kind of an empty day',
      () async {
        await fillToday();
        await repository.saveDayAsTemplate(
          '2026-10-22',
          name: 'Ruhe alt',
          dayKind: NutritionDayKind.rest,
        );
        now = DateTime(2026, 10, 22, 10);
        await repository.saveDayAsTemplate(
          '2026-10-22',
          name: 'Ruhe neu',
          dayKind: NutritionDayKind.rest,
        );
        await repository.saveDayAsTemplate(
          '2026-10-22',
          name: 'Training',
          dayKind: NutritionDayKind.training,
        );
        // Ohne Rhythmus ist morgen ein Ruhetag.
        expect(
          (await repository.read('2026-10-23')).suggestedTemplate?.name,
          'Ruhe neu',
        );
        // Gefüllter Tag und vergangener Tag: kein Vorschlag.
        expect((await repository.read('2026-10-22')).suggestedTemplate, isNull);
        expect((await repository.read('2026-10-20')).suggestedTemplate, isNull);
      },
    );

    test('at most 50 templates', () async {
      await fillToday();
      for (var index = 0; index < NutritionDayTemplate.maxTemplates; index++) {
        await repository.saveDayAsTemplate('2026-10-22', name: 'V$index');
      }
      expect(
        () => repository.saveDayAsTemplate('2026-10-22', name: 'Zu viel'),
        throwsA(isA<NutritionValidationException>()),
      );
    });
  });
}
