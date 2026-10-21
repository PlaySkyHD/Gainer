import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/muscles.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _workoutId = '22222222-2222-4222-8222-222222222222';
const _workoutExerciseId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _setId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _exerciseId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _planId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _planId2 = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _categoryId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

const _scheduleId = '44444444-4444-4444-8444-444444444444';

Map<String, Object?> _scheduleBody() => {
  'scheduleId': _scheduleId,
  'mode': 'cycle',
  'anchorDate': '2026-10-20',
  'validFrom': '2026-10-21',
  'slots': [
    {'planId': _planId},
    {'planId': null},
  ],
  'shifts': [
    {'fromDate': '2026-10-23', 'days': 1},
  ],
  'exceptions': [
    {'date': '2026-10-22', 'planId': _planId, 'movedToDate': '2026-10-23'},
    {'date': '2026-10-25', 'planId': _planId, 'movedToDate': null},
  ],
};

LocalMutation _mutation(
  String type,
  LocalMutationOperation operation,
  String aggregateId,
  Object? body, {
  int? baseVersion = 1,
}) => LocalMutation(
  mutationId: '33333333-3333-4333-8333-333333333333',
  accountId: _accountId,
  aggregateType: type,
  aggregateId: aggregateId,
  sequence: 1,
  status: LocalMutationStatus.pending,
  createdAtUtc: DateTime.utc(2026, 10, 17),
  operation: operation,
  baseVersion: baseVersion,
  body: body,
);

Map<String, Object?> _workoutBody({String? endedAt}) => {
  'workoutId': _workoutId,
  'title': 'Push',
  'notes': null,
  'startedAtUtc': '2026-10-17T08:00:00.000Z',
  'endedAtUtc': endedAt,
  'previousValueSource': 'exercise',
  'sourcePlanId': null,
  'sourceWorkoutId': null,
  'exercises': [
    {
      'workoutExerciseId': _workoutExerciseId,
      'sourceExerciseId': _exerciseId,
      'exerciseNameSnapshot': 'Bankdrücken',
      'exerciseTypeSnapshot': 'strength',
      'notes': null,
      'supersetId': null,
      'sets': [
        {
          'setId': _setId,
          'setType': 'warmup',
          'weightKg': 40,
          'repetitions': null,
          'rir': null,
          'notes': null,
        },
        {
          'setId': 'cccccccc-cccc-4ccc-8ccc-cccccccccc02',
          'setType': 'normal',
          'weightKg': 80,
          'repetitions': 5,
          'rir': 2,
          'notes': null,
        },
      ],
    },
  ],
  'deletedAtUtc': null,
};

Map<String, Object?> _planBody({bool archived = false}) => {
  'planId': _planId,
  'name': 'Push A',
  'notes': null,
  'previousValueSource': 'plan',
  'entries': [
    {
      'entryId': 'ffffffff-ffff-4fff-8fff-fffffffffff1',
      'exerciseId': _exerciseId,
      'warmupSets': 1,
      'workingSets': 3,
      'notes': null,
      'supersetId': null,
    },
  ],
  'sortOrder': 2,
  'isArchived': archived,
};

void main() {
  group('operations', () {
    test('maps workout operations to the sync operation names', () {
      expect(
        SyncPayloadCodec.serverOperation(
          _mutation(
            'workout',
            LocalMutationOperation.create,
            _workoutId,
            _workoutBody(),
          ),
          _workoutBody(),
        ),
        'createWorkout',
      );
      expect(
        SyncPayloadCodec.serverOperation(
          _mutation(
            'workout',
            LocalMutationOperation.update,
            _workoutId,
            _workoutBody(endedAt: '2026-10-17T09:00:00.000Z'),
          ),
          _workoutBody(endedAt: '2026-10-17T09:00:00.000Z'),
        ),
        'saveWorkout',
      );
      expect(
        SyncPayloadCodec.serverOperation(
          _mutation(
            'workout',
            LocalMutationOperation.delete,
            _workoutId,
            _workoutBody(),
          ),
          _workoutBody(),
        ),
        'deleteWorkout',
      );
    });

    test('maps plan, schedule, exercise and category operations', () {
      String op(String type, LocalMutationOperation operation, Object? body) =>
          SyncPayloadCodec.serverOperation(
            _mutation(type, operation, _planId, body),
            body as Map<String, dynamic>,
          );
      expect(
        op('training-plan', LocalMutationOperation.create, _planBody()),
        'createTrainingPlan',
      );
      expect(
        op('training-plan', LocalMutationOperation.update, _planBody()),
        'updateTrainingPlan',
      );
      expect(
        op(
          'training-plan',
          LocalMutationOperation.update,
          _planBody(archived: true),
        ),
        'archiveTrainingPlan',
      );
      expect(
        op('training-plan', LocalMutationOperation.reorder, {
          'plans': <Object?>[],
        }),
        'reorderTrainingPlans',
      );
      expect(
        op('training-schedule', LocalMutationOperation.create, _scheduleBody()),
        'saveTrainingSchedule',
      );
      expect(
        op('training-schedule', LocalMutationOperation.update, _scheduleBody()),
        'saveTrainingSchedule',
      );
      expect(
        op('training-schedule', LocalMutationOperation.delete, _scheduleBody()),
        'deleteTrainingSchedule',
      );
      expect(
        op('custom-exercise', LocalMutationOperation.merge, {
          'targetExerciseId': _planId2,
        }),
        'mergeExercises',
      );
      expect(
        op('exercise-category', LocalMutationOperation.create, {
          'name': 'Beine',
        }),
        'createExerciseCategory',
      );
      expect(
        op('exercise-category', LocalMutationOperation.update, {
          'name': 'Beine',
          'isArchived': false,
        }),
        'updateExerciseCategory',
      );
      expect(
        op('exercise-category', LocalMutationOperation.update, {
          'name': 'Beine',
          'isArchived': true,
        }),
        'archiveExerciseCategory',
      );
    });
  });

  group('payloads', () {
    test('create workout sends the workout without local fields', () {
      final body = _workoutBody();
      final payload = SyncPayloadCodec.serverPayload(
        _mutation('workout', LocalMutationOperation.create, _workoutId, body),
        body,
        0,
      );
      expect(payload, {
        'workout': {
          'workoutId': _workoutId,
          'title': 'Push',
          'startedAtUtc': '2026-10-17T08:00:00.000Z',
          'previousValueSource': 'exercise',
          'exercises': [
            {
              'workoutExerciseId': _workoutExerciseId,
              'sourceExerciseId': _exerciseId,
              'exerciseNameSnapshot': 'Bankdrücken',
              'exerciseTypeSnapshot': 'strength',
              'sets': [
                {'setId': _setId, 'setType': 'warmup', 'weightKg': 40},
                {
                  'setId': 'cccccccc-cccc-4ccc-8ccc-cccccccccc02',
                  'setType': 'normal',
                  'weightKg': 80,
                  'repetitions': 5,
                  'rir': 2,
                },
              ],
            },
          ],
        },
      });
    });

    test('save workout adds the base version and the end time', () {
      final body = _workoutBody(endedAt: '2026-10-17T09:00:00.000Z');
      final payload = SyncPayloadCodec.serverPayload(
        _mutation('workout', LocalMutationOperation.update, _workoutId, body),
        body,
        7,
      ) as Map<String, dynamic>;
      expect(payload['baseVersion'], 7);
      expect(
        (payload['workout'] as Map<String, dynamic>)['endedAtUtc'],
        '2026-10-17T09:00:00.000Z',
      );
      expect(payload.containsKey('deletedAtUtc'), isFalse);
    });

    test('delete workout sends its id and base version', () {
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'workout',
            LocalMutationOperation.delete,
            _workoutId,
            _workoutBody(),
          ),
          _workoutBody(),
          3,
        ),
        {'workoutId': _workoutId, 'baseVersion': 3},
      );
    });

    test('create plan keeps entries and drops sort order and archive flag', () {
      final body = _planBody();
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'training-plan',
            LocalMutationOperation.create,
            _planId,
            body,
          ),
          body,
          0,
        ),
        {
          'plan': {
            'planId': _planId,
            'name': 'Push A',
            'previousValueSource': 'plan',
            'entries': [
              {
                'entryId': 'ffffffff-ffff-4fff-8fff-fffffffffff1',
                'exerciseId': _exerciseId,
                'warmupSets': 1,
                'workingSets': 3,
              },
            ],
          },
        },
      );
    });

    test('update plan and archive plan use their own payload shapes', () {
      final body = _planBody();
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'training-plan',
            LocalMutationOperation.update,
            _planId,
            body,
          ),
          body,
          4,
        ),
        {
          'baseVersion': 4,
          'plan': {
            'planId': _planId,
            'name': 'Push A',
            'previousValueSource': 'plan',
            'entries': [
              {
                'entryId': 'ffffffff-ffff-4fff-8fff-fffffffffff1',
                'exerciseId': _exerciseId,
                'warmupSets': 1,
                'workingSets': 3,
              },
            ],
          },
        },
      );
      final archived = _planBody(archived: true);
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'training-plan',
            LocalMutationOperation.update,
            _planId,
            archived,
          ),
          archived,
          4,
        ),
        {'planId': _planId, 'baseVersion': 4},
      );
    });

    test('reorder plans lists every plan with its base version', () {
      final body = {
        'plans': [
          {'planId': _planId2, 'baseVersion': 5},
          {'planId': _planId, 'baseVersion': 2},
        ],
      };
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'training-plan',
            LocalMutationOperation.reorder,
            _planId2,
            body,
          ),
          body,
          5,
        ),
        {
          'plans': [
            {'planId': _planId2, 'baseVersion': 5},
            {'planId': _planId, 'baseVersion': 2},
          ],
        },
      );
    });

    test('save schedule sends the full D3a state', () {
      final body = _scheduleBody();
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'training-schedule',
            LocalMutationOperation.update,
            _scheduleId,
            body,
          ),
          body,
          9,
        ),
        {
          'scheduleId': _scheduleId,
          'baseVersion': 9,
          'mode': 'cycle',
          'anchorDate': '2026-10-20',
          'validFrom': '2026-10-21',
          'slots': [
            {'planId': _planId},
            {'planId': null},
          ],
          'shifts': [
            {'fromDate': '2026-10-23', 'days': 1},
          ],
          'exceptions': [
            {
              'date': '2026-10-22',
              'planId': _planId,
              'movedToDate': '2026-10-23',
            },
            {'date': '2026-10-25', 'planId': _planId, 'movedToDate': null},
          ],
        },
      );
    });

    test('first schedule save sends base version 0, weekly without anchor', () {
      final body = TrainingSchedule.create(
        scheduleId: _scheduleId,
        mode: TrainingScheduleMode.weekly,
        slots: [
          const TrainingScheduleSlot(planId: _planId),
          for (var i = 0; i < 6; i++) const TrainingScheduleSlot.rest(),
        ],
        today: LocalDay(2026, 10, 21),
      ).toJson();
      final payload =
          SyncPayloadCodec.serverPayload(
                _mutation(
                  'training-schedule',
                  LocalMutationOperation.create,
                  _scheduleId,
                  body,
                  baseVersion: 0,
                ),
                body,
                0,
              )!
              as Map<String, Object?>;
      expect(payload['baseVersion'], 0);
      expect(payload['mode'], 'weekly');
      expect(payload.containsKey('anchorDate'), isTrue);
      expect(payload['anchorDate'], isNull);
      expect(payload['slots'], hasLength(7));
      expect(payload['shifts'], isEmpty);
      expect(payload['exceptions'], isEmpty);
    });

    test('delete schedule sends id and base version only', () {
      final body = {..._scheduleBody(), 'deletedAtUtc': '2026-10-21T08:00:00Z'};
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'training-schedule',
            LocalMutationOperation.delete,
            _scheduleId,
            body,
          ),
          body,
          3,
        ),
        {'scheduleId': _scheduleId, 'baseVersion': 3},
      );
    });

    test('schedule references its plans so they are sent first', () {
      expect(
        SyncPayloadCodec.referencedAggregateIds(
          _mutation(
            'training-schedule',
            LocalMutationOperation.update,
            _scheduleId,
            {
              ..._scheduleBody(),
              'exceptions': [
                {'date': '2026-10-22', 'planId': _planId2, 'movedToDate': null},
              ],
            },
          ),
        ),
        {_planId, _planId2},
      );
    });

    test(
      'custom exercise create sends values without empty optional fields',
      () {
        final exercise = CatalogExercise(
          id: _exerciseId,
          name: 'Kurzhantelzug',
          exerciseType: ExerciseKind.strength,
          weightFactor: 0.5,
          categoryIds: const [_categoryId],
          isBase: false,
        ).toJson();
        expect(
          SyncPayloadCodec.serverPayload(
            _mutation(
              'custom-exercise',
              LocalMutationOperation.create,
              _exerciseId,
              exercise,
            ),
            exercise,
            0,
          ),
          {
            'exerciseId': _exerciseId,
            'values': {
              'name': 'Kurzhantelzug',
              'exerciseType': 'strength',
              'weightFactor': 0.5,
              'categoryIds': [_categoryId],
            },
          },
        );
      },
    );

    test('custom exercise update sends muscle keys', () {
      final exercise = CatalogExercise(
        id: _exerciseId,
        name: 'Schrägbankdrücken',
        exerciseType: ExerciseKind.strength,
        primaryMuscles: const [Muscle.chest],
        secondaryMuscles: const [Muscle.triceps, Muscle.frontDelts],
        isBase: false,
      ).toJson();
      final payload =
          SyncPayloadCodec.serverPayload(
                _mutation(
                  'custom-exercise',
                  LocalMutationOperation.update,
                  _exerciseId,
                  exercise,
                ),
                exercise,
                3,
              )!
              as Map<String, Object?>;
      final values = payload['values']! as Map<String, Object?>;
      expect(values['primaryMuscles'], ['chest']);
      expect(values['secondaryMuscles'], ['triceps', 'frontDelts']);
    });

    test('custom exercise archive sends id and base version only', () {
      final exercise = CatalogExercise(
        id: _exerciseId,
        name: 'Rudern',
        exerciseType: ExerciseKind.strength,
        isBase: false,
        isArchived: true,
      ).toJson();
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'custom-exercise',
            LocalMutationOperation.update,
            _exerciseId,
            exercise,
          ),
          exercise,
          2,
        ),
        {'exerciseId': _exerciseId, 'baseVersion': 2},
      );
    });

    test('merge sends source version and target id', () {
      final body = {
        ...CatalogExercise(
          id: _exerciseId,
          name: 'Rudern',
          exerciseType: ExerciseKind.strength,
          isBase: false,
          isArchived: true,
        ).toJson(),
        'targetExerciseId': _planId2,
        'targetBaseVersion': null,
      };
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'custom-exercise',
            LocalMutationOperation.merge,
            _exerciseId,
            body,
          ),
          body,
          3,
        ),
        {
          'sourceExerciseId': _exerciseId,
          'sourceBaseVersion': 3,
          'targetExerciseId': _planId2,
        },
      );
    });

    test('category create, update and archive payloads', () {
      final create = {'id': _categoryId, 'name': 'Beine'};
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'exercise-category',
            LocalMutationOperation.create,
            _categoryId,
            create,
          ),
          create,
          0,
        ),
        {'categoryId': _categoryId, 'name': 'Beine'},
      );
      final update = {'id': _categoryId, 'name': 'Core', 'isArchived': false};
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'exercise-category',
            LocalMutationOperation.update,
            _categoryId,
            update,
          ),
          update,
          1,
        ),
        {'categoryId': _categoryId, 'baseVersion': 1, 'name': 'Core'},
      );
      final archive = {'id': _categoryId, 'name': 'Core', 'isArchived': true};
      expect(
        SyncPayloadCodec.serverPayload(
          _mutation(
            'exercise-category',
            LocalMutationOperation.update,
            _categoryId,
            archive,
          ),
          archive,
          1,
        ),
        {'categoryId': _categoryId, 'baseVersion': 1},
      );
    });
  });

  group('snapshots', () {
    test('workout snapshot keeps model ids and drops the server version', () {
      final snapshot =
          SyncPayloadCodec.normalizeSnapshot('Workout', {
                ..._workoutBody(endedAt: '2026-10-17T09:00:00.000Z'),
                'createdAtUtc': '2026-10-17T08:00:00Z',
                'updatedAtUtc': '2026-10-17T09:00:00Z',
                'version': 4,
              })!
              as Map<String, dynamic>;
      expect(snapshot.containsKey('version'), isFalse);
      expect(snapshot['workoutId'], _workoutId);
      final workout = Workout.fromJson(snapshot);
      expect(workout.exercises.single.workoutExerciseId, _workoutExerciseId);
      expect(workout.exercises.single.sets.last.setId, isNot(_setId));
      expect(workout.exercises.single.sets.first.setId, _setId);
      expect(workout.endedAtUtc, DateTime.utc(2026, 10, 17, 9));
    });

    test('unknown set type reads as a normal set', () {
      final body = _workoutBody();
      final exercises = body['exercises']! as List<Object?>;
      final sets =
          (exercises.single! as Map<String, Object?>)['sets']! as List<Object?>;
      (sets.first! as Map<String, Object?>)['setType'] = 'future-type';
      final snapshot = SyncPayloadCodec.normalizeSnapshot('Workout', body);
      expect(
        Workout.fromJson(snapshot! as Map<String, Object?>)
            .exercises
            .single
            .sets
            .first
            .setType,
        SetType.normal,
      );
    });

    test('custom exercise snapshot becomes a catalog exercise', () {
      final snapshot =
          SyncPayloadCodec.normalizeSnapshot('CustomExercise', {
                'exerciseId': _exerciseId,
                'values': {
                  'name': 'Rudern',
                  'exerciseType': 'bodyweightLoaded',
                  'categoryIds': [_categoryId],
                },
                'isArchived': false,
                'createdAtUtc': '2026-10-17T08:00:00Z',
                'updatedAtUtc': '2026-10-17T08:00:00Z',
                'version': 2,
              })!
              as Map<String, dynamic>;
      final exercise = CatalogExercise.fromJson(snapshot);
      expect(exercise.id, _exerciseId);
      expect(exercise.isBase, isFalse);
      expect(exercise.exerciseType, ExerciseKind.bodyweightLoaded);
      expect(exercise.categoryIds, [_categoryId]);
    });

    test('category and schedule snapshots keep their identifiers', () {
      final category =
          SyncPayloadCodec.normalizeSnapshot('ExerciseCategory', {
                'categoryId': _categoryId,
                'name': 'Beine',
                'isArchived': true,
                'createdAtUtc': '2026-10-17T08:00:00Z',
                'updatedAtUtc': '2026-10-17T08:00:00Z',
                'version': 1,
              })!
              as Map<String, dynamic>;
      expect(CatalogCategory.fromJson(category).id, _categoryId);
      expect(CatalogCategory.fromJson(category).isArchived, isTrue);

      final schedule =
          SyncPayloadCodec.normalizeSnapshot('TrainingSchedule', {
                ..._scheduleBody(),
                'updatedAtUtc': '2026-10-17T08:00:00Z',
                'version': 3,
              })!
              as Map<String, dynamic>;
      SyncPayloadCodec.verifyTrainingSnapshot('TrainingSchedule', schedule);
      expect(TrainingSchedule.fromJson(schedule).scheduleId, _scheduleId);
      expect(schedule.containsKey('version'), isFalse);
      expect(
        () => SyncPayloadCodec.verifyTrainingSnapshot('TrainingSchedule', {
          ..._scheduleBody(),
          'mode': 'monthly',
        }),
        throwsFormatException,
      );
    });

    test('plan snapshot keeps sort order and archive state', () {
      final snapshot =
          SyncPayloadCodec.normalizeSnapshot('TrainingPlan', {
                ..._planBody(archived: true),
                'createdAtUtc': '2026-10-17T08:00:00Z',
                'updatedAtUtc': '2026-10-17T08:00:00Z',
                'version': 5,
              })!
              as Map<String, dynamic>;
      final plan = TrainingPlanModel.fromJson(snapshot);
      expect(plan.planId, _planId);
      expect(plan.sortOrder, 2);
      expect(plan.isArchived, isTrue);
      expect(plan.entries.single.workingSets, 3);
    });

    test('verification rejects an unknown exercise type', () {
      final snapshot = SyncPayloadCodec.normalizeSnapshot('CustomExercise', {
        'exerciseId': _exerciseId,
        'values': {'name': 'Neu', 'exerciseType': 'unknown'},
        'isArchived': false,
        'createdAtUtc': '2026-10-17T08:00:00Z',
        'updatedAtUtc': '2026-10-17T08:00:00Z',
        'version': 1,
      })!;
      expect(
        () =>
            SyncPayloadCodec.verifyTrainingSnapshot('CustomExercise', snapshot),
        throwsFormatException,
      );
    });
  });
}
