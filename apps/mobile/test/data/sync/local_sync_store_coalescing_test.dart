import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';

const _accountId = '00000000-0000-4000-8000-0000000000aa';
final _now = DateTime.utc(2026, 10, 17, 12);

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toRadixString(16).padLeft(12, '0')}';

LocalAggregateEnvelope<Object?> _envelope(
  String id,
  Object? value,
  int version,
) => LocalAggregateEnvelope<Object?>(
  aggregateId: id,
  serverSnapshot: {'title': 'Server'},
  workingCopy: value,
  serverVersion: 2,
  optimisticVersion: version,
  syncState: LocalSyncState.pending,
);

Future<LocalMutation> _updateWorkout(
  LocalSyncStore store,
  String workoutId,
  String mutationId,
  int version, {
  void Function()? afterEnvelopeWriteForTesting,
}) {
  final value = {'title': 'Stand $version'};
  return store.commitMutation(
    mutationId: mutationId,
    aggregateType: 'workout',
    aggregateId: workoutId,
    operation: LocalMutationOperation.update,
    baseVersion: 2,
    body: value,
    envelope: _envelope(workoutId, value, version),
    createdAtUtc: _now,
    afterEnvelopeWriteForTesting: afterEnvelopeWriteForTesting,
  );
}

Future<LocalMutation> _createWorkout(
  LocalSyncStore store,
  String workoutId,
  String mutationId,
) {
  const value = {'title': 'Neu'};
  return store.commitMutation(
    mutationId: mutationId,
    aggregateType: 'workout',
    aggregateId: workoutId,
    operation: LocalMutationOperation.create,
    baseVersion: null,
    body: value,
    envelope: LocalAggregateEnvelope<Object?>(
      aggregateId: workoutId,
      serverSnapshot: null,
      workingCopy: value,
      serverVersion: null,
      optimisticVersion: 1,
      syncState: LocalSyncState.pending,
    ),
    createdAtUtc: _now,
  );
}

String _titleOf(Object? body) =>
    (body as Map<String, dynamic>)['title'] as String;

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  var counter = 0x100;
  String nextId() => _uuid(counter++);

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _accountId);
  });

  tearDown(() async {
    await store.close();
  });

  group('coalescing of unsent workout edits', () {
    test(
      'fifty consecutive edits leave one pending entry with the last state',
      () async {
        final workoutId = nextId();
        final first = await _updateWorkout(store, workoutId, nextId(), 1);
        for (var version = 2; version <= 50; version++) {
          final committed = await _updateWorkout(
            store,
            workoutId,
            nextId(),
            version,
          );
          expect(committed.mutationId, first.mutationId);
        }

        final outbox = await store.readOutbox(aggregateType: 'workout');
        expect(outbox, hasLength(1));
        expect(outbox.single.mutationId, first.mutationId);
        expect(outbox.single.sequence, first.sequence);
        expect(outbox.single.baseVersion, 2);
        expect(_titleOf(outbox.single.body), 'Stand 50');
        final envelope = await store.readAggregate('workout', workoutId);
        expect(envelope?.optimisticVersion, 50);
        expect(_titleOf(envelope?.workingCopy), 'Stand 50');
      },
    );

    test(
      'a claimed entry is never changed and the next edit appends',
      () async {
        final workoutId = nextId();
        final first = await _updateWorkout(store, workoutId, nextId(), 1);
        await store.claimMutationForSending(first.mutationId, now: _now);

        final next = await _updateWorkout(store, workoutId, nextId(), 2);

        expect(next.mutationId, isNot(first.mutationId));
        final outbox = await store.readOutbox(aggregateType: 'workout');
        expect(outbox.map((row) => row.mutationId), [
          first.mutationId,
          next.mutationId,
        ]);
        final sent = await store.readMutation(first.mutationId);
        expect(sent?.status, LocalMutationStatus.syncing);
        expect(_titleOf(sent?.body), 'Stand 1');
      },
    );

    test(
      'a sent entry keeps its body after it was returned to pending',
      () async {
        final workoutId = nextId();
        final first = await _updateWorkout(store, workoutId, nextId(), 1);
        await store.claimMutationForSending(first.mutationId, now: _now);
        final sent = (await store.readMutation(first.mutationId))!;
        await store.updateMutation(
          LocalMutation(
            mutationId: sent.mutationId,
            accountId: sent.accountId,
            aggregateType: sent.aggregateType,
            aggregateId: sent.aggregateId,
            sequence: sent.sequence,
            status: LocalMutationStatus.pending,
            createdAtUtc: sent.createdAtUtc,
            operation: sent.operation,
            baseVersion: sent.baseVersion,
            body: sent.body,
            attemptCount: 1,
            nextAttemptAtUtc: _now.add(const Duration(seconds: 5)),
            lastErrorCode: 'timeout',
          ),
        );

        await _updateWorkout(store, workoutId, nextId(), 2);

        final outbox = await store.readOutbox(aggregateType: 'workout');
        expect(outbox, hasLength(2));
        expect(_titleOf(outbox.first.body), 'Stand 1');
      },
    );

    test(
      'create keeps its own entry and later edits coalesce into one update',
      () async {
        final workoutId = nextId();
        final created = await _createWorkout(store, workoutId, nextId());
        final firstUpdate = await _updateWorkout(store, workoutId, nextId(), 2);
        await _updateWorkout(store, workoutId, nextId(), 3);
        await _updateWorkout(store, workoutId, nextId(), 4);

        final outbox = await store.readOutbox(aggregateType: 'workout');
        expect(outbox, hasLength(2));
        expect(outbox.first.mutationId, created.mutationId);
        expect(outbox.first.operation, LocalMutationOperation.create);
        expect(_titleOf(outbox.first.body), 'Neu');
        expect(outbox.last.mutationId, firstUpdate.mutationId);
        expect(outbox.last.operation, LocalMutationOperation.update);
        expect(_titleOf(outbox.last.body), 'Stand 4');
      },
    );

    test('an edit of another workout does not coalesce', () async {
      final workoutA = nextId();
      final workoutB = nextId();
      final a = await _updateWorkout(store, workoutA, nextId(), 1);
      final b = await _updateWorkout(store, workoutB, nextId(), 1);
      final a2 = await _updateWorkout(store, workoutA, nextId(), 2);

      expect(b.mutationId, isNot(a.mutationId));
      expect(a2.mutationId, a.mutationId);
      final outbox = await store.readOutbox(aggregateType: 'workout');
      expect(outbox.map((row) => row.aggregateId), [workoutA, workoutB]);
      expect(_titleOf(outbox.last.body), 'Stand 1');
    });

    test(
      'a failure inside the transaction leaves envelope and outbox unchanged',
      () async {
        final workoutId = nextId();
        await _updateWorkout(store, workoutId, nextId(), 1);

        await expectLater(
          _updateWorkout(
            store,
            workoutId,
            nextId(),
            2,
            afterEnvelopeWriteForTesting: () => throw StateError('boom'),
          ),
          throwsStateError,
        );

        final outbox = await store.readOutbox(aggregateType: 'workout');
        expect(outbox, hasLength(1));
        expect(_titleOf(outbox.single.body), 'Stand 1');
        final envelope = await store.readAggregate('workout', workoutId);
        expect(envelope?.optimisticVersion, 1);
        expect(_titleOf(envelope?.workingCopy), 'Stand 1');
      },
    );

    test('a stale status copy cannot overwrite a coalesced body', () async {
      final workoutId = nextId();
      await _updateWorkout(store, workoutId, nextId(), 1);
      final stale = (await store.readOutbox(aggregateType: 'workout')).single;
      await _updateWorkout(store, workoutId, nextId(), 2);

      await store.updateMutation(
        LocalMutation(
          mutationId: stale.mutationId,
          accountId: stale.accountId,
          aggregateType: stale.aggregateType,
          aggregateId: stale.aggregateId,
          sequence: stale.sequence,
          status: LocalMutationStatus.failed,
          createdAtUtc: stale.createdAtUtc,
          operation: stale.operation,
          baseVersion: stale.baseVersion,
          body: stale.body,
          lastErrorCode: 'conflict',
        ),
      );

      final outbox = await store.readOutbox(aggregateType: 'workout');
      expect(_titleOf(outbox.single.body), 'Stand 2');
      expect(outbox.single.status, LocalMutationStatus.failed);
    });

    test('a claim after a coalesced edit sends the stored body', () async {
      final workoutId = nextId();
      final first = await _updateWorkout(store, workoutId, nextId(), 1);
      final candidate = (await store.readOutbox(aggregateType: 'workout'))
          .single;
      await _updateWorkout(store, workoutId, nextId(), 2);

      final claimed = await store.claimMutationForSending(
        candidate.mutationId,
        now: _now,
      );

      expect(claimed?.mutationId, first.mutationId);
      expect(claimed?.status, LocalMutationStatus.syncing);
      expect(_titleOf(claimed?.body), 'Stand 2');
    });

    test(
      'the coalesced body survives closing and reopening the database',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'gainer-outbox-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File(
          '${directory.path}${Platform.pathSeparator}account.sqlite',
        );
        final workoutId = nextId();

        final firstDb = LocalDatabase(NativeDatabase(file));
        final firstStore = LocalSyncStore(
          database: firstDb,
          accountId: _accountId,
        );
        final first = await _updateWorkout(firstStore, workoutId, nextId(), 1);
        await _updateWorkout(firstStore, workoutId, nextId(), 2);
        await _updateWorkout(firstStore, workoutId, nextId(), 3);
        await firstDb.close();

        final reopened = LocalSyncStore(
          database: LocalDatabase(NativeDatabase(file)),
          accountId: _accountId,
        );
        addTearDown(reopened.close);
        final outbox = await reopened.readOutbox(aggregateType: 'workout');
        expect(outbox, hasLength(1));
        expect(outbox.single.mutationId, first.mutationId);
        expect(_titleOf(outbox.single.body), 'Stand 3');
      },
    );
  });
}
