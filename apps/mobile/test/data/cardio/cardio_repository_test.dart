import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/data/repositories/health/cardio_health_exporter.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_draft.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';

const accountId = '00000000-0000-4000-8000-000000000001';
String testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

class _FakeHealth implements CardioHealthPlatform {
  final exports = <CardioHealthExport>[];
  var authorizations = 0;
  Object? failWith;

  @override
  Future<void> requestWriteAuthorization() async => authorizations++;

  @override
  Future<WorkoutExportReceipt> exportCardioSession(
    CardioHealthExport export,
  ) async {
    if (failWith != null) throw failWith!;
    exports.add(export);
    return WorkoutExportReceipt(
      status: HealthExportStatus.saved,
      syncIdentifier: 'gainer.cardio.${export.accountId}.${export.sessionId}',
      syncVersion: export.syncVersion,
    );
  }
}

CardioSession finished(String id, {List<int>? bpm}) => CardioSession(
  sessionId: id,
  startedAtUtc: DateTime.utc(2026, 10, 18, 10),
  endedAtUtc: DateTime.utc(2026, 10, 18, 10, 1),
  targetZone: const CardioTargetZone(lowBpm: 120, highBpm: 140),
  heartRateBpm: bpm ?? List.filled(12, 130),
  rrIntervalsMs: const [800, 810],
  sensorName: 'Polar H10',
  createdAtUtc: DateTime.utc(2026),
  updatedAtUtc: DateTime.utc(2026),
);

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  late CardioRepository repository;
  var nextId = 100;
  var now = DateTime.utc(2026, 10, 18, 10, 2);

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: accountId);
    nextId = 100;
    now = DateTime.utc(2026, 10, 18, 10, 2);
    repository = CardioRepository(
      store: store,
      ids: () => testId(nextId++),
      clock: () => now,
    );
  });

  tearDown(() => database.close());

  test('saveFinished creates a pending envelope and create mutation', () async {
    final id = repository.newSessionId();
    final saved = await repository.saveFinished(finished(id));
    expect(saved.createdAtUtc, now);
    final outbox = await store.readOutbox(
      aggregateType: cardioSessionAggregateType,
    );
    expect(outbox, hasLength(1));
    expect(outbox.single.operation, LocalMutationOperation.create);
    final payload = SyncPayloadCodec.serverPayload(
      outbox.single,
      outbox.single.body as Map<String, dynamic>,
      0,
    ) as Map<String, Object?>;
    expect(
      SyncPayloadCodec.serverOperation(
        outbox.single,
        outbox.single.body as Map<String, dynamic>,
      ),
      'saveCardioSession',
    );
    expect(payload['baseVersion'], 0);
    final session = payload['session'] as Map<String, Object?>;
    expect(session['sessionId'], id);
    expect(session['targetZone'], {'lowBpm': 120, 'highBpm': 140});
    expect(session.containsKey('createdAtUtc'), isFalse);
    expect(session.containsKey('notes'), isFalse);
    expect((await repository.readSessions()).single.sessionId, id);
  });

  test('lists newest first and hides deleted sessions', () async {
    final a = repository.newSessionId();
    final b = repository.newSessionId();
    await repository.saveFinished(finished(a));
    await repository.saveFinished(
      finished(b).copyWith(
        startedAtUtc: DateTime.utc(2026, 10, 19, 10),
        endedAtUtc: DateTime.utc(2026, 10, 19, 10, 1),
      ),
    );
    expect((await repository.readSessions()).map((s) => s.sessionId), [b, a]);
    await repository.deleteSession(b);
    expect((await repository.readSessions()).map((s) => s.sessionId), [a]);
    expect(await repository.readSession(b), isNull);
  });

  test('updateDetails writes an update and validates ranges', () async {
    final id = repository.newSessionId();
    await repository.saveFinished(finished(id));
    final updated = await repository.updateDetails(
      id,
      distanceKm: 14.2,
      averagePowerWatts: 165,
      notes: '  gut  ',
    );
    expect(updated.notes, 'gut');
    final outbox = await store.readOutbox(
      aggregateType: cardioSessionAggregateType,
    );
    // Der noch nicht gesendete Eintrag wird zusammengefasst.
    expect(outbox, isNotEmpty);
    expect((await repository.readSession(id))!.distanceKm, 14.2);
    expect(
      () => repository.updateDetails(id, distanceKm: 1001),
      throwsArgumentError,
    );
    expect(
      () => repository.updateDetails(id, averagePowerWatts: 3001),
      throwsArgumentError,
    );
    expect(
      () => repository.updateDetails(id, energyKcal: 20001),
      throwsArgumentError,
    );
    expect(
      () => repository.updateDetails(id, notes: 'x' * 2001),
      throwsArgumentError,
    );
  });

  test('deleting a not yet synced session drops the queued create', () async {
    final id = repository.newSessionId();
    await repository.saveFinished(finished(id));
    await repository.deleteSession(id);
    expect(await repository.readSession(id), isNull);
    expect(
      await store.readOutbox(aggregateType: cardioSessionAggregateType),
      isEmpty,
    );
  });

  test('draft is stored in sync metadata and can be cleared', () async {
    expect(await repository.readDraft(), isNull);
    final draft = CardioDraft(
      sessionId: 'abc',
      startedAtUtc: DateTime.utc(2026, 10, 18, 10),
      warmupSeconds: 180,
      buckets: const [100, 0],
    );
    await repository.writeDraft(draft);
    expect((await repository.readDraft())!.buckets, [100, 0]);
    expect(await store.readSyncMetadata('cardio-active-session'), isNotNull);
    await repository.clearDraft();
    expect(await repository.readDraft(), isNull);
  });

  test('preferences default, persist and compute zones', () async {
    final prefs = await repository.preferences.read();
    expect(prefs.lastZoneLow, 120);
    expect(prefs.warmupSeconds, 180);
    expect(prefs.alertsEnabled, isTrue);
    expect(prefs.zones, isEmpty);
    await repository.preferences.write(
      const CardioPreferenceValues(age: 30, restingHeartRate: null),
    );
    final back = await repository.preferences.read();
    expect(back.effectiveMaxHeartRate, 187);
    expect(back.zones[1].lowBpm, 112);
  });

  group('sanitize', () {
    test('clamps values the server would reject', () {
      final start = DateTime.utc(2026, 10, 18, 10);
      final dirty = CardioSession(
        sessionId: testId(1),
        startedAtUtc: start,
        endedAtUtc: start.add(const Duration(seconds: 12)),
        targetZone: const CardioTargetZone(lowBpm: 150, highBpm: 100),
        heartRateBpm: [10, 25, 250, 251, 130, 130, 130, 130, 130],
        rrIntervalsMs: [100, 200, 3000, 3001, 800],
        sensorName: 'x' * 150,
        distanceKm: 1500,
        averagePowerWatts: 200,
        energyKcal: -1,
        notes: 'n' * 3000,
        createdAtUtc: start,
        updatedAtUtc: start,
      );
      final clean = CardioRepository.sanitize(dirty);
      // ceil(12 / 5) + 1 = 4 Werte.
      expect(clean.heartRateBpm, [0, 25, 250, 0]);
      expect(clean.rrIntervalsMs, [200, 3000, 800]);
      expect(clean.targetZone, isNull);
      expect(clean.sensorName, hasLength(100));
      expect(clean.distanceKm, isNull);
      expect(clean.averagePowerWatts, 200);
      expect(clean.energyKcal, isNull);
      expect(clean.notes, hasLength(2000));
    });

    test('limits RR count, duration and end after start', () {
      final start = DateTime.utc(2026, 10, 18, 10);
      final dirty = CardioSession(
        sessionId: testId(1),
        startedAtUtc: start,
        endedAtUtc: start.add(const Duration(hours: 30)),
        heartRateBpm: List.filled(10000, 120),
        rrIntervalsMs: List.filled(45000, 800),
        createdAtUtc: start,
        updatedAtUtc: start,
      );
      final clean = CardioRepository.sanitize(dirty);
      expect(clean.endedAtUtc.difference(start), const Duration(hours: 24));
      expect(clean.rrIntervalsMs, hasLength(40000));
      expect(clean.heartRateBpm.length, lessThanOrEqualTo(24 * 720 + 1));
      final inverted = CardioRepository.sanitize(
        finished(testId(2)).copyWith(endedAtUtc: start),
      );
      expect(inverted.endedAtUtc.isAfter(start), isTrue);
    });

    test('saveFinished stores the sanitized series', () async {
      final id = repository.newSessionId();
      final saved = await repository.saveFinished(
        finished(id, bpm: [300, 130, 130]),
      );
      expect(saved.heartRateBpm, [0, 130, 130]);
      final body =
          (await store.readOutbox(aggregateType: cardioSessionAggregateType))
                  .single
                  .body
              as Map<String, dynamic>;
      expect(body['heartRateBpm'], [0, 130, 130]);
    });
  });

  group('CardioHealthExporter', () {
    late _FakeHealth health;
    late CardioHealthExporter exporter;

    setUp(() {
      health = _FakeHealth();
      exporter = CardioHealthExporter(
        store: store,
        repository: repository,
        platform: health,
        clock: () => now,
      );
    });

    test('exports with optimistic version and records the ledger', () async {
      final id = repository.newSessionId();
      await repository.saveFinished(finished(id));
      expect((await exporter.exportState(id)).exported, isFalse);
      final receipt = await exporter.export(id);
      expect(receipt.status, HealthExportStatus.saved);
      expect(health.authorizations, 1);
      expect(health.exports.single.syncVersion, 1);
      expect(health.exports.single.accountId, accountId);
      expect(health.exports.single.heartRateBpm, hasLength(12));
      final state = await exporter.exportState(id);
      expect(state.exported, isTrue);
      expect(state.syncVersion, 1);
      expect(
        await store.readSyncMetadata('health-ledger:cardio-export:$id'),
        isNotNull,
      );
    });

    test(
      'failure is recorded as retryable and keeps earlier success',
      () async {
        final id = repository.newSessionId();
        await repository.saveFinished(finished(id));
        health.failWith = StateError('boom');
        await expectLater(exporter.export(id), throwsStateError);
        var state = await exporter.exportState(id);
        expect(state.exported, isFalse);
        expect(state.failed, isTrue);
        health.failWith = null;
        await exporter.export(id);
        health.failWith = StateError('boom');
        await expectLater(exporter.export(id), throwsStateError);
        state = await exporter.exportState(id);
        expect(state.exported, isTrue);
      },
    );

    test('rejects unknown and deleted sessions', () async {
      await expectLater(exporter.export(testId(9)), throwsStateError);
      final id = repository.newSessionId();
      await repository.saveFinished(finished(id));
      await repository.deleteSession(id);
      await expectLater(exporter.export(id), throwsStateError);
    });
  });
}
