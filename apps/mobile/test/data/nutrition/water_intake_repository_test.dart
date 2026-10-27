import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_preferences.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/water_intake_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';

const _accountId = '00000000-0000-4000-8000-000000000071';
const _otherAccountId = '00000000-0000-4000-8000-000000000072';
const _day = '2026-10-25';

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  late WaterIntakeRepository water;
  var next = 0;

  String id() =>
      '00000000-0000-4000-8000-${(++next).toString().padLeft(12, '0')}';

  setUp(() {
    next = 100;
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _accountId);
    water = WaterIntakeRepository(
      store: store,
      ids: id,
      clock: () => DateTime.utc(2026, 10, 25, 9),
    );
  });

  tearDown(() => database.close());

  Future<List<LocalMutation>> outbox() =>
      store.readOutbox(aggregateType: waterIntakeAggregateType);

  String operationOf(LocalMutation mutation) =>
      SyncPayloadCodec.serverOperation(
        mutation,
        mutation.body! as Map<String, dynamic>,
      );

  Map<String, dynamic> payloadOf(LocalMutation mutation) =>
      SyncPayloadCodec.serverPayload(
            mutation,
            mutation.body! as Map<String, dynamic>,
            mutation.baseVersion ?? 0,
          )!
          as Map<String, dynamic>;

  /// Bestätigt einen Stand wie ein Pull: saubere Serverkopie, leere Outbox.
  Future<void> confirm(int version, {int? amountMl}) async {
    final dayId = water.dayIdFor(_day);
    final row = await store.readAggregate(waterIntakeAggregateType, dayId);
    final snapshot = Map<String, Object?>.from(row!.workingCopy! as Map);
    if (amountMl != null) snapshot['amountMl'] = amountMl;
    await database
        .into(database.localResources)
        .insertOnConflictUpdate(
          LocalResourcesCompanion.insert(
            aggregateType: waterIntakeAggregateType,
            aggregateId: dayId,
            envelopeJson: serverEnvelope(
              aggregateId: dayId,
              snapshot: snapshot,
              version: version,
            ).encode(),
            updatedAtEpochMs: 0,
          ),
        );
    await database.delete(database.localOutbox).go();
  }

  test('the first change creates the day under its fixed id', () async {
    expect(await water.read(_day), 0);

    expect(await water.add(_day, 300), 300);

    expect(await water.read(_day), 300);
    final mutation = (await outbox()).single;
    expect(mutation.aggregateId, waterIntakeDayId(_accountId, _day));
    expect(mutation.operation, LocalMutationOperation.create);
    expect(operationOf(mutation), 'setWaterIntake');
    expect(payloadOf(mutation), {
      'waterIntakeDayId': mutation.aggregateId,
      'localDate': _day,
      'baseVersion': 0,
      'amountMl': 300,
    });
    expect((mutation.body! as Map).containsKey('addedMl'), isFalse);
  });

  test('offline taps merge into one waiting total', () async {
    await water.add(_day, 500);
    await water.add(_day, 500);
    await water.add(_day, 300);

    expect(await water.read(_day), 1300);
    final mutation = (await outbox()).single;
    expect(mutation.operation, LocalMutationOperation.create);
    expect(operationOf(mutation), 'setWaterIntake');
    expect(payloadOf(mutation)['amountMl'], 1300);
    expect(payloadOf(mutation)['baseVersion'], 0);
  });

  test('quick taps in parallel are queued and none is lost', () async {
    final totals = await Future.wait([
      water.add(_day, 200),
      water.add(_day, 300),
      water.add(_day, 500),
    ]);

    expect(totals, [200, 500, 1000]);
    expect(await water.read(_day), 1000);
    expect(await store.readAggregates(waterIntakeAggregateType), hasLength(1));
  });

  test('a confirmed day is changed from its server version', () async {
    await water.add(_day, 500);
    await confirm(3);

    expect(await water.add(_day, 200), 700);
    final added = (await outbox()).single;
    expect(added.operation, LocalMutationOperation.update);
    expect(operationOf(added), 'setWaterIntake');
    expect(payloadOf(added), containsPair('baseVersion', 3));
    expect(payloadOf(added), containsPair('amountMl', 700));

    await confirm(4);
    expect(await water.setAmount(_day, 250), 250);
    final corrected = (await outbox()).single;
    expect(payloadOf(corrected), containsPair('baseVersion', 4));
    expect(payloadOf(corrected), containsPair('amountMl', 250));
  });

  test('an ack between reading and writing is not overwritten', () async {
    await water.add(_day, 500);
    var acked = false;
    water.beforeCommitForTesting = () async {
      if (acked) return;
      acked = true;
      // Der Server bestätigt den wartenden Stand, während getippt wird.
      await confirm(1);
    };

    expect(await water.add(_day, 200), 700);

    final mutation = (await outbox()).single;
    expect(mutation.operation, LocalMutationOperation.update);
    expect(mutation.baseVersion, 1);
    expect(payloadOf(mutation)['amountMl'], 700);
    final envelope = await store.readAggregate(
      waterIntakeAggregateType,
      water.dayIdFor(_day),
    );
    expect(envelope!.serverVersion, 1);
    expect(envelope.syncState, LocalSyncState.pending);
  });

  test(
    'a pull with another total between reading and writing is respected',
    () async {
      await water.add(_day, 500);
      await confirm(1);
      var pulled = false;
      water.beforeCommitForTesting = () async {
        if (pulled) return;
        pulled = true;
        await confirm(2, amountMl: 900);
      };

      expect(await water.add(_day, 200), 1100);
      final mutation = (await outbox()).single;
      expect(mutation.baseVersion, 2);
      expect(payloadOf(mutation)['amountMl'], 1100);
    },
  );

  test('a pull of the server day under another id between reading and '
      'creating changes the server day (#298)', () async {
    const serverId = '00000000-0000-4000-8000-000000000900';
    var pulled = false;
    water.beforeCommitForTesting = () async {
      if (pulled) return;
      pulled = true;
      // Der Pull schreibt den Servertag desselben Datums unter eigener ID,
      // etwa von einer älteren App-Version angelegt.
      await database
          .into(database.localResources)
          .insert(
            LocalResourcesCompanion.insert(
              aggregateType: waterIntakeAggregateType,
              aggregateId: serverId,
              envelopeJson: serverEnvelope(
                aggregateId: serverId,
                snapshot: const {
                  'localDate': _day,
                  'amountMl': 900,
                  'createdAtUtc': '2026-10-25T06:00:00Z',
                  'updatedAtUtc': '2026-10-25T06:00:00Z',
                },
                version: 3,
              ).encode(),
              updatedAtEpochMs: 0,
            ),
          );
    };

    expect(await water.add(_day, 200), 1100);

    final rows = await store.readAggregates(waterIntakeAggregateType);
    expect(rows.map((row) => row.aggregateId), [serverId]);
    final mutation = (await outbox()).single;
    expect(mutation.aggregateId, serverId);
    expect(mutation.operation, LocalMutationOperation.update);
    expect(payloadOf(mutation), containsPair('baseVersion', 3));
    expect(payloadOf(mutation), containsPair('amountMl', 1100));
    expect(await water.read(_day), 1100);
  });

  test('a day that keeps changing gives up after a few attempts', () async {
    await water.add(_day, 500);
    var version = 0;
    water.beforeCommitForTesting = () => confirm(++version);

    await expectLater(
      water.add(_day, 200),
      throwsA(
        isA<WaterIntakeSaveException>().having(
          (error) => error.toString(),
          'message',
          'Die Wassermenge hat sich gerade beim Synchronisieren geändert. '
              'Bitte versuche es noch einmal.',
        ),
      ),
    );
    expect(version, 3);
    expect(await outbox(), isEmpty);

    // The queue keeps working afterwards.
    water.beforeCommitForTesting = null;
    expect(await water.add(_day, 100), 600);
  });

  test('frozen edits during a handover give a German message', () async {
    // Wie während einer Übergabe; der Schlüssel ist für Aufrufer gesperrt.
    await database
        .into(database.localSyncMetadata)
        .insertOnConflictUpdate(
          LocalSyncMetadataCompanion.insert(
            key: 'local-writes-frozen',
            valueJson: 'true',
          ),
        );

    await expectLater(
      water.add(_day, 200),
      throwsA(
        isA<WaterIntakeSaveException>().having(
          (error) => error.message,
          'message',
          startsWith('Während der Geräteübergabe'),
        ),
      ),
    );
    expect(await water.read(_day), 0);
    expect(await outbox(), isEmpty);
  });

  test(
    'setting zero keeps the day and an unchanged value writes nothing',
    () async {
      await water.add(_day, 400);
      await confirm(1);

      expect(await water.setAmount(_day, 400), 400);
      expect(await outbox(), isEmpty);

      expect(await water.setAmount(_day, 0), 0);
      final reset = (await outbox()).single;
      expect(reset.operation, LocalMutationOperation.update);
      expect(payloadOf(reset)['amountMl'], 0);
      expect(await water.read(_day), 0);
    },
  );

  test(
    'amounts outside the daily limits are rejected without writing',
    () async {
      await water.setAmount(_day, 9800);
      await confirm(1);

      await expectLater(
        water.add(_day, 300),
        throwsA(isA<NutritionValidationException>()),
      );
      await expectLater(
        water.add(_day, 0),
        throwsA(isA<NutritionValidationException>()),
      );
      await expectLater(
        water.setAmount(_day, 10001),
        throwsA(isA<NutritionValidationException>()),
      );
      await expectLater(
        water.setAmount(_day, -1),
        throwsA(isA<NutritionValidationException>()),
      );
      await expectLater(
        water.read('2026-13-01'),
        throwsA(isA<NutritionValidationException>()),
      );
      expect(await outbox(), isEmpty);
      expect(await water.read(_day), 9800);

      // A failed change does not block the queue.
      expect(await water.add(_day, 200), 10000);
    },
  );

  test('days are kept apart and the snapshot carries the amount', () async {
    final repository = NutritionRepository(
      store: store,
      ids: id,
      clock: () => DateTime.utc(2026, 10, 25, 9),
    );
    await repository.water.add(_day, 250);
    await repository.water.add('2026-10-24', 500);

    expect((await repository.read(_day)).waterMl, 250);
    expect((await repository.read('2026-10-24')).waterMl, 500);
    expect((await repository.read('2026-10-23')).waterMl, 0);
    expect((await repository.read(_day)).withWater(900).waterMl, 900);
  });

  test('preferences default to hidden and stay with the account', () async {
    final preferences = NutritionPreferences(store: store);
    expect(await preferences.read(), const NutritionPreferenceValues());
    expect(preferences.values.value.waterEnabled, isFalse);
    expect(preferences.values.value.waterGoalMl, 2500);

    final updated = await preferences.update(
      (current) => current.copyWith(waterEnabled: true, waterGoalMl: 3000),
    );
    expect(updated.waterEnabled, isTrue);
    expect(preferences.values.value, updated);
    expect(
      await NutritionPreferences(store: store).read(),
      const NutritionPreferenceValues(waterEnabled: true, waterGoalMl: 3000),
    );

    final otherDatabase = LocalDatabase(NativeDatabase.memory());
    addTearDown(otherDatabase.close);
    final other = NutritionPreferences(
      store: LocalSyncStore(
        database: otherDatabase,
        accountId: _otherAccountId,
      ),
    );
    expect((await other.read()).waterEnabled, isFalse);
  });

  test('quick preference changes do not overwrite each other', () async {
    final preferences = NutritionPreferences(store: store);

    await Future.wait([
      preferences.update((current) => current.copyWith(waterEnabled: true)),
      preferences.update((current) => current.copyWith(waterGoalMl: 3000)),
    ]);

    expect(
      await NutritionPreferences(store: store).read(),
      const NutritionPreferenceValues(waterEnabled: true, waterGoalMl: 3000),
    );
  });

  test('invalid stored preferences fall back per value', () async {
    expect(
      NutritionPreferenceValues.fromJson({
        'waterEnabled': 'yes',
        'waterGoalMl': 50,
      }),
      const NutritionPreferenceValues(),
    );
    expect(
      NutritionPreferenceValues.fromJson({
        'waterEnabled': true,
        'waterGoalMl': 20000,
      }),
      const NutritionPreferenceValues(waterEnabled: true),
    );
    expect(
      NutritionPreferenceValues.fromJson('broken'),
      const NutritionPreferenceValues(),
    );
    expect(
      const NutritionPreferenceValues(waterGoalMl: 3000).hashCode,
      const NutritionPreferenceValues(waterGoalMl: 3000).hashCode,
    );
    expect(const NutritionPreferenceValues().toJson(), {
      'waterEnabled': false,
      'waterGoalMl': 2500,
    });
  });
}
