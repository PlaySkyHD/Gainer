import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const accountA = 'a1234567-1234-4234-8234-123456789abc';
const aggregateId = 'b1234567-1234-4234-8234-123456789abc';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gainer-local-store-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  LocalDatabase open(String name) =>
      LocalDatabase(NativeDatabase(File('${directory.path}/$name.sqlite')));

  test(
    'commits envelope and immutable outbox together and survives reopen',
    () async {
      final database = open('account');
      final store = LocalSyncStore(database: database, accountId: accountA);
      final mutableBody = <String, Object?>{'weightKg': 81.5};
      final mutation = await store.commitMutation(
        mutationId: 'c1234567-1234-4234-8234-123456789abc',
        aggregateType: 'daily-check-in',
        aggregateId: aggregateId,
        operation: LocalMutationOperation.create,
        baseVersion: null,
        body: mutableBody,
        envelope: localEnvelope(
          aggregateId: aggregateId,
          workingCopy: mutableBody,
        ),
        createdAtUtc: DateTime.utc(2026, 10, 12),
      );
      mutableBody['weightKg'] = 99;
      expect(mutation.sequence, 1);
      expect((await store.readOutbox()).single.body, {'weightKg': 81.5});
      await store.close();

      final reopened = open('account');
      final afterRestart = LocalSyncStore(
        database: reopened,
        accountId: accountA,
      );
      final envelope = await afterRestart.readAggregate(
        'daily-check-in',
        aggregateId,
      );
      expect(envelope?.workingCopy, {'weightKg': 81.5});
      expect(envelope?.serverSnapshot, isNull);
      expect(envelope?.serverVersion, isNull);
      expect(
        (await afterRestart.readOutbox()).single.mutationId,
        mutation.mutationId,
      );
      await reopened.close();
    },
  );

  test(
    'rolls back envelope when outbox insert fails inside the transaction',
    () async {
      final database = open('rollback');
      final store = LocalSyncStore(database: database, accountId: accountA);
      expect(
        () => store.commitMutation(
          mutationId: 'c1234567-1234-4234-8234-123456789abc',
          aggregateType: 'daily-check-in',
          aggregateId: aggregateId,
          operation: LocalMutationOperation.create,
          baseVersion: null,
          body: {'weightKg': 81.5},
          envelope: localEnvelope(
            aggregateId: aggregateId,
            workingCopy: {'weightKg': 81.5},
          ),
          afterEnvelopeWriteForTesting: () =>
              throw StateError('simulated process failure'),
        ),
        throwsStateError,
      );
      expect(await store.readAggregate('daily-check-in', aggregateId), isNull);
      expect(await store.readOutbox(), isEmpty);
      await database.close();
    },
  );

  test('commit stream emits once only after a committed transaction', () async {
    final database = open('commit-stream');
    final store = LocalSyncStore(database: database, accountId: accountA);
    final emitted = <LocalMutation>[];
    final subscription = store.committedMutations.listen(emitted.add);
    await expectLater(
      store.commitMutation(
        mutationId: 'c1234567-1234-4234-8234-123456789abc',
        aggregateType: 'daily-check-in',
        aggregateId: aggregateId,
        operation: LocalMutationOperation.create,
        baseVersion: null,
        body: {'weightKg': 81.5},
        envelope: localEnvelope(
          aggregateId: aggregateId,
          workingCopy: {'weightKg': 81.5},
        ),
        afterEnvelopeWriteForTesting: () =>
            throw StateError('simulated transaction rollback'),
      ),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    expect(emitted, isEmpty);

    final committed = await store.commitMutation(
      mutationId: 'd1234567-1234-4234-8234-123456789abc',
      aggregateType: 'daily-check-in',
      aggregateId: aggregateId,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: {'weightKg': 81.5},
      envelope: localEnvelope(
        aggregateId: aggregateId,
        workingCopy: {'weightKg': 81.5},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(emitted, [committed]);
    await subscription.cancel();
    await store.close();
  });

  test('uses account scoped outbox reads and validates account ids', () async {
    final database = open('account-scope');
    final first = LocalSyncStore(database: database, accountId: accountA);
    const accountB = 'd1234567-1234-4234-8234-123456789abc';
    await first.commitMutation(
      mutationId: 'c1234567-1234-4234-8234-123456789abc',
      aggregateType: 'daily-check-in',
      aggregateId: aggregateId,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: {'weightKg': 81},
      envelope: localEnvelope(
        aggregateId: aggregateId,
        workingCopy: {'weightKg': 81},
      ),
    );
    expect(await first.readOutbox(), hasLength(1));
    await expectLater(
      first.writeSyncMetadata('account-owner-id', accountB),
      throwsArgumentError,
    );
    expect(
      () => LocalSyncStore(database: database, accountId: 'invalid'),
      throwsArgumentError,
    );
    await database.close();

    final secondDatabase = open('account-scope-b');
    final second = LocalSyncStore(
      database: secondDatabase,
      accountId: accountB,
    );
    await second.commitMutation(
      mutationId: 'e1234567-1234-4234-8234-123456789abc',
      aggregateType: 'daily-check-in',
      aggregateId: aggregateId,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: {'weightKg': 81},
      envelope: localEnvelope(
        aggregateId: aggregateId,
        workingCopy: {'weightKg': 81},
      ),
    );
    expect(await second.readOutbox(), hasLength(1));
    await secondDatabase.close();
  });

  test(
    'a persisted account database cannot be reopened under a different account',
    () async {
      final path = '${directory.path}/bound.sqlite';
      final firstDb = LocalDatabase(NativeDatabase(File(path)));
      final first = LocalSyncStore(database: firstDb, accountId: accountA);
      await first
          .readOutbox(); // Binds the database even before the first edit.
      await firstDb.close();

      final reopened = LocalDatabase(NativeDatabase(File(path)));
      final wrongAccount = LocalSyncStore(
        database: reopened,
        accountId: 'd1234567-1234-4234-8234-123456789abc',
      );
      await expectLater(wrongAccount.readOutbox(), throwsStateError);
      await reopened.close();
    },
  );

  test(
    'persists a stable random installation UUID in the installation store',
    () async {
      final database = open('installation');
      final identity = InstallationIdentityStore(database);
      final first = await identity.getOrCreateInstallationId();
      final second = await identity.getOrCreateInstallationId();
      expect(first, second);
      expect(RegExp(LocalDatabase.accountIdPattern).hasMatch(first), isTrue);
      await database.close();
    },
  );

  test(
    'handover write freeze blocks edits and requires an empty durable outbox',
    () async {
      final database = open('handover-freeze');
      final store = LocalSyncStore(database: database, accountId: accountA);
      await store.freezeWritesIfOutboxEmpty();
      await expectLater(
        store.commitMutation(
          mutationId: 'c1234567-1234-4234-8234-123456789abc',
          aggregateType: 'daily-check-in',
          aggregateId: aggregateId,
          operation: LocalMutationOperation.create,
          baseVersion: null,
          body: {'weightKg': 81},
          envelope: localEnvelope(
            aggregateId: aggregateId,
            workingCopy: {'weightKg': 81},
          ),
        ),
        throwsStateError,
      );
      expect(await store.readOutbox(), isEmpty);
      await store.unfreezeWrites();
      await store.commitMutation(
        mutationId: 'c1234567-1234-4234-8234-123456789abc',
        aggregateType: 'daily-check-in',
        aggregateId: aggregateId,
        operation: LocalMutationOperation.create,
        baseVersion: null,
        body: {'weightKg': 81},
        envelope: localEnvelope(
          aggregateId: aggregateId,
          workingCopy: {'weightKg': 81},
        ),
      );
      await expectLater(store.freezeWritesIfOutboxEmpty(), throwsStateError);
      await database.close();
    },
  );

  test(
    'schema migration adds retry columns without losing queued outbox rows',
    () async {
      final file = File('${directory.path}/legacy-v1.sqlite');
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('''
      CREATE TABLE local_sync_metadata (
        key TEXT NOT NULL PRIMARY KEY,
        value_json TEXT NOT NULL
      )
    ''');
      legacy.execute('''
      CREATE TABLE local_outbox (
        mutation_id TEXT NOT NULL PRIMARY KEY,
        account_id TEXT NOT NULL,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        status TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        base_version INTEGER NULL,
        client_sequence INTEGER NULL,
        depends_on_mutation_id TEXT NULL,
        UNIQUE(account_id, aggregate_type, aggregate_id, sequence)
      )
    ''');
      legacy.execute('''
      CREATE TABLE local_resources (
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        envelope_json TEXT NOT NULL,
        updated_at_epoch_ms INTEGER NOT NULL,
        PRIMARY KEY (aggregate_type, aggregate_id)
      )
    ''');
      legacy.execute('''
      CREATE TABLE local_conflicts (
        conflict_id TEXT NOT NULL PRIMARY KEY,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        code TEXT NOT NULL,
        detail_json TEXT NOT NULL
      )
    ''');
      legacy.execute('''
      CREATE TABLE local_tombstones (
        resource_type TEXT NOT NULL,
        resource_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        PRIMARY KEY (resource_type, resource_id)
      )
    ''');
      legacy.execute(
        '''
      INSERT INTO local_outbox (
        mutation_id, account_id, aggregate_type, aggregate_id, sequence,
        status, created_at_utc, payload_json, base_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
        [
          'c1234567-1234-4234-8234-123456789abc',
          accountA,
          'daily-check-in',
          aggregateId,
          1,
          'pending',
          '2026-10-12T00:00:00.000Z',
          '{"operation":"create","baseVersion":null,"body":{"weightKg":81}}',
          null,
        ],
      );
      legacy.execute('PRAGMA user_version = 1');
      legacy.close();

      final database = LocalDatabase(NativeDatabase(file));
      final store = LocalSyncStore(database: database, accountId: accountA);
      final queued = await store.readOutbox();
      expect(queued, hasLength(1));
      expect(queued.single.status, LocalMutationStatus.pending);
      expect(queued.single.body, {'weightKg': 81});
      expect(queued.single.attemptCount, 0);
      await database.close();
    },
  );
}
