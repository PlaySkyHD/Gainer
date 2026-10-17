import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_rules.dart';
import 'package:gainer_mobile/domain/models/training/workout_validation.dart';

import 'training_fixtures.dart';

void main() {
  group('set recording per exercise type', () {
    test('strength needs weight and repetitions', () {
      expect(
        isSetRecorded(loggedSet('s', kg: 100, reps: 8), ExerciseKind.strength),
        isTrue,
      );
      expect(
        isSetRecorded(loggedSet('s', reps: 8), ExerciseKind.strength),
        isFalse,
      );
      expect(
        isSetRecorded(loggedSet('s', kg: 100), ExerciseKind.strength),
        isFalse,
      );
    });

    test('bodyweight with added load counts a set without weight', () {
      expect(
        isSetRecorded(loggedSet('s', reps: 10), ExerciseKind.bodyweightLoaded),
        isTrue,
      );
      expect(
        isSetRecorded(loggedSet('s', reps: 0), ExerciseKind.bodyweightLoaded),
        isFalse,
      );
    });

    test('pure bodyweight needs only repetitions', () {
      expect(
        isSetRecorded(loggedSet('s', reps: 12), ExerciseKind.bodyweightOnly),
        isTrue,
      );
      expect(
        isSetRecorded(loggedSet('s', kg: 20), ExerciseKind.bodyweightOnly),
        isFalse,
      );
    });

    test('assisted needs support weight and repetitions', () {
      expect(
        isSetRecorded(loggedSet('s', kg: 20, reps: 8), ExerciseKind.assisted),
        isTrue,
      );
      expect(
        isSetRecorded(loggedSet('s', reps: 8), ExerciseKind.assisted),
        isFalse,
      );
    });

    test(
      'a block is complete only if it has sets and all of them are recorded',
      () {
        final complete = block('we', benchPress, [
          loggedSet('a', kg: 100, reps: 8),
          loggedSet('b', kg: 100, reps: 7),
          loggedSet('c', kg: 100, reps: 6),
        ]);
        final partial = block('we', benchPress, [
          loggedSet('a', kg: 100, reps: 8),
          loggedSet('b', kg: 100),
        ]);

        expect(isBlockComplete(complete), isTrue);
        expect(isBlockComplete(partial), isFalse);
        expect(isBlockComplete(block('we', benchPress, const [])), isFalse);
      },
    );

    test('pull-up without added weight is recorded with weight 0', () {
      final set = loggedSet('s', reps: 10);

      expect(isSetRecorded(set, pullUp.exerciseType), isTrue);
      expect(
        set.weightKg,
        isNull,
        reason: 'missing weight is never stored as 0',
      );
    });
  });

  group('set labels and supersets', () {
    test('warmup is W, normal sets are numbered, dropset is D', () {
      final labels = setLabels([
        loggedSet('a', type: SetType.warmup),
        loggedSet('b'),
        loggedSet('c', type: SetType.dropset),
        loggedSet('d'),
      ]);

      expect(labels, ['W', '1', 'D', '2']);
    });

    test(
      'only directly adjacent blocks with the same superset id form a group',
      () {
        final groups = supersetGroups([
          block('a', benchPress, const [], supersetId: 'x'),
          block('b', squat, const [], supersetId: 'y'),
          block('c', lateralRaise, const [], supersetId: 'x'),
        ]);

        expect(groups, hasLength(3));
        expect(groups.map((group) => group.isSuperset), everyElement(isFalse));
      },
    );

    test('adjacent blocks with the same id become one labeled superset', () {
      final groups = supersetGroups([
        block('a', benchPress, const [], supersetId: 'x'),
        block('b', squat, const [], supersetId: 'x'),
        block('c', lateralRaise, const []),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.blockIndexes, [0, 1]);
      expect(groups.first.labelAt(0), 'A');
      expect(groups.first.labelAt(1), 'B');
      expect(groups.last.labelAt(0), isNull);
    });

    test('empty superset ids are never grouped', () {
      final groups = supersetGroups([
        block('a', benchPress, const [], supersetId: ''),
        block('b', squat, const [], supersetId: ''),
      ]);

      expect(groups, hasLength(2));
    });
  });

  group('missing values', () {
    test('lists only sets with missing required values', () {
      final workout = workoutWithSets();

      final missing = missingValueSets(workout);

      expect(missing.map((item) => item.setId), ['b', 'c']);
      expect(missing.first.blockIndex, 0);
      expect(missing.first.setIndex, 1);
      expect(missing.last.workoutExerciseId, 'we-2');
    });
  });

  group('starting workouts', () {
    final catalog = [benchPress, pullUp, squat, lateralRaise];

    test(
      'plan start builds warmup sets first, then working sets, without values',
      () {
        final plan = TrainingPlanModel(
          planId: 'plan-push',
          name: 'Push',
          notes: 'Langsam',
          previousValueSource: PreviousValueSource.plan,
          entries: const [
            PlanEntry(
              entryId: 'e1',
              exerciseId: 'base-bench',
              warmupSets: 2,
              workingSets: 3,
              notes: 'Schulter',
            ),
          ],
        );

        final workout = workoutFromPlan(
          plan,
          catalog,
          sequentialIds(),
          fixtureNow,
        );

        expect(workout.title, 'Push');
        expect(workout.notes, 'Langsam');
        expect(workout.previousValueSource, PreviousValueSource.plan);
        expect(workout.sourcePlanId, 'plan-push');
        expect(workout.startedAtUtc, DateTime.utc(2026, 10, 17, 18, 30, 45));
        expect(workout.endedAtUtc, isNull);

        final block = workout.exercises.single;
        expect(block.sourceExerciseId, 'base-bench');
        expect(block.exerciseNameSnapshot, 'Bankdrücken');
        expect(block.exerciseTypeSnapshot, ExerciseKind.strength);
        expect(block.notes, 'Schulter');
        expect(setLabels(block.sets), ['W', 'W', '1', '2', '3']);
        expect(
          block.sets.every(
            (set) => set.weightKg == null && set.repetitions == null,
          ),
          isTrue,
        );
      },
    );

    test('plan start rejects an exercise that is not in the catalog', () {
      final unknownPlan = TrainingPlanModel(
        planId: 'p',
        name: 'Push',
        previousValueSource: PreviousValueSource.exercise,
        entries: const [PlanEntry(entryId: 'e', exerciseId: 'gone')],
      );

      expect(
        () =>
            workoutFromPlan(unknownPlan, catalog, sequentialIds(), fixtureNow),
        throwsA(isA<WorkoutValidationException>()),
      );
    });

    test(
      'repeating keeps structure, set types and supersets without values',
      () {
        final source = workout(
          id: 'old',
          startedAt: DateTime.utc(2026, 10, 10, 18),
          endedAt: DateTime.utc(2026, 10, 10, 19),
          title: 'Push',
          exercises: [
            block('we-1', benchPress, [
              loggedSet('s1', type: SetType.warmup, kg: 60, reps: 10, rir: 3),
              loggedSet('s2', kg: 100, reps: 8, rir: 2, notes: 'sauber'),
              loggedSet('s3', type: SetType.dropset, kg: 80, reps: 6),
            ], supersetId: 'ss-old'),
            block('we-2', squat, [
              loggedSet('s4', kg: 120, reps: 5),
            ], supersetId: 'ss-old'),
            block('we-3', lateralRaise, [loggedSet('s5', kg: 10, reps: 12)]),
          ],
        );

        final repeated = workoutFromRepeat(
          source,
          sequentialIds('new'),
          fixtureNow,
          PreviousValueSource.workout,
        );

        expect(repeated.title, 'Push');
        expect(repeated.sourceWorkoutId, 'old');
        expect(repeated.previousValueSource, PreviousValueSource.workout);
        expect(repeated.endedAtUtc, isNull);
        expect(repeated.exercises.map((block) => block.sourceExerciseId), [
          'base-bench',
          'base-squat',
          'base-lateral',
        ]);

        final first = repeated.exercises[0];
        expect(setLabels(first.sets), ['W', '1', 'D']);
        expect(
          first.sets.every(
            (set) =>
                set.weightKg == null &&
                set.repetitions == null &&
                set.rir == null,
          ),
          isTrue,
        );
        expect(first.sets[1].notes, isNull);

        expect(first.supersetId, isNotNull);
        expect(first.supersetId, isNot('ss-old'));
        expect(repeated.exercises[1].supersetId, first.supersetId);
        expect(repeated.exercises[2].supersetId, isNull);
      },
    );

    test('empty workout gets title, rounded start and no blocks', () {
      final workout = emptyWorkout(
        sequentialIds(),
        fixtureNow,
        'Leeres Training',
      );

      expect(workout.title, 'Leeres Training');
      expect(workout.exercises, isEmpty);
      expect(workout.isActive, isTrue);
      expect(workout.previousValueSource, PreviousValueSource.exercise);
      expect(workout.startedAtUtc, DateTime.utc(2026, 10, 17, 18, 30, 45));
    });
  });

  group('training as plan', () {
    test('one warmup and three working sets, dropsets count as working', () {
      final training = workout(
        id: 'w',
        startedAt: DateTime.utc(2026, 10, 17, 18),
        title: 'Beine',
        exercises: [
          block('we', squat, [
            loggedSet('a', type: SetType.warmup),
            loggedSet('b'),
            loggedSet('c', type: SetType.dropset),
            loggedSet('d'),
          ]),
        ],
      );

      final result = planFromWorkout(training, const [], sequentialIds('plan'));

      expect(result.plan.name, 'Beine');
      expect(result.existingPlan, isNull);
      expect(result.plan.entries.single.exerciseId, 'base-squat');
      expect(result.plan.entries.single.warmupSets, 1);
      expect(result.plan.entries.single.workingSets, 3);
    });

    test('detects a non-archived plan with the same name ignoring case', () {
      final existing = TrainingPlanModel(
        planId: 'old-push',
        name: 'push',
        previousValueSource: PreviousValueSource.exercise,
        sortOrder: 4,
      );
      final archived = TrainingPlanModel(
        planId: 'archived-push',
        name: 'PUSH',
        previousValueSource: PreviousValueSource.exercise,
        isArchived: true,
        sortOrder: 5,
      );
      final training = workout(
        id: 'w',
        startedAt: DateTime.utc(2026, 10, 17, 18),
        title: 'Push',
        exercises: [
          block('we', benchPress, [loggedSet('a', kg: 100, reps: 8)]),
        ],
      );

      final result = planFromWorkout(training, [
        archived,
        existing,
      ], sequentialIds('plan'));

      expect(result.existingPlan?.planId, 'old-push');
      expect(result.plan.sortOrder, 6, reason: 'new plan goes to the end');
    });

    test('blocks without sets are skipped because plan entries need a set', () {
      final training = workout(
        id: 'w',
        startedAt: DateTime.utc(2026, 10, 17, 18),
        exercises: [
          block('empty', benchPress, const []),
          block('full', squat, [loggedSet('a', kg: 100, reps: 5)]),
        ],
      );

      final result = planFromWorkout(training, const [], sequentialIds('plan'));

      expect(result.plan.entries.map((e) => e.exerciseId), ['base-squat']);
    });
  });

  group('rotation suggestion', () {
    final plans = [
      TrainingPlanModel(
        planId: 'push',
        name: 'Push',
        previousValueSource: PreviousValueSource.plan,
      ),
      TrainingPlanModel(
        planId: 'pull',
        name: 'Pull',
        previousValueSource: PreviousValueSource.plan,
      ),
      TrainingPlanModel(
        planId: 'legs',
        name: 'Beine',
        previousValueSource: PreviousValueSource.plan,
      ),
    ];
    final rotation = RotationModel(
      rotationId: 'rot',
      planIds: const ['push', 'pull', 'legs'],
    );

    Workout finished(
      String id,
      String planId,
      DateTime endedAt, {
      DateTime? deletedAt,
    }) => workout(
      id: id,
      startedAt: endedAt.subtract(const Duration(hours: 1)),
      endedAt: endedAt,
      source: PreviousValueSource.plan,
      sourcePlanId: planId,
      deletedAt: deletedAt,
    );

    test('suggests the plan after the most recently ended one', () {
      final next = nextRotationPlanId(rotation, plans, [
        finished('w1', 'push', DateTime.utc(2026, 10, 15, 19)),
      ]);

      expect(next, 'pull');
    });

    test('wraps around after the last plan of the rotation', () {
      final next = nextRotationPlanId(rotation, plans, [
        finished('w1', 'legs', DateTime.utc(2026, 10, 16, 19)),
        finished('w2', 'push', DateTime.utc(2026, 10, 14, 19)),
      ]);

      expect(next, 'push');
    });

    test('a deleted workout does not count towards the rotation', () {
      final next = nextRotationPlanId(rotation, plans, [
        finished(
          'w1',
          'pull',
          DateTime.utc(2026, 10, 16, 19),
          deletedAt: DateTime.utc(2026, 10, 16, 20),
        ),
        finished('w2', 'push', DateTime.utc(2026, 10, 14, 19)),
      ]);

      expect(next, 'pull');
    });

    test('archived plans are skipped', () {
      final withArchivedPull = [
        plans[0],
        TrainingPlanModel(
          planId: 'pull',
          name: 'Pull',
          previousValueSource: PreviousValueSource.plan,
          isArchived: true,
        ),
        plans[2],
      ];

      final next = nextRotationPlanId(rotation, withArchivedPull, [
        finished('w1', 'push', DateTime.utc(2026, 10, 15, 19)),
      ]);

      expect(next, 'legs');
    });

    test('an empty rotation or one without active plans suggests nothing', () {
      expect(
        nextRotationPlanId(RotationModel(rotationId: 'rot'), plans, const []),
        isNull,
      );
      expect(
        nextRotationPlanId(rotation, [
          for (final plan in plans) plan.copyWith(isArchived: true),
        ], const []),
        isNull,
      );
    });
  });
}

/// Ein Training mit einem vollständigen und einem unvollständigen Block.
Workout workoutWithSets() => workout(
  id: 'w',
  startedAt: DateTime.utc(2026, 10, 17, 18),
  exercises: [
    block('we-1', benchPress, [
      loggedSet('a', kg: 100, reps: 8),
      loggedSet('b', kg: 100),
    ]),
    block('we-2', pullUp, [loggedSet('c', reps: 0), loggedSet('d', reps: 10)]),
  ],
);
