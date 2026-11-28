import 'package:gainer_mobile/domain/models/training/workout_model.dart';

import 'training_test_support.dart';

const analysisBenchId = 'analysis-bench';
const analysisDeadliftId = 'analysis-deadlift';

/// Heute in den Tests der Trainingsanalyse (Mittwoch).
final analysisNow = DateTime.utc(2026, 11, 25, 9);

WorkoutBlock _block(
  String id,
  String exerciseId,
  String name,
  double kg,
  List<int> reps, {
  int? rir,
  bool warmup = false,
}) => WorkoutBlock(
  workoutExerciseId: id,
  sourceExerciseId: exerciseId,
  exerciseNameSnapshot: name,
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: [
    if (warmup)
      LoggedSet(
        setId: '$id-w',
        setType: SetType.warmup,
        weightKg: kg * 2,
        repetitions: 10,
      ),
    for (final (index, count) in reps.indexed)
      LoggedSet(
        setId: '$id-$index',
        weightKg: kg,
        repetitions: count,
        rir: rir,
      ),
  ],
);

/// Bankdrücken steigt über vier Trainings bis an das obere Ende (Gewicht
/// erhöhen), Kreuzheben verliert Wiederholungen bei RIR 0 (Deload).
Future<void> seedAnalysisScenario(TrainingHarness harness) async {
  const bench = [
    (35, 80.0, [8, 8, 8]),
    (28, 82.5, [10, 9, 9]),
    (14, 85.0, [10, 10, 10]),
    (7, 87.5, [12, 12, 12]),
  ];
  for (final (index, (days, kg, reps)) in bench.indexed) {
    final start = analysisNow
        .subtract(Duration(days: days))
        .add(const Duration(hours: 8));
    await harness.seedWorkout(
      title: 'Brust',
      start: start,
      end: start.add(const Duration(hours: 1)),
      blocks: [
        _block(
          'b$index',
          analysisBenchId,
          'Bankdrücken',
          kg,
          reps,
          warmup: true,
        ),
      ],
    );
  }
  const deadlift = [
    (22, 140.0, [6, 6, 6], null),
    (15, 140.0, [5, 5, 5], 1),
    (8, 140.0, [4, 4, 4], 0),
    (1, 135.0, [3, 3, 3], 0),
  ];
  for (final (index, (days, kg, reps, rir)) in deadlift.indexed) {
    final start = analysisNow
        .subtract(Duration(days: days))
        .add(const Duration(hours: 8));
    await harness.seedWorkout(
      title: 'Rücken',
      start: start,
      end: start.add(const Duration(hours: 1)),
      blocks: [
        _block('d$index', analysisDeadliftId, 'Kreuzheben', kg, reps, rir: rir),
      ],
    );
  }
  harness.now = analysisNow;
}
