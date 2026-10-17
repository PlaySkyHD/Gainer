import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

/// Zählt deterministisch hoch, damit Tests IDs exakt vorhersagen können.
IdFactory sequentialIds([String prefix = 'id']) {
  var next = 0;
  return () => '$prefix-${++next}';
}

final DateTime fixtureNow = DateTime.utc(2026, 10, 17, 18, 30, 45, 789);

const CatalogExercise benchPress = CatalogExercise(
  id: 'base-bench',
  name: 'Bankdrücken',
  exerciseType: ExerciseKind.strength,
  isBase: true,
  categoryIds: ['chest'],
);

const CatalogExercise pullUp = CatalogExercise(
  id: 'base-pullup',
  name: 'Klimmzug',
  exerciseType: ExerciseKind.bodyweightLoaded,
  isBase: true,
  categoryIds: ['back'],
);

const CatalogExercise pushUp = CatalogExercise(
  id: 'base-pushup',
  name: 'Liegestütz',
  exerciseType: ExerciseKind.bodyweightOnly,
  bodyweightFactor: 0.64,
  isBase: true,
);

const CatalogExercise assistedPullUp = CatalogExercise(
  id: 'base-assisted-pullup',
  name: 'Assistierter Klimmzug',
  exerciseType: ExerciseKind.assisted,
  isBase: true,
);

const CatalogExercise squat = CatalogExercise(
  id: 'base-squat',
  name: 'Kniebeuge',
  exerciseType: ExerciseKind.strength,
  isBase: true,
);

const CatalogExercise lateralRaise = CatalogExercise(
  id: 'base-lateral',
  name: 'Seitheben',
  exerciseType: ExerciseKind.strength,
  isBase: true,
);

const CatalogExercise archivedCurl = CatalogExercise(
  id: 'custom-curl',
  name: 'Alter Curl',
  exerciseType: ExerciseKind.strength,
  isBase: false,
  isArchived: true,
);

LoggedSet loggedSet(
  String id, {
  SetType type = SetType.normal,
  double? kg,
  int? reps,
  int? rir,
  String? notes,
}) => LoggedSet(
  setId: id,
  setType: type,
  weightKg: kg,
  repetitions: reps,
  rir: rir,
  notes: notes,
);

WorkoutBlock block(
  String id,
  CatalogExercise exercise,
  List<LoggedSet> sets, {
  String? supersetId,
  String? notes,
}) => WorkoutBlock(
  workoutExerciseId: id,
  sourceExerciseId: exercise.id,
  exerciseNameSnapshot: exercise.name,
  exerciseTypeSnapshot: exercise.exerciseType,
  supersetId: supersetId,
  notes: notes,
  sets: sets,
);

Workout workout({
  required String id,
  required DateTime startedAt,
  DateTime? endedAt,
  String title = 'Training',
  PreviousValueSource source = PreviousValueSource.exercise,
  String? sourcePlanId,
  String? sourceWorkoutId,
  DateTime? deletedAt,
  List<WorkoutBlock> exercises = const [],
}) => Workout(
  workoutId: id,
  title: title,
  startedAtUtc: startedAt,
  endedAtUtc: endedAt,
  previousValueSource: source,
  sourcePlanId: sourcePlanId,
  sourceWorkoutId: sourceWorkoutId,
  deletedAtUtc: deletedAt,
  exercises: exercises,
);
