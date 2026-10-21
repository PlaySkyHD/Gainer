import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/repositories/training/training_schedule_repository.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_validation.dart';

const _account = '00000000-0000-4000-8000-000000000007';

String _testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

class _NoCatalog implements ExerciseCatalogProvider {
  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async =>
      const BaseCatalog(exercises: [], categories: []);
}

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  late TrainingLogRepository training;
  late TrainingScheduleRepository repository;
  var id = 100;
  // Samstag, 17.10.2026, mittags in jeder üblichen Zeitzone.
  var now = DateTime.utc(2026, 10, 17, 11);

  setUp(() {
    id = 100;
    now = DateTime.utc(2026, 10, 17, 11);
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _account);
    training = TrainingLogRepository(
      store: store,
      catalog: _NoCatalog(),
      ids: () => _testId(id++),
      clock: () => now,
    );
    repository = training.schedule;
  });

  tearDown(() => database.close());

  Future<TrainingPlanModel> plan(String name) => training.createPlan(
    TrainingPlanModel(
      planId: training.newId(),
      name: name,
      previousValueSource: PreviousValueSource.exercise,
    ),
  );

  Future<List<LocalMutation>> scheduleOutbox() =>
      store.readOutbox(aggregateType: trainingScheduleAggregateType);

  /// Tut so, als hätte der Server den aktuellen Stand in [version] bestätigt.
  Future<void> markSynced(int version) async {
    final schedule = (await repository.read())!;
    await database.delete(database.localOutbox).go();
    await database
        .into(database.localResources)
        .insertOnConflictUpdate(
          LocalResourcesCompanion.insert(
            aggregateType: trainingScheduleAggregateType,
            aggregateId: schedule.scheduleId,
            envelopeJson: serverEnvelope(
              aggregateId: schedule.scheduleId,
              snapshot: schedule.toJson(),
              version: version,
            ).encode(),
            updatedAtEpochMs: 0,
          ),
        );
  }

  test('creates a cycle with today as the chosen slot', () async {
    final push = await plan('Push');
    final pull = await plan('Pull');
    final saved = await repository.saveRhythm(
      mode: TrainingScheduleMode.cycle,
      slots: [
        TrainingScheduleSlot(planId: push.planId),
        TrainingScheduleSlot(planId: pull.planId),
        const TrainingScheduleSlot.rest(),
      ],
      todaySlotIndex: 1,
    );

    expect(repository.today(), LocalDay(2026, 10, 17));
    expect(saved.validFrom, LocalDay(2026, 10, 17));
    expect(saved.anchorDate, LocalDay(2026, 10, 16));
    expect(await repository.read(), isNotNull);
    final outbox = await scheduleOutbox();
    expect(outbox, hasLength(1));
    expect(outbox.single.operation, LocalMutationOperation.create);
    expect(outbox.single.baseVersion, 0);
    expect(
      SyncPayloadCodec.serverOperation(
        outbox.single,
        outbox.single.body! as Map<String, dynamic>,
      ),
      'saveTrainingSchedule',
    );

    final projection = await repository.readProjection();
    expect(
      projection.day(repository.today()).effective.single.planName,
      'Pull',
    );
  });

  test('rejects rest days only and unknown plans', () async {
    await plan('Push');
    await expectLater(
      repository.saveRhythm(
        mode: TrainingScheduleMode.cycle,
        slots: const [TrainingScheduleSlot.rest()],
      ),
      throwsA(isA<WorkoutValidationException>()),
    );
    await expectLater(
      repository.saveRhythm(
        mode: TrainingScheduleMode.cycle,
        slots: [
          TrainingScheduleSlot(planId: (await plan('Pull')).planId),
          const TrainingScheduleSlot(planId: 'unbekannt'),
        ],
      ),
      throwsA(isA<WorkoutValidationException>()),
    );
    expect(await repository.read(), isNull);
    expect(await scheduleOutbox(), isEmpty);
  });

  test(
    'offline: skip today and move tomorrow coalesce into one entry',
    () async {
      final push = await plan('Push');
      final pull = await plan('Pull');
      await repository.saveRhythm(
        mode: TrainingScheduleMode.cycle,
        slots: [
          TrainingScheduleSlot(planId: push.planId),
          TrainingScheduleSlot(planId: pull.planId),
          const TrainingScheduleSlot.rest(),
        ],
      );
      await markSynced(4);

      final today = repository.today();
      var projection = await repository.readProjection();
      await repository.applyAction(
        projection.day(today).trainings.single,
        const ScheduleAction.skip(),
      );
      projection = await repository.readProjection();
      final tomorrow = projection.day(today.addDays(1)).trainings.single;
      await repository.applyAction(
        tomorrow,
        ScheduleAction.moveSingle(today.addDays(2)),
      );

      final outbox = await scheduleOutbox();
      expect(outbox, hasLength(1));
      expect(outbox.single.operation, LocalMutationOperation.update);
      expect(outbox.single.baseVersion, 4);
      final body = outbox.single.body! as Map<String, dynamic>;
      final payload =
          SyncPayloadCodec.serverPayload(outbox.single, body, 4)!
              as Map<String, Object?>;
      expect(payload['exceptions'], [
        {'date': today.toIso(), 'planId': push.planId, 'movedToDate': null},
        {
          'date': today.addDays(1).toIso(),
          'planId': pull.planId,
          'movedToDate': today.addDays(2).toIso(),
        },
      ]);

      projection = await repository.readProjection();
      expect(
        projection.day(today).trainings.single.status,
        ScheduledTrainingStatus.skipped,
      );
      expect(
        projection.day(today.addDays(2)).effective.map((t) => t.planName),
        ['Pull'],
      );
      final envelope = await store.readAggregate(
        trainingScheduleAggregateType,
        body['scheduleId'] as String,
      );
      expect(envelope!.syncState, LocalSyncState.pending);
      expect(envelope.serverVersion, 4);
    },
  );

  test('schedule mutation waits for an unsent plan', () async {
    final push = await plan('Push');
    await repository.saveRhythm(
      mode: TrainingScheduleMode.cycle,
      slots: [TrainingScheduleSlot(planId: push.planId)],
    );
    final mutation = (await scheduleOutbox()).single;
    expect(SyncPayloadCodec.referencedAggregateIds(mutation), {push.planId});
  });

  test(
    'changing the rhythm resets valid-from, shifts and exceptions',
    () async {
      final push = await plan('Push');
      final pull = await plan('Pull');
      await repository.saveRhythm(
        mode: TrainingScheduleMode.cycle,
        slots: [
          TrainingScheduleSlot(planId: push.planId),
          TrainingScheduleSlot(planId: pull.planId),
        ],
      );
      var projection = await repository.readProjection();
      await repository.applyAction(
        projection.day(repository.today()).trainings.single,
        const ScheduleAction.shiftRhythm(1),
      );
      expect((await repository.read())!.shifts, hasLength(1));

      now = now.add(const Duration(days: 2));
      final changed = await repository.saveRhythm(
        mode: TrainingScheduleMode.weekly,
        slots: [
          TrainingScheduleSlot(planId: pull.planId),
          for (var i = 0; i < 6; i++) const TrainingScheduleSlot.rest(),
        ],
      );
      expect(changed.validFrom, LocalDay(2026, 10, 19));
      expect(changed.shifts, isEmpty);
      expect(changed.exceptions, isEmpty);
      expect(changed.anchorDate, isNull);
      expect(await scheduleOutbox(), hasLength(1));
      projection = await repository.readProjection();
      expect(projection.day(LocalDay(2026, 10, 18)).trainings, isEmpty);
    },
  );

  test('saving an unchanged rhythm writes nothing', () async {
    final push = await plan('Push');
    final slots = [
      TrainingScheduleSlot(planId: push.planId),
      const TrainingScheduleSlot.rest(),
    ];
    final first = await repository.saveRhythm(
      mode: TrainingScheduleMode.cycle,
      slots: slots,
    );
    await markSynced(1);
    final again = await repository.saveRhythm(
      mode: TrainingScheduleMode.cycle,
      slots: slots,
    );
    expect(again.scheduleId, first.scheduleId);
    expect(await scheduleOutbox(), isEmpty);
  });

  test('deleting a never sent schedule discards it completely', () async {
    final push = await plan('Push');
    await repository.saveRhythm(
      mode: TrainingScheduleMode.cycle,
      slots: [TrainingScheduleSlot(planId: push.planId)],
    );
    await repository.delete();
    expect(await repository.read(), isNull);
    expect(await scheduleOutbox(), isEmpty);
    expect(await store.readAggregates(trainingScheduleAggregateType), isEmpty);
  });

  test('deleting a synced schedule queues a delete and hides it', () async {
    final push = await plan('Push');
    final first = await repository.saveRhythm(
      mode: TrainingScheduleMode.cycle,
      slots: [TrainingScheduleSlot(planId: push.planId)],
    );
    await markSynced(3);
    await repository.delete();

    expect(await repository.read(), isNull);
    final outbox = (await scheduleOutbox()).single;
    expect(outbox.operation, LocalMutationOperation.delete);
    expect(
      SyncPayloadCodec.serverOperation(
        outbox,
        outbox.body! as Map<String, dynamic>,
      ),
      'deleteTrainingSchedule',
    );
    expect(
      SyncPayloadCodec.serverPayload(
        outbox,
        outbox.body! as Map<String, dynamic>,
        3,
      ),
      {'scheduleId': first.scheduleId, 'baseVersion': 3},
    );
    final projection = await repository.readProjection();
    expect(projection.schedule, isNull);

    // Ein neuer Rhythmus bekommt eine neue ID.
    final next = await repository.saveRhythm(
      mode: TrainingScheduleMode.cycle,
      slots: [TrainingScheduleSlot(planId: push.planId)],
    );
    expect(next.scheduleId, isNot(first.scheduleId));
    expect((await repository.read())!.scheduleId, next.scheduleId);
  });

  test('a finished workout from the plan marks today as done', () async {
    final push = await plan('Push');
    await repository.saveRhythm(
      mode: TrainingScheduleMode.cycle,
      slots: [
        TrainingScheduleSlot(planId: push.planId),
        const TrainingScheduleSlot.rest(),
      ],
    );
    final workout = await training.startFromPlan(push.planId);
    now = now.add(const Duration(minutes: 50));
    await training.finishWorkout(workout.workoutId);

    final projection = await repository.readProjection();
    expect(
      projection.day(repository.today()).trainings.single.status,
      ScheduledTrainingStatus.done,
    );

    await training.deleteWorkout(workout.workoutId);
    final afterDelete = await repository.readProjection();
    expect(
      afterDelete.day(repository.today()).trainings.single.status,
      ScheduledTrainingStatus.planned,
    );
  });

  test('an action that is not allowed is rejected', () async {
    final push = await plan('Push');
    await repository.saveRhythm(
      mode: TrainingScheduleMode.weekly,
      slots: List.filled(7, TrainingScheduleSlot(planId: push.planId)),
    );
    final projection = await repository.readProjection();
    await expectLater(
      repository.applyAction(
        projection.day(repository.today()).trainings.single,
        const ScheduleAction.shiftRhythm(1),
      ),
      throwsStateError,
    );
  });
}
