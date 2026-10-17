import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';

const _accountId = '00000000-0000-4000-8000-0000000000bb';
final _now = DateTime.utc(2026, 10, 17, 12);

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toRadixString(16).padLeft(12, '0')}';

const _legacyTrainingTypes = [
  'workout',
  'workout-template',
  'workout-rotation',
  'custom-exercise',
  'training-plan',
  'exercise-category',
];
const _otherTypes = ['daily-check-in', 'nutrition-day', 'body-goal'];

Future<void> _commitAggregate(
  LocalSyncStore store,
  String aggregateType,
  int index,
) {
  final id = _uuid(0x200 + index);
  final value = {'type': aggregateType};
  return store
      .commitMutation(
        mutationId: _uuid(0x400 + index),
        aggregateType: aggregateType,
        aggregateId: id,
        operation: LocalMutationOperation.update,
        baseVersion: 1,
        body: value,
        envelope: LocalAggregateEnvelope<Object?>(
          aggregateId: id,
          serverSnapshot: value,
          workingCopy: value,
          serverVersion: 1,
          optimisticVersion: 2,
          syncState: LocalSyncState.pending,
        ),
        createdAtUtc: _now,
      )
      .then((_) {});
}

/// Everything the reset may touch, as sortable strings for comparisons.
Future<List<String>> _rowsOf(LocalDatabase db) async {
  final resources = await db.select(db.localResources).get();
  final outbox = await db.select(db.localOutbox).get();
  final conflicts = await db.select(db.localConflicts).get();
  final tombstones = await db.select(db.localTombstones).get();
  final metadata = await db.select(db.localSyncMetadata).get();
  return [
    for (final row in resources) 'res:${row.aggregateType}:${row.aggregateId}',
    for (final row in outbox) 'out:${row.aggregateType}:${row.mutationId}',
    for (final row in conflicts) 'con:${row.aggregateType}:${row.conflictId}',
    for (final row in tombstones) 'tomb:${row.resourceType}:${row.resourceId}',
    for (final row in metadata) 'meta:${row.key}=${row.valueJson}',
  ]..sort();
}

Future<Set<String>> _aggregateTypesOf(LocalDatabase db) async {
  final rows = await db.select(db.localResources).get();
  return rows.map((row) => row.aggregateType).toSet();
}

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;

  /// Legacy state: committed before the reset existed, no version marker.
  Future<void> seedLegacyState() async {
    await (database.delete(
      database.localSyncMetadata,
    )..where((t) => t.key.equals(trainingSchemaVersionKey))).go();
    var index = 0;
    for (final type in [..._legacyTrainingTypes, ..._otherTypes]) {
      await _commitAggregate(store, type, index++);
    }
    await database
        .into(database.localConflicts)
        .insert(
          LocalConflictsCompanion.insert(
            conflictId: _uuid(0x600),
            aggregateType: 'workout',
            aggregateId: _uuid(0x200),
            createdAtUtc: _now.toIso8601String(),
            code: 'version_conflict',
            detailJson: '{}',
          ),
        );
    await database
        .into(database.localConflicts)
        .insert(
          LocalConflictsCompanion.insert(
            conflictId: _uuid(0x601),
            aggregateType: 'daily-check-in',
            aggregateId: _uuid(0x206),
            createdAtUtc: _now.toIso8601String(),
            code: 'version_conflict',
            detailJson: '{}',
          ),
        );
    await database
        .into(database.localTombstones)
        .insert(
          LocalTombstonesCompanion.insert(
            resourceType: 'Workout',
            resourceId: _uuid(0x700),
            revision: 4,
          ),
        );
    await database
        .into(database.localTombstones)
        .insert(
          LocalTombstonesCompanion.insert(
            resourceType: 'DailyCheckIn',
            resourceId: _uuid(0x701),
            revision: 4,
          ),
        );
    await database
        .into(database.localSyncMetadata)
        .insert(
          LocalSyncMetadataCompanion.insert(
            key: 'pull-cursor',
            valueJson: '17',
          ),
        );
  }

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _accountId);
  });

  tearDown(() async {
    await store.close();
  });

  test(
    'removes all training data and keeps check-in and nutrition data',
    () async {
      await seedLegacyState();

      await store.migrateTrainingSchema();

      expect(await _aggregateTypesOf(database), _otherTypes.toSet());
      final outbox = await database.select(database.localOutbox).get();
      expect(
        outbox.map((row) => row.aggregateType).toSet(),
        _otherTypes.toSet(),
      );
      final conflicts = await database.select(database.localConflicts).get();
      expect(conflicts.map((row) => row.aggregateType), ['daily-check-in']);
      final tombstones = await database.select(database.localTombstones).get();
      expect(tombstones.map((row) => row.resourceType), ['DailyCheckIn']);
      final metadata = {
        for (final row
            in await database.select(database.localSyncMetadata).get())
          row.key: row.valueJson,
      };
      expect(metadata['training-schema-version'], '2');
      expect(metadata.containsKey('pull-cursor'), isFalse);
      expect(metadata.containsKey('account-owner-id'), isTrue);
    },
  );

  test(
    'the first store access runs the reset and no later call changes it',
    () async {
      await seedLegacyState();

      expect(await store.readAggregates('workout'), isEmpty);

      expect(await _aggregateTypesOf(database), _otherTypes.toSet());
      expect(await store.readSyncMetadata('pull-cursor'), isNull);
      expect(await store.readSyncMetadata('training-schema-version'), 2);
    },
  );

  test(
    'a second run changes nothing and keeps training data written afterwards',
    () async {
      await seedLegacyState();
      await store.migrateTrainingSchema();
      final afterFirst = await _rowsOf(database);

      await store.migrateTrainingSchema();
      expect(await _rowsOf(database), afterFirst);

      await _commitAggregate(store, 'workout', 0x50);
      await store.migrateTrainingSchema();
      expect(await _aggregateTypesOf(database), {..._otherTypes, 'workout'});
    },
  );

  test('a failure in the middle of the reset deletes nothing and keeps the version unchanged', () async {
    await seedLegacyState();
    final before = await _rowsOf(database);

    await expectLater(
      store.migrateTrainingSchema(
        afterFirstDeleteForTesting: () => throw StateError('boom'),
      ),
      throwsStateError,
    );

    expect(await _rowsOf(database), before);
    // Read the table directly: store reads would run the reset again.
    final keys = (await database.select(database.localSyncMetadata).get()).map(
      (row) => row.key,
    );
    expect(keys, isNot(contains('training-schema-version')));
  });
}
