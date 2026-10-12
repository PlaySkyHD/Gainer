import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/training_repository.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/training.dart';
import 'package:gainer_mobile/ui/features/training/training_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000002';

String testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

class FixtureCatalog implements ExerciseCatalogProvider {
  @override
  Future<List<ExerciseCatalogEntry>> loadExercises() async => const [
    ExerciseCatalogEntry(
      id: 'catalog-press',
      name: 'Bankdrücken',
      catalogVersion: 1,
    ),
  ];
}

class RecordingTimerPort implements RestTimerNotificationPort {
  final scheduled = <DateTime>[];
  int canceled = 0;

  @override
  Future<void> cancel({required String workoutId}) async => canceled++;

  @override
  Future<void> schedule({
    required String workoutId,
    required DateTime targetUtc,
  }) async {
    scheduled.add(targetUtc);
  }
}

class ThrowingTimerPort implements RestTimerNotificationPort {
  @override
  Future<void> cancel({required String workoutId}) async {
    throw StateError('notification unavailable');
  }

  @override
  Future<void> schedule({
    required String workoutId,
    required DateTime targetUtc,
  }) async {
    throw StateError('notification unavailable');
  }
}

void main() {
  late LocalDatabase database;
  late TrainingRepository repository;
  var databaseIsClosed = false;
  var id = 100;
  var now = DateTime.utc(2026, 10, 12, 9);
  final timerPort = RecordingTimerPort();

  setUp(() {
    id = 100;
    now = DateTime.utc(2026, 10, 12, 9);
    database = LocalDatabase(NativeDatabase.memory());
    databaseIsClosed = false;
    repository = TrainingRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
      catalog: FixtureCatalog(),
      notifications: timerPort,
      ids: () => testId(id++),
      clock: () => now,
    );
  });

  tearDown(() async {
    if (!databaseIsClosed) await database.close();
  });

  test(
    'custom exercises, templates and rotation persist in the account store',
    () async {
      final customId = await repository.createCustomExercise(
        const ExerciseValues(name: 'Kurzhantelrudern', muscleGroup: 'Rücken'),
      );
      final templateId = await repository.saveTemplate(
        name: 'Zug A',
        items: [
          TrainingTemplateItem(
            id: testId(900),
            exerciseId: customId,
            plannedSets: 4,
            minimumRepetitions: 8,
            maximumRepetitions: 12,
            targetRir: 2,
            restSeconds: 120,
            notes: null,
          ),
        ],
      );
      await repository.saveRotation([templateId]);
      final planning = await repository.readPlanning();
      expect(planning.customExercises.single.id, customId);
      expect(planning.nextTemplateId, templateId);
      expect(planning.templates.single.value.items.single.plannedSets, 4);
    },
  );

  test('OS timer failures do not undo or mask a completed set write', () async {
    var notificationFailures = 0;
    late final TrainingViewModel viewModel;
    final timerRepository = TrainingRepository(
      store: repository.store,
      catalog: FixtureCatalog(),
      notifications: ThrowingTimerPort(),
      ids: () => testId(id++),
      clock: () => now,
      onNotificationUnavailable: () {
        notificationFailures++;
        viewModel.reportNotificationUnavailable();
      },
    );
    viewModel = TrainingViewModel(timerRepository);
    addTearDown(viewModel.dispose);
    await viewModel.load();

    final exerciseId = await timerRepository.createCustomExercise(
      const ExerciseValues(name: 'Bankdrücken'),
    );
    final templateId = await timerRepository.saveTemplate(
      name: 'Drücken',
      items: [
        TrainingTemplateItem(
          id: testId(950),
          exerciseId: exerciseId,
          plannedSets: 1,
          minimumRepetitions: 5,
          maximumRepetitions: 8,
          targetRir: 2,
          restSeconds: 90,
          notes: null,
        ),
      ],
    );
    await viewModel.start(templateId);
    final workoutId = viewModel.runningWorkoutId!;
    final exercise = viewModel.runningWorkout!.exercises.single;
    final set = exercise.sets.single;

    await viewModel.logSet(
      exerciseId: exercise.id,
      setId: set.id,
      weightKg: 60,
      repetitions: 6,
      rir: 2,
      notes: null,
      complete: true,
    );

    expect(viewModel.errorMessage, isNull);
    expect(viewModel.notificationNotice, contains('Benachrichtigung'));
    expect(notificationFailures, 1);
    final persisted = (await timerRepository.readRunningWorkout())!;
    expect(persisted.isRunning, isTrue);
    expect(persisted.exercises.single.sets.single.isCompleted, isTrue);
    expect(
      await repository.store.readOutbox(aggregateType: 'workout'),
      isNotEmpty,
    );

    await viewModel.finish();
    expect(viewModel.errorMessage, isNull);
    expect(notificationFailures, 2);
    expect((await timerRepository.readHistory()).single.id, workoutId);
  });

  test('completed workout atomically updates rotation and remains immutable history', () async {
    final exerciseId = await repository.createCustomExercise(
      const ExerciseValues(name: 'Beinpresse'),
    );
    final templateId = await repository.saveTemplate(
      name: 'Beine',
      items: [
        TrainingTemplateItem(
          id: testId(901),
          exerciseId: exerciseId,
          plannedSets: 1,
          minimumRepetitions: 8,
          maximumRepetitions: 10,
          targetRir: 2,
          restSeconds: 90,
          notes: null,
        ),
      ],
    );
    final rotationId = await repository.saveRotation([templateId]);
    final workoutId = await repository.startWorkout(templateId);
    final workout = (await repository.readRunningWorkout())!;
    final exercise = workout.exercises.single;
    final set = exercise.sets.single;

    await repository.logSet(
      workoutId: workoutId,
      exerciseId: exercise.id,
      setId: set.id,
      weightKg: 100,
      repetitions: 9,
      rir: 2,
      notes: 'sauber',
      complete: true,
    );
    expect(timerPort.scheduled, hasLength(1));
    final failing = TrainingRepository(
      store: repository.store,
      catalog: FixtureCatalog(),
      ids: () => testId(id++),
      clock: () => now,
      transactionFaultForTesting: () => throw StateError('injected rollback'),
    );
    await expectLater(failing.completeWorkout(workoutId), throwsStateError);
    expect((await repository.readRunningWorkout())?.isRunning, isTrue);
    final unchangedRotation = await repository.store.readAggregate(
      'workout-rotation',
      rotationId,
    );
    expect(
      unchangedRotation!.workingCopy,
      containsPair('lastCompletedTemplateId', null),
    );
    await repository.completeWorkout(workoutId);

    final history = await repository.readHistory();
    expect(history, hasLength(1));
    expect(history.single.value.exercises.single.sets.single.weightKg, 100);
    expect(history.single.value.status, 'completed');
    final rotation = await repository.store.readAggregate(
      'workout-rotation',
      rotationId,
    );
    expect(
      rotation!.workingCopy,
      containsPair('lastCompletedTemplateId', templateId),
    );
    final outbox = await repository.store.readOutbox(aggregateType: 'workout');
    expect(outbox.last.operation, LocalMutationOperation.complete);
    expect(
      outbox.last.body,
      containsPair('rotation', containsPair('id', rotationId)),
    );
    await expectLater(
      repository.logSet(
        workoutId: workoutId,
        exerciseId: exercise.id,
        setId: set.id,
        weightKg: 101,
        repetitions: 9,
        rir: null,
        notes: null,
        complete: true,
      ),
      throwsStateError,
    );
  });

  test(
    'running workout supports exercise and set insert, remove, and reorder',
    () async {
      final templateId = await repository.saveTemplate(
        name: 'Kraft A',
        items: [
          TrainingTemplateItem(
            id: testId(903),
            exerciseId: 'catalog-press',
            plannedSets: 2,
            minimumRepetitions: 5,
            maximumRepetitions: 8,
            targetRir: null,
            restSeconds: null,
            notes: null,
          ),
        ],
      );
      final workoutId = await repository.startWorkout(templateId);
      final started = (await repository.readRunningWorkout())!;
      final originalExercise = started.exercises.single;
      var workout = await repository.addExerciseToWorkout(
        workoutId: workoutId,
        exerciseId: 'catalog-press',
      );
      expect(workout.exercises, hasLength(2));
      workout = await repository.moveExercise(
        workoutId: workoutId,
        workoutExerciseId: originalExercise.id,
        targetPosition: 1,
      );
      expect(workout.exercises.last.id, originalExercise.id);
      final addedExercise = workout.exercises.first;
      workout = await repository.addSet(
        workoutId: workoutId,
        workoutExerciseId: addedExercise.id,
      );
      expect(workout.exercises.first.sets, hasLength(2));
      final firstSet = workout.exercises.first.sets.first;
      workout = await repository.moveSet(
        workoutId: workoutId,
        workoutExerciseId: addedExercise.id,
        setId: firstSet.id,
        targetPosition: 1,
      );
      expect(workout.exercises.first.sets.last.id, firstSet.id);
      workout = await repository.removeSet(
        workoutId: workoutId,
        workoutExerciseId: addedExercise.id,
        setId: firstSet.id,
      );
      expect(workout.exercises.first.sets, hasLength(1));
      workout = await repository.removeExerciseFromWorkout(
        workoutId: workoutId,
        workoutExerciseId: addedExercise.id,
      );
      expect(workout.exercises, hasLength(1));
      expect(workout.exercises.single.id, originalExercise.id);
    },
  );

  test('rest timer deadline resumes after file reopen and recomputes remaining time', () async {
    final directory = await Directory.systemTemp.createTemp('gainer-training-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}training.sqlite',
    );
    LocalDatabase? fileDb;
    LocalDatabase? reopenedDb;
    try {
      await database.close();
      databaseIsClosed = true;
      fileDb = LocalDatabase(NativeDatabase.createInBackground(file));
      final first = TrainingRepository(
        store: LocalSyncStore(database: fileDb, accountId: accountId),
        catalog: FixtureCatalog(),
        notifications: timerPort,
        ids: () => testId(id++),
        clock: () => now,
      );
      final exerciseId = await first.createCustomExercise(
        const ExerciseValues(name: 'Rudern'),
      );
      final templateId = await first.saveTemplate(
        name: 'Rücken',
        items: [
          TrainingTemplateItem(
            id: testId(902),
            exerciseId: exerciseId,
            plannedSets: 1,
            minimumRepetitions: 10,
            maximumRepetitions: 10,
            targetRir: null,
            restSeconds: 90,
            notes: null,
          ),
        ],
      );
      final workoutId = await first.startWorkout(templateId);
      final workout = (await first.readRunningWorkout())!;
      await first.logSet(
        workoutId: workoutId,
        exerciseId: workout.exercises.single.id,
        setId: workout.exercises.single.sets.single.id,
        weightKg: 50,
        repetitions: 10,
        rir: null,
        notes: null,
        complete: true,
      );
      await fileDb.close();
      fileDb = null;

      now = now.add(const Duration(seconds: 25));
      reopenedDb = LocalDatabase(NativeDatabase.createInBackground(file));
      final reopened = TrainingRepository(
        store: LocalSyncStore(database: reopenedDb, accountId: accountId),
        catalog: FixtureCatalog(),
        notifications: timerPort,
        clock: () => now,
      );
      final resumedWorkout = await reopened.readRunningWorkout();
      expect(resumedWorkout?.restTimer?.targetAtUtc, isNotNull);
      expect(reopened.remainingRestSeconds(resumedWorkout?.restTimer), 65);
      final scheduledCount = timerPort.scheduled.length;
      await reopened.resumeRestTimerNotification();
      expect(timerPort.scheduled, hasLength(scheduledCount + 1));
      expect(
        timerPort.scheduled.last,
        DateTime.parse(resumedWorkout!.restTimer!.targetAtUtc),
      );
    } finally {
      await fileDb?.close();
      await reopenedDb?.close();
      await directory.delete(recursive: true);
    }
  });
}
