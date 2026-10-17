import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_rules.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/workout_view_model.dart';

import 'training_test_support.dart';

CatalogExercise _exercise(
  String id,
  String name, {
  ExerciseKind kind = ExerciseKind.strength,
}) => CatalogExercise(id: id, name: name, exerciseType: kind, isBase: false);

WorkoutBlock _block(
  String id,
  String source,
  String name, {
  String? supersetId,
  List<LoggedSet> sets = const [LoggedSet(setId: 'set')],
}) => WorkoutBlock(
  workoutExerciseId: id,
  sourceExerciseId: source,
  exerciseNameSnapshot: name,
  exerciseTypeSnapshot: ExerciseKind.strength,
  supersetId: supersetId,
  sets: sets,
);

void main() {
  late TrainingHarness harness;
  late ActiveWorkoutController activeWorkout;

  setUp(() async {
    harness = await TrainingHarness.create();
    activeWorkout = ActiveWorkoutController(harness.repository);
  });

  tearDown(() async {
    activeWorkout.dispose();
    await harness.dispose();
  });

  Future<WorkoutViewModel> open(
    List<WorkoutBlock> blocks, {
    List<Workout> history = const [],
  }) async {
    for (final past in history) {
      await harness.seedWorkout(
        title: past.title,
        start: past.startedAtUtc,
        end: past.endedAtUtc,
        blocks: past.exercises,
      );
    }
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: blocks,
    );
    await activeWorkout.load();
    harness.now = DateTime.utc(2026, 10, 17, 9);
    final model = WorkoutViewModel(
      repository: harness.repository,
      activeWorkout: activeWorkout,
      workoutId: workout.workoutId,
    );
    addTearDown(model.dispose);
    await model.load();
    return model;
  }

  test(
    'Einzelübung wird als Block mit leerem normalen Satz angehängt',
    () async {
      final model = await open([_block('a', 'sa', 'Bankdrücken')]);

      await model.addExercises([_exercise('kniebeuge', 'Kniebeuge')]);

      final added = model.workout!.exercises.last;
      expect(model.workout!.exercises, hasLength(2));
      expect(added.exerciseNameSnapshot, 'Kniebeuge');
      expect(added.sourceExerciseId, 'kniebeuge');
      expect(added.exerciseTypeSnapshot, ExerciseKind.strength);
      expect(added.supersetId, isNull);
      expect(added.sets, hasLength(1));
      expect(added.sets.single.setType, SetType.normal);
      expect(added.sets.single.weightKg, isNull);
      expect(added.sets.single.repetitions, isNull);
    },
  );

  test(
    'Superset legt benachbarte Blöcke mit gemeinsamer neuer ID an',
    () async {
      final model = await open([_block('a', 'sa', 'Bankdrücken')]);

      await model.addExercises([
        _exercise('curl', 'Bizepscurl'),
        _exercise('triceps', 'Trizepsdrücken'),
      ], asSuperset: true);

      final blocks = model.workout!.exercises;
      expect(blocks, hasLength(3));
      final first = blocks[1];
      final second = blocks[2];
      expect(first.supersetId, isNotNull);
      expect(first.supersetId, isNot(blocks.first.supersetId));
      expect(second.supersetId, first.supersetId);
      final group = supersetGroups(blocks).last;
      expect(group.isSuperset, isTrue);
      expect(group.labelAt(0), 'A');
      expect(group.labelAt(1), 'B');
    },
  );

  test('Neuordnen behält nur die übergebene Reihenfolge', () async {
    final model = await open([
      _block('bench', 'sb', 'Bankdrücken'),
      _block('row', 'sr', 'Rudern'),
      _block('squat', 'sk', 'Kniebeuge'),
    ]);

    await model.arrangeBlocks(['squat', 'bench', 'row']);

    expect(
      [for (final block in model.workout!.exercises) block.workoutExerciseId],
      ['squat', 'bench', 'row'],
    );
    expect(
      (await harness.repository.readWorkout(model.workoutId))!.exercises
          .map((block) => block.workoutExerciseId),
      ['squat', 'bench', 'row'],
    );
  });

  test('Ersetzen behält Satzwerte und Blocknotiz', () async {
    final model = await open([
      _block(
        'bench',
        'barbell',
        'Langhantel-Bankdrücken',
        sets: const [
          LoggedSet(setId: 's1', weightKg: 80, repetitions: 8),
          LoggedSet(setId: 's2', weightKg: 80, repetitions: 7),
        ],
      ),
    ]);
    await model.setBlockNotes('bench', 'Schulter zwickt');

    await model.replaceExercise(
      'bench',
      _exercise('dumbbell', 'Kurzhantel-Bankdrücken'),
    );

    final block = model.workout!.exercises.single;
    expect(block.sourceExerciseId, 'dumbbell');
    expect(block.exerciseNameSnapshot, 'Kurzhantel-Bankdrücken');
    expect(block.notes, 'Schulter zwickt');
    expect([for (final set in block.sets) set.weightKg], [80, 80]);
    expect([for (final set in block.sets) set.repetitions], [8, 7]);
  });

  test('nach dem Ersetzen beziehen sich Vorwerte auf die neue Übung', () async {
    final history = Workout(
      workoutId: 'old',
      title: 'Alt',
      startedAtUtc: DateTime.utc(2026, 10, 10, 8),
      endedAtUtc: DateTime.utc(2026, 10, 10, 9),
      previousValueSource: PreviousValueSource.exercise,
      exercises: [
        _block(
          'old-db',
          'dumbbell',
          'Kurzhantel-Bankdrücken',
          sets: const [LoggedSet(setId: 'o1', weightKg: 30, repetitions: 10)],
        ),
      ],
    );
    final model = await open(
      [_block('bench', 'barbell', 'Langhantel-Bankdrücken')],
      history: [history],
    );
    expect(model.previousValues['bench'], [null]);

    await model.replaceExercise(
      'bench',
      _exercise('dumbbell', 'Kurzhantel-Bankdrücken'),
    );

    final previous = model.previousValues['bench']!.single!;
    expect(previous.weightKg, 30);
    expect(previous.repetitions, 10);
  });

  test('Entfernen löst ein Superset, das danach allein steht', () async {
    final model = await open([
      _block('a', 'sa', 'Bizepscurl', supersetId: 'ss'),
      _block('b', 'sb', 'Trizepsdrücken', supersetId: 'ss'),
    ]);

    await model.removeBlock('b');

    expect(model.workout!.exercises, hasLength(1));
    expect(model.workout!.exercises.single.supersetId, isNull);
  });

  test('Fehlende Werte zählen und Vorwerte füllen nur leere Felder', () async {
    final previous = Workout(
      workoutId: 'old',
      title: 'Alt',
      startedAtUtc: DateTime.utc(2026, 10, 10, 8),
      endedAtUtc: DateTime.utc(2026, 10, 10, 9),
      previousValueSource: PreviousValueSource.exercise,
      exercises: [
        _block(
          'old-bench',
          'bench',
          'Bankdrücken',
          sets: const [
            LoggedSet(setId: 'o1', weightKg: 100, repetitions: 8),
            LoggedSet(setId: 'o2', weightKg: 100, repetitions: 7),
          ],
        ),
      ],
    );
    final model = await open(
      [
        _block(
          'bench',
          'bench',
          'Bankdrücken',
          sets: const [
            LoggedSet(setId: 's1', weightKg: 90),
            LoggedSet(setId: 's2'),
          ],
        ),
        _block('row', 'row', 'Rudern', sets: const [LoggedSet(setId: 'r1')]),
      ],
      history: [previous],
    );
    expect(model.missingValueCount, 3);

    final outcome = await model.requestFinish(applyPreviousValues: true);

    expect(outcome, WorkoutFinishOutcome.finished);
    final stored = await harness.repository.readWorkout(model.workoutId);
    final bench = stored!.exercises.first;
    expect(bench.sets[0].weightKg, 90);
    expect(bench.sets[0].repetitions, 8);
    expect(bench.sets[1].weightKg, 100);
    expect(bench.sets[1].repetitions, 7);
    final row = stored.exercises.last;
    expect(row.sets.single.weightKg, isNull);
    expect(row.sets.single.repetitions, isNull);
    expect(stored.endedAtUtc, isNotNull);
  });

  test('Trotzdem beenden lässt fehlende Werte leer', () async {
    final model = await open([
      _block('a', 'sa', 'Bankdrücken', sets: const [LoggedSet(setId: 's1')]),
    ]);

    final outcome = await model.requestFinish();

    expect(outcome, WorkoutFinishOutcome.finished);
    final stored = await harness.repository.readWorkout(model.workoutId);
    expect(stored!.exercises.single.sets.single.weightKg, isNull);
    expect(stored.exercises.single.sets.single.repetitions, isNull);
    expect(stored.endedAtUtc, isNotNull);
  });
}
