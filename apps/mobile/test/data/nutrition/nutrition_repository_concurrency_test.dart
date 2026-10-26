import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/bls_food_catalog.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';

const _accountId = '00000000-0000-4000-8000-000000000001';

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

NutritionEntry _entry(int value, NutritionMeal meal, int position) =>
    NutritionEntry(
      entryId: _id(value),
      meal: meal,
      position: position,
      productName: 'Eintrag $value',
      brand: null,
      amountGrams: 100,
      per100Grams: const NutritionTotals(kilocalories: 100),
      source: null,
    );

void main() {
  late LocalDatabase database;
  late NutritionRepository repository;
  var nextId = 100;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    repository = NutritionRepository(
      store: LocalSyncStore(database: database, accountId: _accountId),
      ids: () => _id(nextId++),
      clock: () => DateTime.utc(2026, 10, 12, 9),
    );
  });

  tearDown(() => database.close());

  test(
    'two parallel saveEntry calls on the same day keep both entries',
    () async {
      await Future.wait([
        repository.saveEntry(
          '2026-10-12',
          _entry(1, NutritionMeal.breakfast, 1),
        ),
        repository.saveEntry(
          '2026-10-12',
          _entry(2, NutritionMeal.breakfast, 2),
        ),
      ]);

      final day = (await repository.read('2026-10-12')).day;
      expect(day.entries.map((entry) => entry.entryId), {_id(1), _id(2)});
    },
  );

  test('parallel save, move and remove on one day do not lose edits', () async {
    await repository.saveEntry(
      '2026-10-12',
      _entry(1, NutritionMeal.breakfast, 1),
    );
    await repository.saveEntry(
      '2026-10-12',
      _entry(2, NutritionMeal.breakfast, 2),
    );

    await Future.wait([
      repository.saveEntry('2026-10-12', _entry(3, NutritionMeal.lunch, 1)),
      repository.removeEntry('2026-10-12', _id(1)),
      repository.moveEntry('2026-10-12', _id(2), NutritionMeal.dinner, 0),
    ]);

    final entries = (await repository.read('2026-10-12')).day.entries;
    expect(entries.map((entry) => entry.entryId).toSet(), {_id(2), _id(3)});
    expect(
      entries.singleWhere((entry) => entry.entryId == _id(2)).meal,
      NutritionMeal.dinner,
    );
  });

  test('a failed queued action does not block the following ones', () async {
    final failing = repository.moveEntry(
      '2026-10-12',
      _id(9),
      NutritionMeal.lunch,
      1,
    );
    await expectLater(failing, throwsA(anything));
    await repository.saveEntry(
      '2026-10-12',
      _entry(1, NutritionMeal.breakfast, 1),
    );

    expect((await repository.read('2026-10-12')).day.entries, hasLength(1));
  });

  test('the BLS catalog retries after a failed load', () async {
    final bundle = _FlakyBundle();
    final catalog = BlsFoodCatalog(bundle: bundle);

    await expectLater(catalog.search('Apfel'), throwsA(anything));
    bundle.failing = false;
    final result = await catalog.search('Apfel');

    expect(result.foods, isNotEmpty);
    expect(bundle.loads, 2);
  });
}

class _FlakyBundle extends AssetBundle {
  bool failing = true;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(_catalog)));

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loads++;
    if (failing) throw StateError('asset missing');
    return _catalog;
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}

const _catalog = '{"foods": [["B1", "Apfel", 52, 0.3, 14, 0.2, 2, 0]]}';
