import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

/// Vertragsbeispiel aus /tmp/gainer-contracts.md, ergänzt um die lokalen Felder
/// `deletedAtUtc`, `sortOrder` und `isArchived`, die `toJson` immer schreibt.
const Map<String, Object?> contractWorkoutJson = {
  'workoutId': 'w-1',
  'title': 'Push',
  'notes': 'Schulter zwickt',
  'startedAtUtc': '2026-10-17T18:00:00.000Z',
  'endedAtUtc': '2026-10-17T19:05:00.000Z',
  'previousValueSource': 'plan',
  'sourcePlanId': 'plan-1',
  'sourceWorkoutId': null,
  'exercises': [
    {
      'workoutExerciseId': 'we-1',
      'sourceExerciseId': 'base-bench',
      'exerciseNameSnapshot': 'Bankdrücken',
      'exerciseTypeSnapshot': 'strength',
      'notes': null,
      'supersetId': 'ss-1',
      'sets': [
        {
          'setId': 's-1',
          'setType': 'warmup',
          'weightKg': 60.0,
          'repetitions': 10,
          'rir': null,
          'notes': null,
        },
        {
          'setId': 's-2',
          'setType': 'normal',
          'weightKg': 100.0,
          'repetitions': 8,
          'rir': 2,
          'notes': 'sauber',
        },
        {
          'setId': 's-3',
          'setType': 'dropset',
          'weightKg': null,
          'repetitions': null,
          'rir': null,
          'notes': null,
        },
      ],
    },
  ],
  'deletedAtUtc': null,
};

void main() {
  group('Workout JSON', () {
    test('round-trips the contract example exactly', () {
      final workout = Workout.fromJson(contractWorkoutJson);

      expect(workout.toJson(), equals(contractWorkoutJson));
      expect(workout.exercises.single.sets.map((set) => set.setType), [
        SetType.warmup,
        SetType.normal,
        SetType.dropset,
      ]);
    });

    test('reads unknown set types as normal sets', () {
      final set = LoggedSet.fromJson({
        'setId': 's',
        'setType': 'superset-future-type',
      });

      expect(set.setType, SetType.normal);
    });

    test('rejects unknown exercise types instead of reinterpreting them', () {
      expect(
        () => WorkoutBlock.fromJson({
          'workoutExerciseId': 'we',
          'sourceExerciseId': 'x',
          'exerciseNameSnapshot': 'Cardio',
          'exerciseTypeSnapshot': 'duration',
          'sets': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('training plan round-trips with entries and rotation', () {
      final plan = TrainingPlanModel.fromJson({
        'planId': 'plan-1',
        'name': 'Push',
        'notes': null,
        'previousValueSource': 'exercise',
        'entries': [
          {
            'entryId': 'e-1',
            'exerciseId': 'base-bench',
            'warmupSets': 1,
            'workingSets': 3,
            'notes': null,
            'supersetId': null,
          },
        ],
        'sortOrder': 2,
        'isArchived': false,
      });

      expect(plan.toJson()['entries'], [
        {
          'entryId': 'e-1',
          'exerciseId': 'base-bench',
          'warmupSets': 1,
          'workingSets': 3,
          'notes': null,
          'supersetId': null,
        },
      ]);
      expect(plan.sortOrder, 2);
      expect(
        RotationModel.fromJson({
          'rotationId': 'rot-1',
          'planIds': ['plan-1', 'plan-2'],
        }).toJson(),
        {
          'rotationId': 'rot-1',
          'planIds': ['plan-1', 'plan-2'],
        },
      );
    });
  });

  group('Workout state and value semantics', () {
    final start = DateTime.utc(2026, 10, 17, 18);

    test('isActive is true only without end and without deletion', () {
      final active = Workout(
        workoutId: 'w',
        title: 'T',
        startedAtUtc: start,
        previousValueSource: PreviousValueSource.exercise,
      );

      expect(active.isActive, isTrue);
      expect(
        active
            .copyWith(endedAtUtc: () => start.add(const Duration(hours: 1)))
            .isActive,
        isFalse,
      );
      expect(active.copyWith(deletedAtUtc: () => start).isActive, isFalse);
    });

    test('copyWith can clear nullable fields explicitly', () {
      final ended = Workout(
        workoutId: 'w',
        title: 'T',
        notes: 'Notiz',
        startedAtUtc: start,
        endedAtUtc: start.add(const Duration(hours: 1)),
        previousValueSource: PreviousValueSource.exercise,
      );

      final resumed = ended.copyWith(endedAtUtc: () => null, notes: () => null);

      expect(resumed.endedAtUtc, isNull);
      expect(resumed.notes, isNull);
      expect(resumed.isActive, isTrue);
      expect(ended.endedAtUtc, isNotNull, reason: 'original stays immutable');
    });

    test('equal content yields equal objects and hash codes', () {
      final first = Workout.fromJson(contractWorkoutJson);
      final second = Workout.fromJson(contractWorkoutJson);
      final changed = first.copyWith(
        exercises: [
          first.exercises.single.copyWith(
            sets: [
              first.exercises.single.sets.first,
              first.exercises.single.sets[1].copyWith(repetitions: () => 9),
              first.exercises.single.sets.last,
            ],
          ),
        ],
      );

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(equals(changed)));
    });

    test('nested lists are unmodifiable', () {
      final workout = Workout.fromJson(contractWorkoutJson);

      expect(
        () => workout.exercises.add(workout.exercises.single),
        throwsUnsupportedError,
      );
      expect(
        () => workout.exercises.single.sets.clear(),
        throwsUnsupportedError,
      );
    });

    test(
      'exercise catalog entries round-trip and expose effective factors',
      () {
        final json = {
          'id': 'custom-1',
          'name': 'Landmine Press',
          'exerciseType': 'strength',
          'description': null,
          'targetMuscle': 'Schulter',
          'muscleGroup': 'Oberkörper',
          'equipment': 'Langhantel',
          'notes': 'Griff eng',
          'bodyweightFactor': null,
          'weightFactor': 2.5,
          'categoryIds': ['shoulders'],
          'isBase': false,
          'isArchived': false,
        };
        final exercise = CatalogExercise.fromJson(json);

        expect(exercise.toJson(), equals(json));
        expect(exercise.effectiveWeightFactor, 2.5);
        expect(exercise.effectiveBodyweightFactor, 0);
      },
    );

    test('catalog category round-trips', () {
      const json = {
        'id': 'cat-1',
        'name': 'Reha',
        'isBase': false,
        'isArchived': true,
      };

      expect(CatalogCategory.fromJson(json).toJson(), equals(json));
    });
  });
}
