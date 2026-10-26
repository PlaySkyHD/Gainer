import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_status.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';

const _accountId = 'a1234567-1234-4234-8234-123456789abc';
const _planId = 'b1234567-1234-4234-8234-123456789abc';

SyncRunReport _report(SyncRunState state) =>
    SyncRunReport(state: state, pushed: 0, pulledBatches: 0);

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  late SyncStatusTracker tracker;
  final now = DateTime.utc(2026, 10, 18, 12);
  var disposed = false;

  setUp(() {
    disposed = false;
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _accountId);
    tracker = SyncStatusTracker(store: store);
  });

  tearDown(() async {
    if (!disposed) tracker.dispose();
    await database.close();
  });

  Future<void> commitPlan(String mutationId) => store.commitMutation(
    mutationId: mutationId,
    aggregateType: 'training-plan',
    aggregateId: _planId,
    operation: LocalMutationOperation.create,
    baseVersion: 0,
    body: {'name': 'Push'},
    envelope: localEnvelope(
      aggregateId: _planId,
      workingCopy: {'name': 'Push'},
    ),
  );

  test('starts as writer without sync time and nothing pending', () async {
    await tracker.load();

    expect(tracker.value.isWriter, isTrue);
    expect(tracker.value.lastSyncedAtUtc, isNull);
    expect(tracker.value.pendingCount, 0);
  });

  test('counts every outbox entry the server has not confirmed', () async {
    await commitPlan('c1234567-1234-4234-8234-123456789abc');
    await tracker.refreshPending();
    expect(tracker.value.pendingCount, 1);

    await store.updateMutation(
      (await store.readOutbox()).single.let(
        (m) => LocalMutation(
          mutationId: m.mutationId,
          accountId: m.accountId,
          aggregateType: m.aggregateType,
          aggregateId: m.aggregateId,
          sequence: m.sequence,
          status: LocalMutationStatus.clean,
          createdAtUtc: m.createdAtUtc,
          operation: m.operation,
          baseVersion: m.baseVersion,
          body: m.body,
        ),
      ),
    );
    await tracker.refreshPending();
    expect(tracker.value.pendingCount, 0);
  });

  test(
    'scheduled refreshes collapse into one count after a short delay',
    () async {
      var notified = 0;
      tracker.addListener(() => notified++);
      await commitPlan('c1234567-1234-4234-8234-123456789abc');

      tracker.scheduleRefresh();
      tracker.scheduleRefresh();
      tracker.scheduleRefresh();
      expect(tracker.value.pendingCount, 0);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(tracker.value.pendingCount, 1);
      expect(notified, 1);
    },
  );

  test('a scheduled refresh is dropped when the tracker is disposed', () async {
    final timers = <Timer>[];
    void schedule() => runZoned(
      () => tracker.scheduleRefresh(),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createTimer(zone, duration, callback);
          timers.add(timer);
          return timer;
        },
      ),
    );

    schedule();
    expect(timers, hasLength(1));
    expect(timers.single.isActive, isTrue);

    tracker.dispose();
    disposed = true;
    expect(timers.single.isActive, isFalse);

    // Nach dem Schließen startet kein neuer Timer mehr.
    schedule();
    expect(timers, hasLength(1));
  });

  test('a finished run stores the time and survives a restart', () async {
    await tracker.recordRun(_report(SyncRunState.synced), now);

    expect(tracker.value.lastSyncedAtUtc, now);
    expect(tracker.value.isWriter, isTrue);

    final restarted = SyncStatusTracker(store: store);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.value.lastSyncedAtUtc, now);
  });

  test(
    'another writing device shows up as not writer until taken over',
    () async {
      await tracker.recordRun(_report(SyncRunState.inactiveClient), now);
      expect(tracker.value.isWriter, isFalse);
      expect(tracker.value.lastSyncedAtUtc, now);

      await tracker.recordRun(
        _report(SyncRunState.synced),
        now.add(const Duration(minutes: 1)),
      );
      expect(tracker.value.isWriter, isTrue);
    },
  );

  test(
    'runs that never reached the server keep time and writer state',
    () async {
      await tracker.recordRun(_report(SyncRunState.inactiveClient), now);

      for (final state in [
        SyncRunState.authBlocked,
        SyncRunState.upgradeRequired,
        SyncRunState.busy,
      ]) {
        await tracker.recordRun(
          _report(state),
          now.add(const Duration(hours: 1)),
        );
      }

      expect(tracker.value.isWriter, isFalse);
      expect(tracker.value.lastSyncedAtUtc, now);
    },
  );

  test(
    'a required update stays visible until a run reaches the server',
    () async {
      await tracker.recordRun(_report(SyncRunState.upgradeRequired), now);
      expect(tracker.value.upgradeRequired, isTrue);

      // Läufe, die den Server nicht erreichen, ändern nichts am Hinweis.
      for (final state in [SyncRunState.busy, SyncRunState.authBlocked]) {
        await tracker.recordRun(_report(state), now);
        expect(tracker.value.upgradeRequired, isTrue, reason: state.name);
      }

      await tracker.recordRun(_report(SyncRunState.synced), now);
      expect(tracker.value.upgradeRequired, isFalse);
    },
  );

  test('listeners are told only about real changes', () async {
    var notified = 0;
    tracker.addListener(() => notified++);

    await tracker.refreshPending();
    await tracker.refreshPending();

    expect(notified, 0);
  });

  test('a late result after dispose is ignored without error', () async {
    await commitPlan('c1234567-1234-4234-8234-123456789abc');
    tracker.dispose();
    disposed = true;

    await tracker.recordRun(_report(SyncRunState.synced), now);
    await tracker.load();
    await tracker.refreshPending();

    // Nichts davon darf den Status ändern oder den Zeitpunkt speichern.
    expect(tracker.value.pendingCount, 0);
    expect(tracker.value.lastSyncedAtUtc, isNull);
    expect(await store.readSyncMetadata('last-synced-at'), isNull);
  });

  test('an unreadable store does not throw out of the tracker', () async {
    final broken = SyncStatusTracker(store: _BrokenStore(database));
    addTearDown(broken.dispose);

    await broken.refreshPending();
    await broken.recordRun(_report(SyncRunState.synced), now);

    expect(broken.value.pendingCount, 0);
  });

  test('equal states compare equal', () {
    expect(
      SyncStatus(lastSyncedAtUtc: now, pendingCount: 2, isWriter: false),
      SyncStatus(lastSyncedAtUtc: now, pendingCount: 2, isWriter: false),
    );
    expect(
      SyncStatus(lastSyncedAtUtc: now, pendingCount: 2).hashCode,
      SyncStatus(lastSyncedAtUtc: now, pendingCount: 2).hashCode,
    );
    expect(const SyncStatus(), isNot(const SyncStatus(pendingCount: 1)));
  });
}

class _BrokenStore extends LocalSyncStore {
  _BrokenStore(LocalDatabase database)
    : super(database: database, accountId: _accountId);

  @override
  Future<List<LocalMutation>> readOutbox({String? aggregateType}) =>
      throw StateError('Speicher nicht lesbar.');
}

extension<T> on T {
  R let<R>(R Function(T value) block) => block(this);
}
