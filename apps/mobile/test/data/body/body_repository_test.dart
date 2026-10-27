import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart'
    show NutritionSaveException;
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';
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
        DailyCheckInInput(
          localDate: '2026-10-12',
          weightKg: 71,
          caloriesKcal: 2200,
          proteinGrams: 140,
          carbohydrateGrams: 250,
          fatGrams: 70,
          steps: 8500,
          sleepMinutes: 420,
        ),
      );
      final again = await repository.saveCheckIn(
        DailyCheckInInput(
          localDate: '2026-10-12',
          weightKg: 70.8,
          caloriesKcal: null,
          proteinGrams: 135,
          carbohydrateGrams: null,
          fatGrams: null,
          steps: null,
          sleepMinutes: null,
        ),
      );
      expect(again, originalId);
      final checkIn = (await repository.read()).checkIns.single.value;
      expect(checkIn.weightKg, 70.8);
      // null heißt „nicht übergeben“: die bisherigen Werte bleiben.
      expect(checkIn.caloriesKcal, 2200);
      expect(checkIn.steps, 8500);
      expect(checkIn.sleepMinutes, 420);
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
          DailyCheckInInput(
            localDate: '2026-10-12',
            weightKg: 72,
            caloriesKcal: null,
            proteinGrams: null,
            carbohydrateGrams: null,
            fatGrams: null,
            steps: null,
            sleepMinutes: null,
          ),
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

  group('gleichzeitige Check-in-Schreiber', () {
    DailyCheckInInput input({double? calories, int? steps}) =>
        DailyCheckInInput(
          localDate: '2026-10-12',
          weightKg: 71,
          caloriesKcal: calories,
          proteinGrams: null,
          carbohydrateGrams: null,
          fatGrams: null,
          steps: steps,
          sleepMinutes: null,
        );

    test('updateSteps und saveCheckIn am selben Tag behalten beide', () async {
      await repository.saveCheckIn(input(calories: 2000, steps: 1000));
      await Future.wait([
        repository.updateSteps(localDate: '2026-10-12', steps: 9000),
        repository.saveCheckIn(input(calories: 2500)),
      ]);
      final value = (await repository.read()).checkIns.single.value;
      expect(value.steps, 9000);
      expect(value.caloriesKcal, 2500);
    });

    test('zwei Schreiber an einem Tag ohne Check-in legen einen an', () async {
      final ids = await Future.wait([
        repository.saveCheckIn(input(calories: 2000)),
        repository.saveCheckIn(input(steps: 500)),
      ]);
      expect(ids.toSet(), hasLength(1));
      final snapshot = await repository.read();
      expect(snapshot.checkIns, hasLength(1));
      expect(snapshot.checkIns.single.value.caloriesKcal, 2000);
      expect(snapshot.checkIns.single.value.steps, 500);
    });

    test(
      'liest neu, wenn der Check-in beim Commit schon geändert ist',
      () async {
        await repository.saveCheckIn(input(calories: 2000, steps: 1000));
        // Zweite Instanz auf demselben Speicher: eigene Warteschlange, wie ein
        // Pull oder eine Bestätigung zwischen Lesen und Commit.
        final other = BodyRepository(
          store: repository.store,
          ids: () => testId(id++),
          clock: () => now,
        );
        var interfered = false;
        repository.beforeCheckInCommitForTesting = () async {
          if (interfered) return;
          interfered = true;
          await other.updateSteps(localDate: '2026-10-12', steps: 9000);
        };
        await repository.saveCheckIn(input(calories: 2500));
        final value = (await repository.read()).checkIns.single.value;
        expect(value.steps, 9000);
        expect(value.caloriesKcal, 2500);
      },
    );
  });

  group('Check-in-Konflikte', () {
    test(
      'flushPendingResting überspringt einen Konflikt statt zu werfen',
      () async {
        await repository.recordRestingMeasurement(
          localDate: '2026-10-12',
          restingHeartRateBpm: 58,
          restingHrvMs: 52,
        );
        await repository.saveCheckIn(
          DailyCheckInInput(
            localDate: '2026-10-12',
            weightKg: 71,
            caloriesKcal: null,
            proteinGrams: null,
            carbohydrateGrams: null,
            fatGrams: null,
            steps: null,
            sleepMinutes: null,
          ),
        );
        // saveCheckIn hat den wartenden Wert übernommen; erneut wartend setzen
        // und den Check-in unter dem Flush ändern.
        final other = BodyRepository(
          store: repository.store,
          ids: () => testId(id++),
          clock: () => now,
        );
        await repository.store.writeSyncMetadata('body-resting-pending', {
          '2026-10-12': {'restingHeartRateBpm': 60, 'restingHrvMs': 40},
        });
        var steps = 100;
        repository.beforeCheckInCommitForTesting = () =>
            other.updateSteps(localDate: '2026-10-12', steps: steps++);
        await repository.flushPendingResting();
        final snapshot = await repository.read();
        expect(snapshot.pendingResting, hasLength(1));
        expect(snapshot.checkIns, hasLength(1));
      },
    );

    DailyCheckInInput input(double? calories) => DailyCheckInInput(
      localDate: '2026-10-12',
      weightKg: 71,
      caloriesKcal: calories,
      proteinGrams: null,
      carbohydrateGrams: null,
      fatGrams: null,
      steps: null,
      sleepMinutes: null,
    );

    test('dauerhafter Konflikt wird zur deutschen Meldung', () async {
      await repository.saveCheckIn(input(2000));
      final other = BodyRepository(
        store: repository.store,
        ids: () => testId(id++),
        clock: () => now,
      );
      var steps = 100;
      repository.beforeCheckInCommitForTesting = () =>
          other.updateSteps(localDate: '2026-10-12', steps: steps++);
      await expectLater(
        repository.saveCheckIn(input(2500)),
        throwsA(
          isA<NutritionSaveException>().having(
            (e) => e.toString(),
            'message',
            contains('Bitte versuche es noch einmal'),
          ),
        ),
      );
    });

    test('Health-Import wiederholt einen Konflikt höchstens dreimal', () async {
      await repository.saveCheckIn(input(2000));
      final other = BodyRepository(
        store: repository.store,
        ids: () => testId(id++),
        clock: () => now,
      );
      var steps = 100;
      var attempts = 0;
      repository.beforeCheckInCommitForTesting = () async {
        attempts++;
        await other.updateSteps(localDate: '2026-10-12', steps: steps++);
      };
      await expectLater(
        repository.importHealthWeight(
          probeId: 'p1',
          localDate: '2026-10-12',
          weightKg: 70,
          replaceExistingCheckIn: true,
          sessionGuard: () => true,
        ),
        throwsA(isA<NutritionSaveException>()),
      );
      // Eine Wiederholungsschicht: genau drei Versuche, nicht neun.
      expect(attempts, 3);
    });
  });

  group('Ruhepuls und HRV', () {
    Future<String> checkIn(String date, {double weight = 71}) =>
        repository.saveCheckIn(
          DailyCheckInInput(
            localDate: date,
            weightKg: weight,
            caloriesKcal: 2200,
            proteinGrams: null,
            carbohydrateGrams: null,
            fatGrams: null,
            steps: 8000,
            sleepMinutes: 420,
          ),
        );

    test(
      'korrigiert einen vorhandenen Check-in und sendet die Werte',
      () async {
        final id = await checkIn('2026-10-12');
        final status = await repository.recordRestingMeasurement(
          localDate: '2026-10-12',
          restingHeartRateBpm: 58,
          restingHrvMs: 52,
        );
        expect(status, RestingMeasurementStatus.savedToCheckIn);
        final value = (await repository.read()).checkIns.single.value;
        expect((value.restingHeartRateBpm, value.restingHrvMs), (58, 52));
        expect(value.weightKg, 71);
        expect(value.caloriesKcal, 2200);
        final outbox = await repository.store.readOutbox(
          aggregateType: 'daily-check-in',
        );
        final last = outbox.last;
        final payload = SyncPayloadCodec.serverPayload(
          last,
          last.body as Map<String, dynamic>,
          1,
        ) as Map<String, Object?>;
        expect(payload['checkInId'], id);
        final values = payload['values'] as Map<String, Object?>;
        expect(values['restingHeartRateBpm'], 58);
        expect(values['restingHrvMs'], 52);
        expect(values['weightKg'], 71);
      },
    );

    test(
      'ohne Check-in wartet der Wert und kommt beim Speichern mit',
      () async {
        final status = await repository.recordRestingMeasurement(
          localDate: '2026-10-12',
          restingHeartRateBpm: 60,
          restingHrvMs: 48,
        );
        expect(status, RestingMeasurementStatus.pending);
        var snapshot = await repository.read();
        expect(snapshot.checkIns, isEmpty);
        expect(snapshot.pendingResting.single.isPending, isTrue);
        expect(snapshot.restingEntries.single.restingHrvMs, 48);
        expect(await repository.store.readOutbox(), isEmpty);

        await checkIn('2026-10-12');
        snapshot = await repository.read();
        expect(snapshot.pendingResting, isEmpty);
        final value = snapshot.checkIns.single.value;
        expect((value.restingHeartRateBpm, value.restingHrvMs), (60, 48));
        // Ein späteres Speichern des Check-ins behält die Werte.
        await checkIn('2026-10-12', weight: 70);
        expect(
          (await repository.read()).checkIns.single.value.restingHrvMs,
          48,
        );
      },
    );

    test('flushPendingResting überträgt Werte in einen später entstandenen Check-in', () async {
      await repository.recordRestingMeasurement(
        localDate: '2026-10-12',
        restingHeartRateBpm: 60,
        restingHrvMs: 48,
      );
      await repository.recordRestingMeasurement(
        localDate: '2026-10-11',
        restingHeartRateBpm: 61,
        restingHrvMs: 40,
      );
      // Der Check-in entsteht am Repository vorbei (z. B. Health-Import).
      await repository.importHealthWeight(
        probeId: 'probe-1',
        localDate: '2026-10-12',
        weightKg: 70,
        replaceExistingCheckIn: false,
        sessionGuard: () => true,
      );
      await repository.flushPendingResting();
      final snapshot = await repository.read();
      expect(snapshot.checkIns.single.value.restingHrvMs, 48);
      // Tage ohne Check-in warten weiter.
      expect(snapshot.pendingResting.single.localDate, '2026-10-11');
    });

    test('lehnt Werte außerhalb der Grenzen ab', () async {
      for (final (rate, hrv) in [(24, 50), (151, 50), (60, 0), (60, 301)]) {
        await expectLater(
          repository.recordRestingMeasurement(
            localDate: '2026-10-12',
            restingHeartRateBpm: rate,
            restingHrvMs: hrv,
          ),
          throwsA(isA<BodyTrackingValidationException>()),
        );
      }
    });

    test('Check-in ohne Ruhewerte sendet die Schlüssel nicht', () async {
      await checkIn('2026-10-12');
      final outbox = await repository.store.readOutbox(
        aggregateType: 'daily-check-in',
      );
      final payload = SyncPayloadCodec.serverPayload(
        outbox.single,
        outbox.single.body as Map<String, dynamic>,
        0,
      ) as Map<String, Object?>;
      final values = payload['values'] as Map<String, Object?>;
      expect(values.containsKey('restingHeartRateBpm'), isFalse);
      expect(values.containsKey('restingHrvMs'), isFalse);
    });
  });
}
