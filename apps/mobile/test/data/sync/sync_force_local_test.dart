import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_conflict_recovery.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';

const _accountId = 'a1234567-1234-4234-8234-123456789abc';
const _workoutId = 'b1234567-1234-4234-8234-123456789abc';
const _exerciseId = 'b2234567-1234-4234-8234-123456789abc';
const _replacementId = 'f1234567-1234-4234-8234-123456789abc';

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  var nextMutation = 0;

  String mutationId() =>
      'c${(nextMutation++).toString().padLeft(7, '0')}-1234-4234-8234-123456789abc';

  setUp(() {
    nextMutation = 0;
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _accountId);
  });

  tearDown(() => database.close());

  Map<String, Object?> workout({String? endedAtUtc, String? deletedAtUtc}) => {
    'workoutId': _workoutId,
    'title': 'Push',
    'startedAtUtc': '2026-10-17T08:00:00Z',
    'endedAtUtc': endedAtUtc,
    'deletedAtUtc': deletedAtUtc,
    'exercises': <Object?>[],
  };

  Future<void> commit({
    required String type,
    required String id,
    required LocalMutationOperation operation,
    required Map<String, Object?> body,
    int? baseVersion,
    int? serverVersion,
    Object? serverSnapshot,
    DateTime? createdAtUtc,
  }) => store.commitMutation(
    mutationId: mutationId(),
    aggregateType: type,
    aggregateId: id,
    operation: operation,
    baseVersion: baseVersion,
    body: body,
    envelope: LocalAggregateEnvelope<Object?>(
      aggregateId: id,
      serverSnapshot: serverSnapshot,
      workingCopy: body,
      serverVersion: serverVersion,
      optimisticVersion: 2,
      syncState: LocalSyncState.pending,
    ),
    createdAtUtc: createdAtUtc ?? DateTime.utc(2026, 10, 17, 8),
  );

  Future<String> conflict(String type, String id, String code) async {
    final first = (await store.readOutbox()).firstWhere(
      (m) => m.aggregateType == type && m.aggregateId == id,
    );
    await store.upsertConflict(
      LocalConflictRecord(
        conflictId: first.mutationId,
        aggregateType: type,
        aggregateId: id,
        createdAtUtc: DateTime.utc(2026, 10, 18),
        code: code,
        detail: {'message': 'abgelehnt'},
      ),
    );
    return first.mutationId;
  }

  Future<void> force(String conflictId) => store.forceLocalState(
    conflictId: conflictId,
    replacementMutationId: _replacementId,
    createdAtUtc: DateTime.utc(2026, 10, 19),
  );

  test(
    'create: replaces all queued rows by one create of the working copy',
    () async {
      await commit(
        type: 'workout',
        id: _workoutId,
        operation: LocalMutationOperation.create,
        baseVersion: 0,
        body: workout(),
      );
      await commit(
        type: 'workout',
        id: _workoutId,
        operation: LocalMutationOperation.update,
        body: workout(endedAtUtc: '2026-10-17T09:00:00Z'),
      );
      final conflictId = await conflict(
        'workout',
        _workoutId,
        'active_workout_exists',
      );

      await force(conflictId);

      final outbox = await store.readOutbox();
      expect(outbox, hasLength(1));
      final row = outbox.single;
      expect(row.mutationId, _replacementId);
      expect(row.operation, LocalMutationOperation.create);
      expect(row.baseVersion, 0);
      expect(row.sequence, 1);
      expect(row.createdAtUtc, DateTime.utc(2026, 10, 17, 8));
      expect(row.status, LocalMutationStatus.pending);
      expect(row.dependsOnMutationId, isNull);
      expect(row.clientSequence, isNull);
      expect(row.body, workout(endedAtUtc: '2026-10-17T09:00:00Z'));
      expect(await database.select(database.localConflicts).get(), isEmpty);
      final envelope = await store.readAggregate('workout', _workoutId);
      expect(envelope?.syncState, LocalSyncState.pending);
      expect(envelope?.serverVersion, isNull);
    },
  );

  test('update: saves against the current server version', () async {
    final snapshot = workout();
    await commit(
      type: 'workout',
      id: _workoutId,
      operation: LocalMutationOperation.update,
      baseVersion: 2,
      body: workout(endedAtUtc: '2026-10-17T09:00:00Z'),
      serverVersion: 5,
      serverSnapshot: snapshot,
    );
    final conflictId = await conflict(
      'workout',
      _workoutId,
      'stale_base_version',
    );

    await force(conflictId);

    final row = (await store.readOutbox()).single;
    expect(row.operation, LocalMutationOperation.update);
    expect(row.baseVersion, 5);
    expect(
      jsonDecode(
        (await database.select(database.localOutbox).getSingle()).payloadJson,
      ),
      {
        'operation': 'update',
        'baseVersion': 5,
        'body': workout(endedAtUtc: '2026-10-17T09:00:00Z'),
      },
    );
    final envelope = await store.readAggregate('workout', _workoutId);
    expect(envelope?.serverVersion, 5);
    expect(envelope?.serverSnapshot, snapshot);
  });

  test(
    'delete: a locally deleted resource known to the server is deleted',
    () async {
      await commit(
        type: 'workout',
        id: _workoutId,
        operation: LocalMutationOperation.update,
        baseVersion: 2,
        body: workout(),
        serverVersion: 3,
        serverSnapshot: workout(),
      );
      await commit(
        type: 'workout',
        id: _workoutId,
        operation: LocalMutationOperation.delete,
        body: workout(deletedAtUtc: '2026-10-17T10:00:00Z'),
        serverVersion: 3,
        serverSnapshot: workout(),
      );
      final conflictId = await conflict(
        'workout',
        _workoutId,
        'stale_base_version',
      );

      await force(conflictId);

      final row = (await store.readOutbox()).single;
      expect(row.operation, LocalMutationOperation.delete);
      expect(row.baseVersion, 3);
    },
  );

  test(
    'deleted locally and unknown to the server: removes everything',
    () async {
      await commit(
        type: 'workout',
        id: _workoutId,
        operation: LocalMutationOperation.create,
        baseVersion: 0,
        body: workout(),
      );
      await commit(
        type: 'workout',
        id: _workoutId,
        operation: LocalMutationOperation.delete,
        body: workout(deletedAtUtc: '2026-10-17T10:00:00Z'),
      );
      final conflictId = await conflict(
        'workout',
        _workoutId,
        'active_workout_exists',
      );

      await force(conflictId);

      expect(await store.readOutbox(), isEmpty);
      expect(await database.select(database.localConflicts).get(), isEmpty);
      expect(await store.readAggregate('workout', _workoutId), isNull);
    },
  );

  test('a deletion marker in the working copy counts as deleted', () async {
    await commit(
      type: 'workout',
      id: _workoutId,
      operation: LocalMutationOperation.update,
      body: workout(deletedAtUtc: '2026-10-17T10:00:00Z'),
    );
    final conflictId = await conflict(
      'workout',
      _workoutId,
      'validation_failed',
    );

    await force(conflictId);

    expect(await store.readOutbox(), isEmpty);
    expect(await store.readAggregate('workout', _workoutId), isNull);
  });

  test('a server tombstone is never revived', () async {
    await commit(
      type: 'workout',
      id: _workoutId,
      operation: LocalMutationOperation.update,
      baseVersion: 2,
      body: workout(),
      serverVersion: 2,
      serverSnapshot: workout(),
    );
    await store.upsertTombstone(
      const LocalTombstoneRecord(
        resourceType: 'Workout',
        resourceId: _workoutId,
        revision: 9,
      ),
    );
    final conflictId = await conflict(
      'workout',
      _workoutId,
      'resource_not_found',
    );

    await expectLater(force(conflictId), throwsStateError);

    expect(await store.readOutbox(), hasLength(1));
    expect(await database.select(database.localConflicts).get(), hasLength(1));
    final info = (await store.readConflictResourceInfos())[conflictId]!;
    expect(info.canForceLocal, isFalse);
    expect(info.hasServerState, isTrue);
  });

  test('rejects unsupported types, multi-resource rows and bad ids', () async {
    await commit(
      type: 'body-goal',
      id: _exerciseId,
      operation: LocalMutationOperation.create,
      body: {'kind': 'Cut'},
    );
    final goalConflict = await conflict(
      'body-goal',
      _exerciseId,
      'validation_failed',
    );
    await expectLater(force(goalConflict), throwsStateError);

    await commit(
      type: 'custom-exercise',
      id: _workoutId,
      operation: LocalMutationOperation.merge,
      body: {'targetExerciseId': _exerciseId},
    );
    final mergeConflict = await conflict(
      'custom-exercise',
      _workoutId,
      'validation_failed',
    );
    await expectLater(force(mergeConflict), throwsStateError);
    final infos = await store.readConflictResourceInfos();
    expect(infos[goalConflict]!.canForceLocal, isFalse);
    expect(infos[mergeConflict]!.canForceLocal, isFalse);

    await expectLater(
      store.forceLocalState(
        conflictId: mergeConflict,
        replacementMutationId: 'not an id!',
        createdAtUtc: DateTime.utc(2026, 10, 19),
      ),
      throwsArgumentError,
    );
    await expectLater(
      store.forceLocalState(
        conflictId: 'missing',
        replacementMutationId: _replacementId,
        createdAtUtc: DateTime.utc(2026, 10, 19),
      ),
      throwsStateError,
    );
  });

  test('keeps the original send order across resources', () async {
    await commit(
      type: 'custom-exercise',
      id: _exerciseId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: {'id': _exerciseId, 'name': 'Rudern'},
      createdAtUtc: DateTime.utc(2026, 10, 17, 7),
    );
    await commit(
      type: 'workout',
      id: _workoutId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: workout(),
      createdAtUtc: DateTime.utc(2026, 10, 17, 8),
    );
    final exerciseConflict = await conflict(
      'custom-exercise',
      _exerciseId,
      'validation_failed',
    );
    final workoutConflict = await conflict(
      'workout',
      _workoutId,
      'validation_failed',
    );

    // Das Training wird zuerst erzwungen und darf die Übung nicht überholen.
    await store.forceLocalState(
      conflictId: workoutConflict,
      replacementMutationId: _replacementId,
      createdAtUtc: DateTime.utc(2026, 10, 19),
    );
    await store.forceLocalState(
      conflictId: exerciseConflict,
      replacementMutationId: 'f2234567-1234-4234-8234-123456789abc',
      createdAtUtc: DateTime.utc(2026, 10, 19, 1),
    );

    final outbox = await store.readOutbox();
    expect(outbox.map((m) => m.aggregateType), ['custom-exercise', 'workout']);
  });

  test('without queued rows the given time and sequence 1 are used', () async {
    await commit(
      type: 'workout',
      id: _workoutId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: workout(),
    );
    final conflictId = await conflict(
      'workout',
      _workoutId,
      'validation_failed',
    );
    await store.deleteMutation(conflictId);

    await force(conflictId);

    final row = (await store.readOutbox()).single;
    expect(row.sequence, 1);
    expect(row.createdAtUtc, DateTime.utc(2026, 10, 19));
  });

  test('resource infos expose title, server state and queue position', () async {
    await commit(
      type: 'workout',
      id: _workoutId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: workout(),
      createdAtUtc: DateTime.utc(2026, 10, 17, 8),
    );
    await commit(
      type: 'exercise-category',
      id: _exerciseId,
      operation: LocalMutationOperation.update,
      baseVersion: 1,
      body: {'id': _exerciseId, 'name': 'Beine'},
      serverVersion: 2,
      serverSnapshot: {'id': _exerciseId, 'name': 'Beine'},
      createdAtUtc: DateTime.utc(2026, 10, 17, 9),
    );
    final workoutConflict = await conflict(
      'workout',
      _workoutId,
      'active_workout_exists',
    );
    final categoryConflict = await conflict(
      'exercise-category',
      _exerciseId,
      'stale_base_version',
    );

    final infos = await store.readConflictResourceInfos();

    final started = DateTime.utc(2026, 10, 17, 8).toLocal();
    final date =
        '${started.day.toString().padLeft(2, '0')}.${started.month.toString().padLeft(2, '0')}.${started.year}';
    expect(infos[workoutConflict]!.title, 'Push · $date');
    expect(infos[workoutConflict]!.hasServerState, isFalse);
    expect(infos[workoutConflict]!.canForceLocal, isTrue);
    expect(infos[workoutConflict]!.firstSequence, 1);
    expect(
      infos[workoutConflict]!.firstQueuedAtUtc,
      DateTime.utc(2026, 10, 17, 8),
    );
    expect(infos[categoryConflict]!.title, 'Beine');
    expect(infos[categoryConflict]!.hasServerState, isTrue);
    expect(infos[categoryConflict]!.canForceLocal, isTrue);
  });

  test(
    'titles fall back by type and are absent without a local copy',
    () async {
      await commit(
        type: 'daily-check-in',
        id: _exerciseId,
        operation: LocalMutationOperation.create,
        baseVersion: 0,
        body: {'localDate': '2026-10-12'},
      );
      await commit(
        type: 'workout-rotation',
        id: _workoutId,
        operation: LocalMutationOperation.create,
        baseVersion: 0,
        body: {'rotationId': _workoutId, 'planIds': <Object?>[]},
      );
      final checkIn = await conflict('daily-check-in', _exerciseId, 'x');
      final rotation = await conflict('workout-rotation', _workoutId, 'x');
      await database.delete(database.localResources).go();
      await store.upsertConflict(
        LocalConflictRecord(
          conflictId: 'orphan',
          aggregateType: 'unknown-type',
          aggregateId: 'z',
          createdAtUtc: DateTime.utc(2026, 10, 18),
          code: 'x',
          detail: const {},
        ),
      );

      final infos = await store.readConflictResourceInfos();

      expect(infos[checkIn]!.title, isNull);
      expect(infos[rotation]!.canForceLocal, isFalse);
      expect(infos['orphan']!.canForceLocal, isFalse);
      expect(infos['orphan']!.hasServerState, isFalse);
    },
  );

  test('check-in and rotation titles come from the working copy', () async {
    await commit(
      type: 'daily-check-in',
      id: _exerciseId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: {'localDate': '2026-10-12'},
    );
    await commit(
      type: 'workout-rotation',
      id: _workoutId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: {'rotationId': _workoutId, 'planIds': <Object?>[]},
    );
    final checkIn = await conflict('daily-check-in', _exerciseId, 'x');
    final rotation = await conflict('workout-rotation', _workoutId, 'x');

    final infos = await store.readConflictResourceInfos();

    expect(infos[checkIn]!.title, '2026-10-12');
    expect(infos[rotation]!.title, 'Rotation');
  });
}
