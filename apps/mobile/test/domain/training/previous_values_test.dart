import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/previous_values.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

import 'training_fixtures.dart';

void main() {
  final current = workout(
    id: 'current',
    startedAt: DateTime.utc(2026, 10, 17, 18),
    source: PreviousValueSource.exercise,
    exercises: [
      block('cur-bench', benchPress, [
        loggedSet('c1'),
        loggedSet('c2'),
        loggedSet('c3'),
      ]),
    ],
  );

  List<double?> weights(List<LoggedSet?> sets) =>
      sets.map((set) => set?.weightKg).toList();
  List<int?> reps(List<LoggedSet?> sets) =>
      sets.map((set) => set?.repetitions).toList();

  test(
    'uses the newest eligible workout by exercise and skips empty blocks',
    () {
      final history = [
        workout(
          id: 'recent-empty',
          startedAt: DateTime.utc(2026, 10, 16, 18),
          exercises: [
            block('r', squat, [loggedSet('x')]),
          ],
        ),
        workout(
          id: 'older',
          startedAt: DateTime.utc(2026, 10, 10, 18),
          exercises: [
            block('o', squat, [loggedSet('a', kg: 120, reps: 5)]),
          ],
        ),
      ];
      final training = workout(
        id: 'now',
        startedAt: DateTime.utc(2026, 10, 17, 18),
        exercises: [
          block('n', squat, [loggedSet('n1')]),
        ],
      );

      final previous = previousValuesFor(training, history);

      expect(weights(previous['n']!), [120]);
      expect(reps(previous['n']!), [5]);
    },
  );

  test('only workouts that started before the current one are considered', () {
    final later = workout(
      id: 'later',
      startedAt: DateTime.utc(2026, 10, 18, 18),
      exercises: [
        block('l', benchPress, [loggedSet('a', kg: 999, reps: 1)]),
      ],
    );

    final previous = previousValuesFor(current, [later]);

    expect(previous['cur-bench'], [null, null, null]);
  });

  test('deleted workouts never provide previous values', () {
    final deleted = workout(
      id: 'deleted',
      startedAt: DateTime.utc(2026, 10, 16, 18),
      deletedAt: DateTime.utc(2026, 10, 16, 20),
      exercises: [
        block('d', benchPress, [loggedSet('a', kg: 100, reps: 8)]),
      ],
    );

    final previous = previousValuesFor(current, [deleted]);

    expect(previous['cur-bench'], [null, null, null]);
  });

  test('strength blocks need repetitions above zero to be eligible', () {
    final history = [
      workout(
        id: 'only-weight',
        startedAt: DateTime.utc(2026, 10, 16, 18),
        exercises: [
          block('w', benchPress, [loggedSet('a', kg: 140, reps: 0)]),
        ],
      ),
      workout(
        id: 'usable',
        startedAt: DateTime.utc(2026, 10, 10, 18),
        exercises: [
          block('u', benchPress, [loggedSet('b', kg: 100, reps: 8)]),
        ],
      ),
    ];

    final previous = previousValuesFor(current, history);

    expect(weights(previous['cur-bench']!), [100, null, null]);
  });

  test(
    'plan source prefers the newest workout of the same plan with fallback',
    () {
      final planned = workout(
        id: 'planned',
        startedAt: DateTime.utc(2026, 10, 15, 18),
        sourcePlanId: 'push',
        exercises: [
          block('p', benchPress, [loggedSet('a', kg: 90, reps: 10)]),
        ],
      );
      final other = workout(
        id: 'other',
        startedAt: DateTime.utc(2026, 10, 16, 18),
        exercises: [
          block('o', benchPress, [loggedSet('b', kg: 110, reps: 6)]),
        ],
      );
      final withPlanSource = workout(
        id: 'now',
        startedAt: DateTime.utc(2026, 10, 17, 18),
        source: PreviousValueSource.plan,
        sourcePlanId: 'push',
        exercises: [
          block('n', benchPress, [loggedSet('n1')]),
        ],
      );

      expect(
        weights(previousValuesFor(withPlanSource, [other, planned])['n']!),
        [90],
      );

      final pullDay = workout(
        id: 'now-pull',
        startedAt: DateTime.utc(2026, 10, 17, 18),
        source: PreviousValueSource.plan,
        sourcePlanId: 'pull',
        exercises: [
          block('n', benchPress, [loggedSet('n1')]),
        ],
      );
      expect(weights(previousValuesFor(pullDay, [other, planned])['n']!), [
        110,
      ], reason: 'no workout of plan "pull" exists, falls back to exercise');
    },
  );

  test(
    'workout source uses the referenced workout and falls back when missing',
    () {
      final referenced = workout(
        id: 'source',
        startedAt: DateTime.utc(2026, 10, 1, 18),
        exercises: [
          block('s', benchPress, [loggedSet('a', kg: 75, reps: 12)]),
        ],
      );
      final newer = workout(
        id: 'newer',
        startedAt: DateTime.utc(2026, 10, 16, 18),
        exercises: [
          block('n', benchPress, [loggedSet('b', kg: 120, reps: 3)]),
        ],
      );
      final repeated = workout(
        id: 'repeat',
        startedAt: DateTime.utc(2026, 10, 17, 18),
        source: PreviousValueSource.workout,
        sourceWorkoutId: 'source',
        exercises: [
          block('r', benchPress, [loggedSet('r1')]),
        ],
      );

      expect(weights(previousValuesFor(repeated, [newer, referenced])['r']!), [
        75,
      ]);

      final missingSource = workout(
        id: 'repeat-deleted',
        startedAt: DateTime.utc(2026, 10, 17, 18),
        source: PreviousValueSource.workout,
        sourceWorkoutId: 'gone',
        exercises: [
          block('r', benchPress, [loggedSet('r1')]),
        ],
      );
      expect(
        weights(previousValuesFor(missingSource, [newer, referenced])['r']!),
        [120],
        reason: 'a missing source workout falls back to the exercise rule',
      );
    },
  );

  test(
    'repeated exercises map the nth occurrence to the nth eligible block',
    () {
      final history = [
        workout(
          id: 'source',
          startedAt: DateTime.utc(2026, 10, 16, 18),
          exercises: [
            block('a', benchPress, [loggedSet('a1', kg: 100, reps: 8)]),
            block('b', benchPress, [loggedSet('b1', kg: 60, reps: 12)]),
          ],
        ),
      ];
      final training = workout(
        id: 'now',
        startedAt: DateTime.utc(2026, 10, 17, 18),
        exercises: [
          block('n1', benchPress, [loggedSet('x')]),
          block('n2', benchPress, [loggedSet('y')]),
          block('n3', benchPress, [loggedSet('z')]),
        ],
      );

      final previous = previousValuesFor(training, history);

      expect(weights(previous['n1']!), [100]);
      expect(weights(previous['n2']!), [60]);
      expect(weights(previous['n3']!), [
        100,
      ], reason: 'beyond the last eligible block it falls back to the first');
    },
  );

  test('sets map by position and surplus sets get no previous value', () {
    final history = [
      workout(
        id: 'source',
        startedAt: DateTime.utc(2026, 10, 16, 18),
        exercises: [
          block('a', benchPress, [
            loggedSet('a1', kg: 100, reps: 8),
            loggedSet('a2', kg: 100, reps: 7),
          ]),
        ],
      ),
    ];

    final previous = previousValuesFor(current, history);

    expect(weights(previous['cur-bench']!), [100, 100, null]);
    expect(reps(previous['cur-bench']!), [8, 7, null]);
  });

  test('sets map by position within the same set type', () {
    final history = [
      workout(
        id: 'source',
        startedAt: DateTime.utc(2026, 10, 16, 18),
        exercises: [
          block('a', benchPress, [
            loggedSet('a1', kg: 100, reps: 8),
            loggedSet('a2', kg: 95, reps: 7),
          ]),
        ],
      ),
    ];
    final training = workout(
      id: 'now',
      startedAt: DateTime.utc(2026, 10, 17, 18),
      exercises: [
        block('n', benchPress, [
          loggedSet('w1', type: SetType.warmup, kg: 50, reps: 8),
          loggedSet('w2', type: SetType.warmup, kg: 80, reps: 3),
          loggedSet('n1'),
          loggedSet('n2'),
        ]),
      ],
    );

    final previous = previousValuesFor(training, history);

    // Aufwärmsätze ohne Vorgänger verschieben die Arbeitssätze nicht.
    expect(weights(previous['n']!), [null, null, 100, 95]);
    expect(reps(previous['n']!), [null, null, 8, 7]);
  });

  test(
    'applying previous values fills only empty fields and never inserts zero',
    () {
      final training = Workout(
        workoutId: 'now',
        title: 'Push',
        startedAtUtc: DateTime.utc(2026, 10, 17, 18),
        previousValueSource: PreviousValueSource.exercise,
        exercises: [
          block('bench', benchPress, [
            loggedSet('empty'),
            loggedSet('own-weight', kg: 80),
            loggedSet('third'),
          ]),
        ],
      );
      final previous = {
        'bench': [
          loggedSet('p1', kg: 100, reps: 8),
          loggedSet('p2', kg: 105, reps: 6),
          null,
        ],
      };

      final filled = applyPreviousValues(training, previous);
      final sets = filled.exercises.single.sets;

      expect(sets[0].weightKg, 100);
      expect(sets[0].repetitions, 8);
      expect(sets[1].weightKg, 80, reason: 'own value stays');
      expect(sets[1].repetitions, 6);
      expect(sets[2].weightKg, isNull, reason: 'no previous value stays empty');
      expect(sets[2].repetitions, isNull);
    },
  );

  test('without any history every field stays empty', () {
    final previous = previousValuesFor(current, const []);

    expect(previous['cur-bench'], [null, null, null]);
    final applied = applyPreviousValues(current, previous);
    expect(applied.exercises.single.sets.map((set) => set.weightKg), [
      null,
      null,
      null,
    ]);
  });
}
