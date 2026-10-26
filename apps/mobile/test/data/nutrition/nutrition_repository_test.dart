import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';

const accountId = '00000000-0000-4000-8000-000000000001';
String testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

void main() {
  late LocalDatabase database;
  late NutritionRepository repository;
  var nextId = 10;
  var closed = false;
  final now = DateTime.utc(2026, 10, 12, 9);

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    closed = false;
    repository = NutritionRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
      ids: () => testId(nextId++),
      clock: () => now,
    );
  });

  tearDown(() async {
    if (!closed) await database.close();
  });

  test(
    'creates an empty four-meal day without persisting until a user edit',
    () async {
      final value = await repository.read('2026-10-12');
      expect(value.day.entries, isEmpty);
      expect((await repository.store.readAggregates('nutrition-day')), isEmpty);
      expect(NutritionMeal.values, hasLength(4));
    },
  );

  test('a diary edit atomically persists a local envelope and exact nutrition mutation', () async {
    await repository.saveEntry(
      '2026-10-12',
      NutritionEntry(
        entryId: testId(50),
        meal: NutritionMeal.breakfast,
        position: 0,
        productName: 'Hafer',
        brand: 'Mühle',
        amountGrams: 50,
        per100Grams: const NutritionTotals(kilocalories: 370, proteinGrams: 13),
        source: null,
      ),
    );
    final day = await repository.read('2026-10-12');
    expect(day.day.totals.kilocalories, 185);
    expect(day.day.totals.proteinGrams, 6.5);
    final outbox = await repository.store.readOutbox(
      aggregateType: 'nutrition-day',
    );
    expect(outbox, hasLength(1));
    expect(outbox.single.operation.name, 'create');
    expect(outbox.single.body, containsPair('localDate', '2026-10-12'));
    expect(outbox.single.body, containsPair('entries', isA<List<dynamic>>()));
  });

  test('move/delete maintain stable day identity and one waiting aggregate mutation', () async {
    final one = NutritionEntry(
      entryId: testId(50),
      meal: NutritionMeal.breakfast,
      position: 0,
      productName: 'Apfel',
      brand: null,
      amountGrams: 120,
      per100Grams: const NutritionTotals(kilocalories: 52),
      source: null,
    );
    final two = NutritionEntry(
      entryId: testId(51),
      meal: NutritionMeal.breakfast,
      position: 1,
      productName: 'Joghurt',
      brand: null,
      amountGrams: 100,
      per100Grams: const NutritionTotals(kilocalories: 65),
      source: null,
    );
    await repository.saveEntry('2026-10-12', one);
    await repository.saveEntry('2026-10-12', two);
    final id = (await repository.store.readAggregates('nutrition-day'))
        .single
        .aggregateId;
    await repository.moveEntry(
      '2026-10-12',
      two.entryId,
      NutritionMeal.snacks,
      0,
    );
    await repository.removeEntry('2026-10-12', one.entryId);
    final result = await repository.read('2026-10-12');
    expect(
      (await repository.store.readAggregates('nutrition-day'))
          .single
          .aggregateId,
      id,
    );
    expect(result.day.entries.single.entryId, two.entryId);
    expect(result.day.entries.single.meal, NutritionMeal.snacks);
    expect(
      (await repository.store.readOutbox(aggregateType: 'nutrition-day'))
          .map((m) => m.sequence),
      // Vier lokale Änderungen vor dem Senden bleiben ein wartender Eintrag.
      [1],
    );
  });

  test(
    'copying a reusable meal makes fresh diary IDs and scales snapshots',
    () async {
      final mealId = await repository.saveReusableMeal(
        ReusableMeal(
          name: 'Porridge',
          description: null,
          standardPortion: 1.5,
          components: [
            ReusableMealComponent(
              componentId: testId(60),
              position: 0,
              name: 'Hafer',
              brand: null,
              amountGrams: 40,
              per100Grams: const NutritionTotals(
                kilocalories: 370,
                proteinGrams: 13,
              ),
              source: NutritionSource(
                provider: 'OpenFoodFacts',
                barcode: '12345678',
                retrievedAtUtc: now,
                basisGrams: 100,
              ),
            ),
          ],
        ),
      );
      await repository.copyReusableMealToDay(
        mealId: mealId,
        localDate: '2026-10-12',
        meal: NutritionMeal.lunch,
      );
      final copied = (await repository.read('2026-10-12')).day.entries.single;
      expect(copied.entryId, isNot(testId(60)));
      expect(copied.productName, 'Hafer');
      expect(copied.amountGrams, 60);
      expect(copied.totals.kilocalories, 222);
      expect(copied.source?.barcode, '12345678');
    },
  );

  test('archived reusable meal is read-only and cannot be copied', () async {
    final id = await repository.saveReusableMeal(
      ReusableMeal(
        name: 'Shake',
        description: null,
        standardPortion: 1,
        components: [
          ReusableMealComponent(
            componentId: testId(60),
            position: 0,
            name: 'Milch',
            brand: null,
            amountGrams: 200,
            per100Grams: const NutritionTotals(kilocalories: 60),
            source: null,
          ),
        ],
      ),
    );
    await repository.archiveReusableMeal(id);
    expect(
      (await repository.read('2026-10-12')).meals.single.value.status,
      'Archived',
    );
    await expectLater(
      repository.copyReusableMealToDay(
        mealId: id,
        localDate: '2026-10-12',
        meal: NutritionMeal.breakfast,
      ),
      throwsStateError,
    );
  });

  test('file-backed diary survives close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gainer-nutrition-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}nutrition.sqlite',
    );
    try {
      final firstDatabase = LocalDatabase(NativeDatabase(file));
      final first = NutritionRepository(
        store: LocalSyncStore(database: firstDatabase, accountId: accountId),
        ids: () => testId(80),
        clock: () => now,
      );
      await first.saveEntry(
        '2026-10-12',
        NutritionEntry(
          entryId: testId(81),
          meal: NutritionMeal.dinner,
          position: 0,
          productName: 'Reis',
          brand: null,
          amountGrams: 150,
          per100Grams: const NutritionTotals(kilocalories: 130),
          source: null,
        ),
      );
      await first.store.close();
      final reopenedDatabase = LocalDatabase(NativeDatabase(file));
      final reopened = NutritionRepository(
        store: LocalSyncStore(database: reopenedDatabase, accountId: accountId),
        ids: () => testId(82),
        clock: () => now,
      );
      expect(
        (await reopened.read('2026-10-12')).day.entries.single.productName,
        'Reis',
      );
      expect(
        await reopened.store.readOutbox(aggregateType: 'nutrition-day'),
        hasLength(1),
      );
      await reopened.store.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  group('label scan confirmation', () {
    NutritionLabelFieldDraft field(double? per100) => NutritionLabelFieldDraft(
      originalValue: per100,
      per100Grams: per100,
      status: per100 == null ? 'Missing' : 'Read',
      evidence: per100 == null ? null : '$per100',
    );

    NutritionLabelScanDraft draft({
      required double? kcal,
      bool canConfirm = true,
    }) => NutritionLabelScanDraft(
      basis: 'Per100Grams',
      servingMassGrams: null,
      kilocalories: field(kcal),
      proteinGrams: field(null),
      carbohydrateGrams: field(null),
      fatGrams: field(null),
      canConfirm: canConfirm,
      provider: 'OpenAI',
      providerModelVersion: 'model',
      parserVersion: 'nutrition-label-v1',
      scannedAtUtc: now,
    );

    test('accepts 0 kcal per 100 g, e.g. a zero drink', () {
      final totals = draft(kcal: 0).confirmedPer100Grams;
      expect(totals, isNotNull);
      expect(totals!.kilocalories, 0);
    });

    test('rejects negative, non-finite and missing energy', () {
      expect(draft(kcal: -1).confirmedPer100Grams, isNull);
      expect(draft(kcal: double.nan).confirmedPer100Grams, isNull);
      expect(draft(kcal: double.infinity).confirmedPer100Grams, isNull);
      expect(draft(kcal: null).confirmedPer100Grams, isNull);
      expect(draft(kcal: 0, canConfirm: false).confirmedPer100Grams, isNull);
    });
  });
}
