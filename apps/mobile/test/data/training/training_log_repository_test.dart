import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_validation.dart';

const _accountA = '00000000-0000-4000-8000-000000000002';
const _accountB = '00000000-0000-4000-8000-000000000003';
const _squat = '00000000-0000-4000-8000-0000000000a1';
const _row = '00000000-0000-4000-8000-0000000000a2';
const _category = '00000000-0000-4000-8000-0000000000c1';

String testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

class _FixtureCatalog implements ExerciseCatalogProvider {
  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async => const BaseCatalog(
    exercises: [
      CatalogExercise(
        id: _squat,
        name: 'Kniebeuge',
        exerciseType: ExerciseKind.strength,
        isBase: true,
        categoryIds: [_category],
      ),
      CatalogExercise(
        id: _row,
        name: 'Rudern',
        exerciseType: ExerciseKind.strength,
        isBase: true,
      ),
    ],
    categories: [CatalogCategory(id: _category, name: 'Beine', isBase: true)],
  );
}

void main() {
  late LocalDatabase database;
  late LocalSyncStore store;
  late TrainingLogRepository repository;
  var id = 100;
  var now = DateTime.utc(2026, 10, 17, 9);

  String nextId() => testId(id++);

  setUp(() {
    id = 100;
    now = DateTime.utc(2026, 10, 17, 9);
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _accountA);
    repository = TrainingLogRepository(
      store: store,
      catalog: _FixtureCatalog(),
      ids: nextId,
      clock: () => now,
    );
  });

  tearDown(() async {
    await database.close();
  });

  void advance([Duration by = const Duration(hours: 1)]) => now = now.add(by);

  Future<void> markOutboxSent() => database
      .update(database.localOutbox)
      .write(const LocalOutboxCompanion(status: Value('clean')));

  /// Schreibt einen bereits synchronisierten Eintrag direkt in den Store.
  Future<void> seedServer(
    String aggregateType,
    String aggregateId,
    Object snapshot,
  ) async {
    await store.ensureAccountBound();
    await database
        .into(database.localResources)
        .insertOnConflictUpdate(
          LocalResourcesCompanion.insert(
            aggregateType: aggregateType,
            aggregateId: aggregateId,
            envelopeJson: serverEnvelope(
              aggregateId: aggregateId,
              snapshot: snapshot,
              version: 1,
            ).encode(),
            updatedAtEpochMs: now.millisecondsSinceEpoch,
          ),
        );
  }

  /// Ein beendetes Training mit einer Übung und einem Satz.
  Future<Workout> finishedWorkout({
    required String title,
    double? weightKg,
    int? repetitions,
    String? exerciseId,
  }) async {
    final started = await repository.startEmpty(title: title);
    final block = WorkoutBlock(
      workoutExerciseId: nextId(),
      sourceExerciseId: exerciseId ?? _squat,
      exerciseNameSnapshot: 'Kniebeuge',
      exerciseTypeSnapshot: ExerciseKind.strength,
      sets: [
        LoggedSet(
          setId: nextId(),
          weightKg: weightKg,
          repetitions: repetitions,
        ),
      ],
    );
    await repository.saveWorkout(started.copyWith(exercises: [block]));
    advance(const Duration(minutes: 30));
    final finished = await repository.finishWorkout(started.workoutId);
    advance();
    return finished;
  }

  test(
    'startEmpty creates one active workout with one create mutation',
    () async {
      final workout = await repository.startEmpty(title: 'Freies Training');

      expect(workout.isActive, isTrue);
      expect(workout.startedAtUtc, now);
      expect(
        (await repository.readActiveWorkout())?.workoutId,
        workout.workoutId,
      );
      final outbox = await store.readOutbox();
      expect(outbox.single.operation, LocalMutationOperation.create);
      expect(outbox.single.aggregateType, 'workout');
      expect(outbox.single.baseVersion, 0);
    },
  );

  test(
    'startFromPlan lists warm-up sets before working sets, all without values',
    () async {
      await repository.createPlan(
        TrainingPlanModel(
          planId: nextId(),
          name: 'Beine',
          previousValueSource: PreviousValueSource.plan,
          entries: [
            PlanEntry(
              entryId: nextId(),
              exerciseId: _squat,
              warmupSets: 1,
              workingSets: 2,
            ),
          ],
        ),
      );
      final plan = (await repository.readPlans()).single;

      final workout = await repository.startFromPlan(plan.planId);

      expect(workout.title, 'Beine');
      expect(workout.sourcePlanId, plan.planId);
      expect(workout.previousValueSource, PreviousValueSource.plan);
      final sets = workout.exercises.single.sets;
      expect(sets.map((set) => set.setType), [
        SetType.warmup,
        SetType.normal,
        SetType.normal,
      ]);
      expect(sets.every((set) => set.weightKg == null), isTrue);
    },
  );

  test(
    'startRepeat keeps structure and set types and records the chosen source',
    () async {
      final source = await finishedWorkout(
        title: 'A',
        weightKg: 60,
        repetitions: 8,
      );

      final repeat = await repository.startRepeat(
        source.workoutId,
        previousValueSource: PreviousValueSource.workout,
      );

      expect(repeat.sourceWorkoutId, source.workoutId);
      expect(repeat.previousValueSource, PreviousValueSource.workout);
      expect(repeat.exercises.single.sourceExerciseId, _squat);
      expect(repeat.exercises.single.sets.single.weightKg, isNull);
      expect(repeat.exercises.single.sets.single.repetitions, isNull);
    },
  );

  test('two starts at the same time create only one active workout', () async {
    // Doppeltipp auf „Starten“: beide Aufrufe laufen gleichzeitig los.
    final results = await Future.wait([
      repository.startEmpty().then<Object>((w) => w, onError: (Object e) => e),
      repository.startEmpty().then<Object>((w) => w, onError: (Object e) => e),
    ]);

    expect(results.whereType<Workout>(), hasLength(1));
    expect(results.whereType<ActiveWorkoutExistsException>(), hasLength(1));
    expect(
      (await repository.readDiary()).where((w) => w.isActive),
      hasLength(1),
    );
  });

  test('a second active workout is rejected with its own error', () async {
    final first = await repository.startEmpty();

    await expectLater(
      repository.startEmpty(),
      throwsA(
        isA<ActiveWorkoutExistsException>().having(
          (error) => error.workoutId,
          'workoutId',
          first.workoutId,
        ),
      ),
    );
    expect((await repository.readDiary()).length, 1);
  });

  test('changing one set twice leaves exactly one pending mutation', () async {
    final workout = await repository.startEmpty();
    await markOutboxSent();
    final block = WorkoutBlock(
      workoutExerciseId: nextId(),
      sourceExerciseId: _squat,
      exerciseNameSnapshot: 'Kniebeuge',
      exerciseTypeSnapshot: ExerciseKind.strength,
      sets: [LoggedSet(setId: nextId())],
    );
    final withBlock = await repository.saveWorkout(
      workout.copyWith(exercises: [block]),
    );
    final edited = withBlock.copyWith(
      exercises: [
        block.copyWith(sets: [block.sets.single.copyWith(weightKg: () => 80)]),
      ],
    );
    await repository.saveWorkout(edited);
    final secondEdit = edited.copyWith(
      exercises: [
        block.copyWith(
          sets: [
            block.sets.single.copyWith(
              weightKg: () => 80,
              repetitions: () => 5,
            ),
          ],
        ),
      ],
    );
    await repository.saveWorkout(secondEdit);

    final pending = (await store.readOutbox())
        .where((row) => row.status == LocalMutationStatus.pending)
        .toList();
    expect(pending.single.operation, LocalMutationOperation.update);
    expect(pending.single.aggregateId, workout.workoutId);
    expect(
      Workout.fromJson(pending.single.body! as Map<String, Object?>)
          .exercises
          .single
          .sets
          .single
          .repetitions,
      5,
    );
  });

  test('finishing without previous values keeps empty fields empty', () async {
    final earlier = await finishedWorkout(
      title: 'Früher',
      weightKg: 60,
      repetitions: 8,
    );
    final current = await repository.startRepeat(
      earlier.workoutId,
      previousValueSource: PreviousValueSource.workout,
    );
    expect(current.exercises.single.sets.single.weightKg, isNull);

    advance(const Duration(minutes: 20));
    final finished = await repository.finishWorkout(current.workoutId);

    expect(finished.endedAtUtc, now);
    expect(finished.exercises.single.sets.single.weightKg, isNull);
  });

  test('finishing with previous values fills only empty weight and repetition fields', () async {
    final earlier = await finishedWorkout(
      title: 'Früher',
      weightKg: 60,
      repetitions: 8,
    );
    final current = await repository.startRepeat(
      earlier.workoutId,
      previousValueSource: PreviousValueSource.workout,
    );

    advance(const Duration(minutes: 20));
    final finished = await repository.finishWorkout(
      current.workoutId,
      applyPreviousValues: true,
    );

    final set = finished.exercises.single.sets.single;
    expect(set.weightKg, 60);
    expect(set.repetitions, 8);
  });

  test('resume makes the workout active again', () async {
    final finished = await finishedWorkout(title: 'Erledigt');
    expect(finished.endedAtUtc, isNotNull);

    final resumed = await repository.resumeWorkout(finished.workoutId);

    expect(resumed.endedAtUtc, isNull);
    expect(
      (await repository.readActiveWorkout())?.workoutId,
      finished.workoutId,
    );
    await expectLater(
      repository.startEmpty(),
      throwsA(isA<ActiveWorkoutExistsException>()),
    );
  });

  test('resume is rejected while another workout is active', () async {
    final ended = await finishedWorkout(title: 'Früher');
    final other = await repository.startEmpty(title: 'Jetzt');

    await expectLater(
      repository.resumeWorkout(ended.workoutId),
      throwsA(
        isA<ActiveWorkoutExistsException>().having(
          (error) => error.workoutId,
          'workoutId',
          other.workoutId,
        ),
      ),
    );
    expect(
      (await repository.readWorkout(ended.workoutId))?.endedAtUtc,
      isNotNull,
    );
  });

  test('deleting an synced workout offline removes it from the diary with one mutation', () async {
    final workout = Workout(
      workoutId: nextId(),
      title: 'Synchron',
      startedAtUtc: DateTime.utc(2026, 10, 16, 9),
      endedAtUtc: DateTime.utc(2026, 10, 16, 10),
      previousValueSource: PreviousValueSource.exercise,
    );
    await seedServer('workout', workout.workoutId, workout.toJson());
    expect((await repository.readDiary()).single.workoutId, workout.workoutId);

    await repository.deleteWorkout(workout.workoutId);

    expect(await repository.readDiary(), isEmpty);
    final outbox = await store.readOutbox();
    expect(outbox, hasLength(1));
    expect(outbox.single.operation, LocalMutationOperation.delete);
    expect(outbox.single.baseVersion, 1);
  });

  test('saving a workout as a plan creates a new plan or overwrites the same-named one', () async {
    final workout = await finishedWorkout(title: 'Push');
    expect(
      (await repository.previewPlanFromWorkout(workout.workoutId)).existingPlan,
      isNull,
    );

    final created = await repository.saveWorkoutAsPlan(workout.workoutId);
    expect(created.name, 'Push');
    expect(created.entries.single.exerciseId, _squat);
    expect(await repository.readPlans(), hasLength(1));

    final preview = await repository.previewPlanFromWorkout(workout.workoutId);
    expect(preview.existingPlan?.planId, created.planId);

    final overwritten = await repository.saveWorkoutAsPlan(
      workout.workoutId,
      overwriteExisting: true,
    );
    expect(overwritten.planId, created.planId);
    expect(await repository.readPlans(), hasLength(1));

    await repository.saveWorkoutAsPlan(workout.workoutId);
    expect(await repository.readPlans(), hasLength(2));
  });

  test('merging a custom exercise rewrites local references and archives the source', () async {
    final custom = CatalogExercise(
      id: nextId(),
      name: 'Kurzhantelrudern',
      exerciseType: ExerciseKind.strength,
      isBase: false,
    );
    await seedServer('custom-exercise', custom.id, {
      ...custom.toJson(),
      'isArchived': false,
    });
    final workout = await finishedWorkout(
      title: 'Zug',
      exerciseId: custom.id,
      weightKg: 20,
      repetitions: 10,
    );
    final plan = await repository.createPlan(
      TrainingPlanModel(
        planId: nextId(),
        name: 'Zug-Plan',
        previousValueSource: PreviousValueSource.exercise,
        entries: [PlanEntry(entryId: nextId(), exerciseId: custom.id)],
      ),
    );

    await repository.mergeExercises(
      sourceExerciseId: custom.id,
      targetExerciseId: _row,
    );

    expect(
      (await repository.readExercises()).any((item) => item.id == custom.id),
      isFalse,
    );
    final rewritten = await repository.readWorkout(workout.workoutId);
    expect(rewritten?.exercises.single.sourceExerciseId, _row);
    expect(rewritten?.exercises.single.exerciseNameSnapshot, 'Kniebeuge');
    expect(
      (await repository.readPlan(plan.planId))?.entries.single.exerciseId,
      _row,
    );
    expect(
      (await store.readOutbox()).any(
        (row) => row.operation == LocalMutationOperation.merge,
      ),
      isTrue,
    );
  });

  test(
    'a custom exercise with an invalid name is refused before writing',
    () async {
      final before = (await store.readOutbox()).length;

      await expectLater(
        repository.createCustomExercise(
          CatalogExercise(
            id: nextId(),
            name: '  ',
            exerciseType: ExerciseKind.strength,
            isBase: false,
          ),
        ),
        throwsA(isA<WorkoutValidationException>()),
      );

      expect((await store.readOutbox()).length, before);
    },
  );

  test('accounts do not see each other data and a database stays bound to one account', () async {
    await repository.createPlan(
      TrainingPlanModel(
        planId: nextId(),
        name: 'Nur A',
        previousValueSource: PreviousValueSource.exercise,
      ),
    );
    final otherDatabase = LocalDatabase(NativeDatabase.memory());
    final otherStore = LocalSyncStore(
      database: otherDatabase,
      accountId: _accountB,
    );
    final otherRepository = TrainingLogRepository(
      store: otherStore,
      catalog: _FixtureCatalog(),
      ids: nextId,
      clock: () => now,
    );
    addTearDown(otherDatabase.close);

    expect(await otherRepository.readPlans(), isEmpty);
    expect(await otherRepository.readDiary(), isEmpty);
    expect(await repository.readPlans(), hasLength(1));

    await expectLater(
      LocalSyncStore(
        database: database,
        accountId: _accountB,
      ).ensureAccountBound(),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'a refused local write returns an error and leaves no workout behind',
    () async {
      await store.freezeWritesIfOutboxEmpty();

      await expectLater(repository.startEmpty(), throwsStateError);

      expect(await repository.readDiary(), isEmpty);
      expect(await store.readOutbox(), isEmpty);
    },
  );
}
