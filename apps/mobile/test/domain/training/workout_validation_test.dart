import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_validation.dart';

import 'training_fixtures.dart';

void main() {
  final start = DateTime.utc(2026, 10, 17, 18);

  test('a valid workout passes validation', () {
    final valid = workout(
      id: 'w',
      startedAt: start,
      endedAt: start.add(const Duration(hours: 1)),
      title: 'Push',
      exercises: [
        block('we', benchPress, [loggedSet('s', kg: 100, reps: 8, rir: 2)]),
      ],
    );

    expect(() => validateWorkout(valid), returnsNormally);
  });

  test('title must have 1 to 160 characters after trimming', () {
    expect(
      () => validateWorkout(workout(id: 'w', startedAt: start, title: '  ')),
      throwsA(isA<WorkoutValidationException>()),
    );
    expect(
      () =>
          validateWorkout(workout(id: 'w', startedAt: start, title: 'x' * 161)),
      throwsA(isA<WorkoutValidationException>()),
    );
  });

  test('notes are limited to 2000 characters', () {
    final tooLong = Workout(
      workoutId: 'w',
      title: 'T',
      notes: 'x' * 2001,
      startedAtUtc: start,
      previousValueSource: PreviousValueSource.exercise,
    );

    expect(
      () => validateWorkout(tooLong),
      throwsA(
        isA<WorkoutValidationException>().having(
          (e) => e.fields.keys,
          'fields',
          contains('notes'),
        ),
      ),
    );
  });

  test('end time must be after start time', () {
    final sameInstant = workout(id: 'w', startedAt: start, endedAt: start);

    expect(
      () => validateWorkout(sameInstant),
      throwsA(
        isA<WorkoutValidationException>().having(
          (e) => e.fields['endedAtUtc'],
          'endedAtUtc',
          isNotNull,
        ),
      ),
    );
  });

  test('RIR must be between 0 and 10 and reports the set path', () {
    final invalid = workout(
      id: 'w',
      startedAt: start,
      exercises: [
        block('we', benchPress, [loggedSet('s', kg: 100, reps: 8, rir: 11)]),
      ],
    );

    expect(
      () => validateWorkout(invalid),
      throwsA(
        isA<WorkoutValidationException>().having(
          (e) => e.fields.keys,
          'fields',
          ['exercises[0].sets[0].rir'],
        ),
      ),
    );
  });

  test('more than 50 blocks or sets per block is rejected', () {
    final tooManyBlocks = workout(
      id: 'w',
      startedAt: start,
      exercises: [
        for (var i = 0; i < 51; i++) block('we-$i', benchPress, const []),
      ],
    );
    final tooManySets = workout(
      id: 'w',
      startedAt: start,
      exercises: [
        block('we', benchPress, [
          for (var i = 0; i < 51; i++) loggedSet('s-$i'),
        ]),
      ],
    );

    expect(
      () => validateWorkout(tooManyBlocks),
      throwsA(isA<WorkoutValidationException>()),
    );
    expect(
      () => validateWorkout(tooManySets),
      throwsA(isA<WorkoutValidationException>()),
    );
  });

  test('all field errors are collected in one exception', () {
    final invalid = workout(
      id: 'w',
      startedAt: start,
      title: '',
      exercises: [
        block('we', benchPress, [loggedSet('s', kg: -1, reps: 8)]),
      ],
    );

    expect(
      () => validateWorkout(invalid),
      throwsA(
        isA<WorkoutValidationException>().having(
          (e) => e.fields.keys,
          'fields',
          containsAll(['title', 'exercises[0].sets[0].weightKg']),
        ),
      ),
    );
  });

  test('plan entries need 0 to 20 warmup, 0 to 50 working and 1 to 50 sets in total', () {
    TrainingPlanModel plan(PlanEntry entry) => TrainingPlanModel(
      planId: 'p',
      name: 'Push',
      previousValueSource: PreviousValueSource.exercise,
      entries: [entry],
    );

    expect(
      () => validateTrainingPlan(
        plan(const PlanEntry(entryId: 'e', exerciseId: 'x', workingSets: 0)),
      ),
      throwsA(isA<WorkoutValidationException>()),
    );
    expect(
      () => validateTrainingPlan(
        plan(const PlanEntry(entryId: 'e', exerciseId: 'x', warmupSets: 21)),
      ),
      throwsA(isA<WorkoutValidationException>()),
    );
    expect(
      () => validateTrainingPlan(
        plan(const PlanEntry(entryId: 'e', exerciseId: 'x', workingSets: 51)),
      ),
      throwsA(isA<WorkoutValidationException>()),
    );
    expect(
      () => validateTrainingPlan(
        plan(
          const PlanEntry(
            entryId: 'e',
            exerciseId: 'x',
            warmupSets: 1,
            workingSets: 50,
          ),
        ),
      ),
      throwsA(isA<WorkoutValidationException>()),
    );
    expect(
      () => validateTrainingPlan(
        plan(const PlanEntry(entryId: 'e', exerciseId: 'x', warmupSets: 1)),
      ),
      returnsNormally,
    );
  });

  test(
    'catalog factors and category ids are checked against contract bounds',
    () {
      CatalogExercise exercise({
        double? bodyweight,
        double? weight,
        List<String> categories = const [],
      }) => CatalogExercise(
        id: 'custom',
        name: 'Landmine Press',
        exerciseType: ExerciseKind.strength,
        bodyweightFactor: bodyweight,
        weightFactor: weight,
        categoryIds: categories,
        isBase: false,
      );

      expect(
        () => validateCatalogExercise(exercise(bodyweight: 1.5)),
        throwsA(isA<WorkoutValidationException>()),
      );
      expect(
        () => validateCatalogExercise(exercise(weight: 0)),
        throwsA(isA<WorkoutValidationException>()),
      );
      expect(
        () => validateCatalogExercise(exercise(weight: 10.5)),
        throwsA(isA<WorkoutValidationException>()),
      );
      expect(
        () => validateCatalogExercise(exercise(categories: ['a', 'a'])),
        throwsA(isA<WorkoutValidationException>()),
      );
      expect(
        () => validateCatalogExercise(
          exercise(bodyweight: 0.64, weight: 2.5, categories: ['a', 'b']),
        ),
        returnsNormally,
      );
    },
  );
}
