import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const _account = '00000000-0000-4000-8000-0000000000aa';
const _rotationId = '00000000-0000-4000-8000-000000000101';
const _workoutId = '00000000-0000-4000-8000-000000000102';
const _rotationMutation = '00000000-0000-4000-8000-000000000201';
const _workoutMutation = '00000000-0000-4000-8000-000000000202';
const _dependentMutation = '00000000-0000-4000-8000-000000000203';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gainer-rotation-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<LocalMutation> commit(
    LocalSyncStore store, {
    required String mutationId,
    required String type,
    required String id,
    required Object? body,
    String? dependsOn,
  }) => store.commitMutation(
    mutationId: mutationId,
    aggregateType: type,
    aggregateId: id,
    operation: LocalMutationOperation.create,
    baseVersion: 0,
    body: body,
    envelope: localEnvelope(aggregateId: id, workingCopy: body),
    dependsOnMutationId: dependsOn,
    createdAtUtc: DateTime.utc(2026, 10, 20),
  );

  test(
    'upgrade to version 4 drops rotation rows and keeps everything else',
    () async {
      final file = File('${directory.path}/account.sqlite');
      final before = LocalDatabase(NativeDatabase(file));
      final store = LocalSyncStore(database: before, accountId: _account);
      await commit(
        store,
        mutationId: _rotationMutation,
        type: 'workout-rotation',
        id: _rotationId,
        body: {'rotationId': _rotationId, 'planIds': <Object?>[]},
      );
      await commit(
        store,
        mutationId: _workoutMutation,
        type: 'workout',
        id: _workoutId,
        body: {'workoutId': _workoutId, 'title': 'Push'},
      );
      // Ein Eintrag, der (künstlich) auf die Rotations-Mutation wartet.
      await commit(
        store,
        mutationId: _dependentMutation,
        type: 'daily-check-in',
        id: _rotationMutation.replaceFirst('201', '301'),
        body: {'localDate': '2026-10-20'},
        dependsOn: _rotationMutation,
      );
      await store.upsertConflict(
        LocalConflictRecord(
          conflictId: 'rotation-conflict',
          aggregateType: 'workout-rotation',
          aggregateId: _rotationId,
          createdAtUtc: DateTime.utc(2026, 10, 20),
          code: 'stale_base_version',
          detail: const {},
        ),
      );
      await store.upsertConflict(
        LocalConflictRecord(
          conflictId: 'workout-conflict',
          aggregateType: 'workout',
          aggregateId: _workoutId,
          createdAtUtc: DateTime.utc(2026, 10, 20),
          code: 'stale_base_version',
          detail: const {},
        ),
      );
      await store.upsertTombstone(
        const LocalTombstoneRecord(
          resourceType: 'WorkoutRotation',
          resourceId: _rotationId,
          revision: 3,
        ),
      );
      await store.upsertTombstone(
        const LocalTombstoneRecord(
          resourceType: 'Workout',
          resourceId: _workoutId,
          revision: 4,
        ),
      );
      await before
          .into(before.localSyncMetadata)
          .insertOnConflictUpdate(
            LocalSyncMetadataCompanion.insert(
              key: 'auto-heal:workout-rotation:$_rotationId',
              valueJson: 'true',
            ),
          );
      await before
          .into(before.localSyncMetadata)
          .insertOnConflictUpdate(
            LocalSyncMetadataCompanion.insert(
              key: 'auto-heal:workout:$_workoutId',
              valueJson: 'true',
            ),
          );
      await before
          .update(before.localOutbox)
          .write(const LocalOutboxCompanion(sentAtUtc: Value(null)));
      await before.close();

      // Stand vor dem Upgrade: Schema-Version 3.
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('PRAGMA user_version = 3');
      legacy.close();

      final database = LocalDatabase(NativeDatabase(file));
      final upgraded = LocalSyncStore(database: database, accountId: _account);

      final outbox = await upgraded.readOutbox();
      expect(
        outbox.map((m) => m.mutationId),
        unorderedEquals([_workoutMutation, _dependentMutation]),
      );
      expect(
        outbox.every((m) => m.status == LocalMutationStatus.pending),
        isTrue,
      );
      expect(
        outbox
            .firstWhere((m) => m.mutationId == _dependentMutation)
            .dependsOnMutationId,
        isNull,
      );
      expect(await upgraded.readAggregates('workout-rotation'), isEmpty);
      expect(await upgraded.readAggregate('workout', _workoutId), isNotNull);
      final conflicts = await database.select(database.localConflicts).get();
      expect(conflicts.map((c) => c.conflictId), ['workout-conflict']);
      expect(
        await upgraded.hasTombstone('WorkoutRotation', _rotationId),
        isFalse,
      );
      expect(await upgraded.hasTombstone('Workout', _workoutId), isTrue);
      expect(
        await upgraded.readSyncMetadata(
          'auto-heal:workout-rotation:$_rotationId',
        ),
        isNull,
      );
      expect(
        await upgraded.readSyncMetadata('auto-heal:workout:$_workoutId'),
        isTrue,
      );
      // Ein zweites Öffnen ändert nichts mehr.
      await database.close();
      final reopened = LocalDatabase(NativeDatabase(file));
      addTearDown(reopened.close);
      final again = LocalSyncStore(database: reopened, accountId: _account);
      expect(await again.readOutbox(), hasLength(2));
    },
  );
}
