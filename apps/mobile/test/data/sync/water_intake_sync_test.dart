import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/nutrition/water_intake_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_conflict_recovery.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';

const _accountId = '00000000-0000-4000-8000-000000000081';

void main() {
  test('the server resource maps to the local water type', () {
    expect(
      SyncPayloadCodec.aggregateTypeForResource('WaterIntakeDay'),
      waterIntakeAggregateType,
    );
    expect(
      SyncPayloadCodec.normalizeSnapshot('WaterIntakeDay', {
        'waterIntakeDayId': 'id',
        'localDate': '2026-10-25',
        'amountMl': 750,
        'createdAtUtc': '2026-10-25T09:00:00Z',
        'updatedAtUtc': '2026-10-25T10:00:00Z',
        'version': 3,
      }),
      {
        'localDate': '2026-10-25',
        'amountMl': 750,
        'createdAtUtc': '2026-10-25T09:00:00Z',
        'updatedAtUtc': '2026-10-25T10:00:00Z',
      },
    );
  });

  test('forcing the local state sends the total and names the day', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: _accountId);
    var next = 200;
    final water = WaterIntakeRepository(
      store: store,
      ids: () =>
          '00000000-0000-4000-8000-${(++next).toString().padLeft(12, '0')}',
      clock: () => DateTime.utc(2026, 10, 25, 9),
    );
    await water.add('2026-10-25', 500);
    final pending = (await store.readOutbox()).single;
    await store.upsertConflict(
      LocalConflictRecord(
        conflictId: pending.mutationId,
        aggregateType: waterIntakeAggregateType,
        aggregateId: pending.aggregateId,
        createdAtUtc: DateTime.utc(2026, 10, 25, 9),
        code: 'stale_base_version',
        detail: const {'baseVersion': 0},
      ),
    );

    final info = (await store.readConflictResourceInfos())[pending.mutationId]!;
    expect(info.title, '2026-10-25');
    expect(info.canForceLocal, isTrue);
    expect(info.hasServerState, isFalse);

    await store.forceLocalState(
      conflictId: pending.mutationId,
      replacementMutationId: '00000000-0000-4000-8000-000000000999',
      createdAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    final forced = (await store.readOutbox()).single;
    final body = forced.body! as Map<String, dynamic>;
    expect(forced.operation, LocalMutationOperation.create);
    expect(body.containsKey('addedMl'), isFalse);
    expect(SyncPayloadCodec.serverOperation(forced, body), 'setWaterIntake');
    expect(
      SyncPayloadCodec.serverPayload(forced, body, 0),
      containsPair('amountMl', 500),
    );
  });
}
