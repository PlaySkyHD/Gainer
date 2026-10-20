import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/muscle_volume.dart';
import 'package:gainer_mobile/domain/models/training/muscles.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

CatalogExercise _exercise(
  String id,
  String name, {
  List<Muscle> primary = const [],
  List<Muscle> secondary = const [],
  ExerciseKind kind = ExerciseKind.strength,
}) => CatalogExercise(
  id: id,
  name: name,
  exerciseType: kind,
  primaryMuscles: primary,
  secondaryMuscles: secondary,
  isBase: false,
);

final _bench = _exercise(
  'bench',
  'Bankdrücken',
  primary: [Muscle.chest],
  secondary: [Muscle.triceps],
);
final _pushdown = _exercise(
  'pushdown',
  'Trizepsdrücken',
  primary: [Muscle.triceps],
);
final _squat = _exercise('squat', 'Kniebeuge', primary: [Muscle.quads]);
final _curl = _exercise('curl', 'Curls');

final _byId = {
  for (final exercise in [_bench, _pushdown, _squat, _curl])
    exercise.id: exercise,
};

TrainingPlanModel _plan(
  String id,
  List<(String, int)> entries, {
  bool archived = false,
}) => TrainingPlanModel(
  planId: id,
  name: id,
  previousValueSource: PreviousValueSource.exercise,
  isArchived: archived,
  entries: [
    for (final (exerciseId, sets) in entries)
      PlanEntry(
        entryId: '$id-$exerciseId',
        exerciseId: exerciseId,
        warmupSets: 2,
        workingSets: sets,
      ),
  ],
);

Workout _workout(
  String id,
  DateTime startedAtUtc,
  List<WorkoutBlock> blocks, {
  bool ended = true,
  bool deleted = false,
}) => Workout(
  workoutId: id,
  title: id,
  startedAtUtc: startedAtUtc,
  endedAtUtc: ended ? startedAtUtc.add(const Duration(hours: 1)) : null,
  deletedAtUtc: deleted ? startedAtUtc : null,
  previousValueSource: PreviousValueSource.exercise,
  exercises: blocks,
);

WorkoutBlock _squatBlock(String id) => WorkoutBlock(
  workoutExerciseId: id,
  sourceExerciseId: 'squat',
  exerciseNameSnapshot: 'Kniebeuge',
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: [
    for (var i = 0; i < 2; i++)
      LoggedSet(
        setId: '$id-w$i',
        setType: SetType.warmup,
        weightKg: 40,
        repetitions: 8,
      ),
    for (var i = 0; i < 3; i++)
      LoggedSet(setId: '$id-s$i', weightKg: 100, repetitions: 5),
    // Ohne Gewicht bei Kraftübungen nicht erfasst.
    LoggedSet(setId: '$id-empty', repetitions: 5),
  ],
);

void main() {
  test('plan counts working sets, secondary muscles half', () {
    final volume = MuscleVolume.fromPlans([
      _plan('push', [('bench', 4), ('pushdown', 3)]),
    ], _byId);

    expect(volume.setsFor(Muscle.chest), 4);
    expect(volume.setsFor(Muscle.triceps), 5);
    expect(volume.setsFor(Muscle.quads), 0);
    expect(volume.contributionsFor(Muscle.triceps).map((c) => c.sets), [3, 2]);
    expect(
      volume.contributionsFor(Muscle.triceps).last.role,
      MuscleRole.secondary,
    );
  });

  test('all plans sum active plans and skip archived ones', () {
    final volume = MuscleVolume.fromPlans([
      _plan('push', [('bench', 4)]),
      _plan('push2', [('bench', 3)]),
      _plan('old', [('squat', 5)], archived: true),
    ], _byId);

    expect(volume.setsFor(Muscle.chest), 7);
    expect(volume.setsFor(Muscle.quads), 0);
  });

  test('exercises without muscles are listed once', () {
    final volume = MuscleVolume.fromPlans([
      _plan('a', [('curl', 3)]),
      _plan('b', [('curl', 2), ('unknown', 1)]),
    ], _byId);

    expect(volume.exercisesWithoutMuscles, ['Curls', 'Übung']);
    expect(volume.isEmpty, isTrue);
  });

  test('workouts count recorded working sets within the period', () {
    final now = DateTime.utc(2026, 10, 20, 12);
    final volume = MuscleVolume.fromWorkouts(
      [
        _workout('a', now.subtract(const Duration(days: 1)), [
          _squatBlock('a1'),
        ]),
        _workout('b', now.subtract(const Duration(days: 6)), [
          _squatBlock('b1'),
        ]),
        _workout('old', now.subtract(const Duration(days: 8)), [
          _squatBlock('o1'),
        ]),
        _workout('active', now, [_squatBlock('x1')], ended: false),
        _workout('deleted', now.subtract(const Duration(days: 2)), [
          _squatBlock('d1'),
        ], deleted: true),
      ],
      _byId,
      fromUtc: now.subtract(const Duration(days: 7)),
      toUtc: now.add(const Duration(minutes: 1)),
    );

    expect(volume.setsFor(Muscle.quads), 6);
  });

  test('average per week divides by the number of weeks', () {
    final now = DateTime.utc(2026, 10, 20, 12);
    final volume = MuscleVolume.fromWorkouts(
      [
        _workout('a', now.subtract(const Duration(days: 1)), [
          _squatBlock('a1'),
        ]),
        _workout('b', now.subtract(const Duration(days: 20)), [
          _squatBlock('b1'),
        ]),
      ],
      _byId,
      fromUtc: now.subtract(const Duration(days: 28)),
      toUtc: now,
      weeks: 4,
    );

    expect(volume.setsFor(Muscle.quads), 1.5);
  });

  test('levels follow the documented thresholds', () {
    expect(MuscleLevel.of(0), MuscleLevel.none);
    expect(MuscleLevel.of(0.5), MuscleLevel.low);
    expect(MuscleLevel.of(4), MuscleLevel.medium);
    expect(MuscleLevel.of(10), MuscleLevel.high);
    expect(MuscleLevel.of(20), MuscleLevel.high);
    expect(MuscleLevel.of(20.5), MuscleLevel.veryHigh);
  });

  test('ranked lists all muscles by sets', () {
    final volume = MuscleVolume.fromPlans([
      _plan('push', [('bench', 4), ('pushdown', 3)]),
    ], _byId);

    expect(volume.ranked.take(2), [Muscle.triceps, Muscle.chest]);
    expect(volume.ranked, hasLength(Muscle.values.length));
  });

  test('muscle lists ignore unknown and repeated keys', () {
    expect(Muscle.listFromJson(['chest', 'pecs', 'chest', 'lats']), [
      Muscle.chest,
      Muscle.lats,
    ]);
    expect(Muscle.listFromJson(null), isEmpty);
  });

  test('catalog exercise round-trips muscles', () {
    final json = _bench.toJson();
    expect(json['primaryMuscles'], ['chest']);
    expect(CatalogExercise.fromJson(json), _bench);
  });
}
