import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
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

  /// Ein Pull ersetzt den Tag, wie nach einer Serverbestätigung.
  Future<void> pull(
    int version, {
    List<NutritionEntry> entries = const [],
  }) async {
    final row = (await repository.store.readAggregates('nutrition-day')).single;
    final snapshot = Map<String, Object?>.from(row.workingCopy! as Map)
      ..['entries'] = [for (final entry in entries) entry.toJson()];
    await database
        .into(database.localResources)
        .insertOnConflictUpdate(
          LocalResourcesCompanion.insert(
            aggregateType: 'nutrition-day',
            aggregateId: row.aggregateId,
            envelopeJson: serverEnvelope(
              aggregateId: row.aggregateId,
              snapshot: snapshot,
              version: version,
            ).encode(),
            updatedAtEpochMs: 0,
          ),
        );
    await database.delete(database.localOutbox).go();
  }

  test('a pull between reading and writing is respected on retry', () async {
    await repository.saveEntry(
      '2026-10-12',
      _entry(1, NutritionMeal.breakfast, 1),
    );
    var pulled = false;
    repository.beforeDayCommitForTesting = () async {
      if (pulled) return;
      pulled = true;
      await pull(
        1,
        entries: [
          _entry(1, NutritionMeal.breakfast, 1),
          _entry(7, NutritionMeal.lunch, 1),
        ],
      );
    };

    await repository.saveEntry(
      '2026-10-12',
      _entry(2, NutritionMeal.breakfast, 2),
    );

    final ids = (await repository.read('2026-10-12')).day.entries
        .map((entry) => entry.entryId);
    expect(ids, containsAll([_id(1), _id(2), _id(7)]));
  });

  test('a pull of the server day under another id between reading and '
      'creating changes the server day (#298)', () async {
    final serverId = _id(900);
    var pulled = false;
    repository.beforeDayCommitForTesting = () async {
      if (pulled) return;
      pulled = true;
      // Der Pull schreibt den Servertag desselben Datums unter eigener ID.
      await database
          .into(database.localResources)
          .insert(
            LocalResourcesCompanion.insert(
              aggregateType: 'nutrition-day',
              aggregateId: serverId,
              envelopeJson: serverEnvelope(
                aggregateId: serverId,
                snapshot: NutritionDay(
                  localDate: '2026-10-12',
                  entries: [_entry(7, NutritionMeal.breakfast, 0)],
                ).toJson(),
                version: 3,
              ).encode(),
              updatedAtEpochMs: 0,
            ),
          );
    };

    await repository.saveEntry(
      '2026-10-12',
      _entry(2, NutritionMeal.breakfast, 0),
    );

    final rows = await repository.store.readAggregates('nutrition-day');
    expect(rows.map((row) => row.aggregateId), [serverId]);
    final waiting = (await repository.store.readOutbox(
      aggregateType: 'nutrition-day',
    )).single;
    expect(waiting.aggregateId, serverId);
    expect(waiting.operation, LocalMutationOperation.update);
    expect(waiting.baseVersion, 3);
    final ids = (await repository.read('2026-10-12')).day.entries
        .map((entry) => entry.entryId);
    expect(ids, [_id(7), _id(2)]);
  });

  test('a day that keeps changing gives up with a German message', () async {
    await repository.saveEntry(
      '2026-10-12',
      _entry(1, NutritionMeal.breakfast, 1),
    );
    var version = 0;
    repository.beforeDayCommitForTesting = () => pull(++version);

    await expectLater(
      repository.saveEntry('2026-10-12', _entry(2, NutritionMeal.lunch, 1)),
      throwsA(
        isA<NutritionSaveException>().having(
          (error) => error.toString(),
          'message',
          'Der Tag hat sich gerade beim Synchronisieren geändert. '
              'Bitte versuche es noch einmal.',
        ),
      ),
    );
    expect(version, 3);
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
