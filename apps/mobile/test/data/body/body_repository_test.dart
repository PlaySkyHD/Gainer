import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';

const accountId = '00000000-0000-4000-8000-000000000001';

String testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

void main() {
  late LocalDatabase database;
  late BodyRepository repository;
  var databaseIsClosed = false;
  var id = 10;
  final now = DateTime.utc(2026, 10, 12, 9);

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    databaseIsClosed = false;
    repository = BodyRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
      ids: () => testId(id++),
      clock: () => now,
    );
  });

  tearDown(() async {
    if (!databaseIsClosed) await database.close();
  });

  test('switching active goals atomically ends the prior goal', () async {
    final firstId = await repository.activateGoal(
      kind: BodyGoalKind.bulk,
      startWeightKg: 70,
      targetWeightKg: 75,
      startDate: '2026-10-01',
      targetDate: '2027-01-01',
    );
    final secondId = await repository.activateGoal(
      kind: BodyGoalKind.cut,
      startWeightKg: 72,
      targetWeightKg: 68,
      startDate: '2026-10-12',
      targetDate: '2027-02-01',
    );

    final snapshot = await repository.read();
    expect(snapshot.activeGoal?.id, secondId);
    expect(snapshot.goalHistory.single.id, firstId);
    expect(snapshot.goalHistory.single.value.endedAtUtc, now.toIso8601String());
    final outbox = await repository.store.readOutbox(
      aggregateType: 'body-goal',
    );
    expect(outbox, hasLength(2));
    expect(outbox.last.dependsOnMutationId, outbox.first.mutationId);
    expect(
      (await repository.store.readAggregate('body-goal', firstId))!.workingCopy,
      containsPair('endedAtUtc', now.toIso8601String()),
    );
  });

  test(
    'daily check-in upserts by local date and preserves creation time',
    () async {
      final originalId = await repository.saveCheckIn(
        localDate: '2026-10-12',
        weightKg: 71,
        caloriesKcal: 2200,
        proteinGrams: 140,
        carbohydrateGrams: 250,
        fatGrams: 70,
        steps: 8500,
        sleepMinutes: 420,
      );
      final again = await repository.saveCheckIn(
        localDate: '2026-10-12',
        weightKg: 70.8,
        caloriesKcal: null,
        proteinGrams: 135,
        carbohydrateGrams: null,
        fatGrams: null,
        steps: null,
        sleepMinutes: null,
      );
      expect(again, originalId);
      final checkIn = (await repository.read()).checkIns.single.value;
      expect(checkIn.weightKg, 70.8);
      expect(checkIn.caloriesKcal, isNull);
      expect(checkIn.steps, isNull);
      expect(checkIn.createdAtUtc, now.toIso8601String());
      expect(checkIn.updatedAtUtc, now.toIso8601String());
    },
  );

  test(
    'goal activation fault rolls back new and previous goal changes',
    () async {
      await repository.activateGoal(
        kind: BodyGoalKind.bulk,
        startWeightKg: 70,
        targetWeightKg: 75,
        startDate: '2026-10-01',
        targetDate: null,
      );
      final failing = BodyRepository(
        store: repository.store,
        ids: () => testId(id++),
        clock: () => now,
        transactionFaultForTesting: () => throw StateError('injected rollback'),
      );

      await expectLater(
        failing.activateGoal(
          kind: BodyGoalKind.cut,
          startWeightKg: 70,
          targetWeightKg: 65,
          startDate: '2026-10-12',
          targetDate: null,
        ),
        throwsStateError,
      );
      final snapshot = await repository.read();
      expect(snapshot.activeGoal?.value.kind, BodyGoalKind.bulk);
      expect(snapshot.goalHistory, isEmpty);
      expect(
        await repository.store.readOutbox(aggregateType: 'body-goal'),
        hasLength(1),
      );
    },
  );

  test(
    'body goal and check-ins survive closing and reopening the SQLite file',
    () async {
      final directory = await Directory.systemTemp.createTemp('gainer-body-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}body.sqlite',
      );
      try {
        await database.close();
        databaseIsClosed = true;
        final firstDb = LocalDatabase(NativeDatabase.createInBackground(file));
        final firstRepo = BodyRepository(
          store: LocalSyncStore(database: firstDb, accountId: accountId),
          ids: () => testId(id++),
          clock: () => now,
        );
        await firstRepo.activateGoal(
          kind: BodyGoalKind.maintain,
          startWeightKg: 72,
          targetWeightKg: 72,
          startDate: '2026-10-12',
          targetDate: null,
        );
        await firstRepo.saveCheckIn(
          localDate: '2026-10-12',
          weightKg: 72,
          caloriesKcal: null,
          proteinGrams: null,
          carbohydrateGrams: null,
          fatGrams: null,
          steps: null,
          sleepMinutes: null,
        );
        await firstDb.close();

        final reopenedDb = LocalDatabase(
          NativeDatabase.createInBackground(file),
        );
        final reopenedRepository = BodyRepository(
          store: LocalSyncStore(database: reopenedDb, accountId: accountId),
          clock: () => now,
        );
        final reopened = await reopenedRepository.read();
        expect(reopened.activeGoal?.value.kind, BodyGoalKind.maintain);
        expect(reopened.checkIns.single.value.weightKg, 72);
        expect(await reopenedRepository.store.readOutbox(), hasLength(2));
        await reopenedDb.close();
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
