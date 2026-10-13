import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _aggregateId = '22222222-2222-4222-8222-222222222222';

LocalMutation _mutation(
  String type,
  LocalMutationOperation operation,
  Object? body,
) => LocalMutation(
  mutationId: '33333333-3333-4333-8333-333333333333',
  accountId: _accountId,
  aggregateType: type,
  aggregateId: _aggregateId,
  sequence: 1,
  status: LocalMutationStatus.pending,
  createdAtUtc: DateTime.utc(2026),
  operation: operation,
  baseVersion: 1,
  body: body,
);

void main() {
  test('maps all nine backend resource names to PWA aggregate types', () {
    expect(
      [
        'BodyGoal',
        'DailyCheckIn',
        'CustomExercise',
        'WorkoutTemplate',
        'WorkoutRotation',
        'Workout',
        'NutritionDay',
        'ReusableMeal',
        'NutritionTargetSchedule',
      ].map(SyncPayloadCodec.aggregateTypeForResource).toList(),
      [
        'body-goal',
        'daily-check-in',
        'custom-exercise',
        'workout-template',
        'workout-rotation',
        'workout',
        'nutrition-day',
        'reusable-meal',
        'nutrition-target-schedule',
      ],
    );
  });

  test(
    'normalizes check-in and exercise values and preserves body-goal fields',
    () {
      final checkIn =
          SyncPayloadCodec.normalizeSnapshot('DailyCheckIn', {
                'checkInId': _aggregateId,
                'version': 3,
                'localDate': '2026-01-01',
                'values': {'weightKg': 80, 'steps': 1000},
                'createdAtUtc': '2026-01-01T10:00:00Z',
                'updatedAtUtc': '2026-01-01T10:00:00Z',
              })!
              as Map<String, dynamic>;
      expect(checkIn['weightKg'], 80);
      expect(checkIn['steps'], 1000);
      final checkInPayload =
          SyncPayloadCodec.serverPayload(
                _mutation(
                  'daily-check-in',
                  LocalMutationOperation.create,
                  checkIn,
                ),
                checkIn,
                0,
              )!
              as Map<String, dynamic>;
      expect(checkInPayload['values'], {'weightKg': 80, 'steps': 1000});

      final exercise =
          SyncPayloadCodec.normalizeSnapshot('CustomExercise', {
                'exerciseId': _aggregateId,
                'version': 2,
                'values': {
                  'name': 'Row',
                  'description': null,
                  'targetMuscle': 'back',
                  'muscleGroup': 'upper-body',
                  'equipment': 'cable',
                },
                'isArchived': false,
                'createdAtUtc': '2026-01-01T10:00:00Z',
                'updatedAtUtc': '2026-01-01T10:00:00Z',
              })!
              as Map<String, dynamic>;
      final exercisePayload =
          SyncPayloadCodec.serverPayload(
                _mutation(
                  'custom-exercise',
                  LocalMutationOperation.create,
                  exercise,
                ),
                exercise,
                0,
              )!
              as Map<String, dynamic>;
      expect(exercisePayload['values']['name'], 'Row');
      expect(exercisePayload['values']['equipment'], 'cable');

      final goal =
          SyncPayloadCodec.normalizeSnapshot('BodyGoal', {
                'goalId': _aggregateId,
                'version': 5,
                'kind': 'gain',
                'startWeightKg': 80,
                'targetWeightKg': 85,
                'startDate': '2026-01-01',
                'targetDate': null,
                'createdAtUtc': '2026-01-01T10:00:00Z',
                'endedAtUtc': null,
              })!
              as Map<String, dynamic>;
      final goalPayload =
          SyncPayloadCodec.serverPayload(
                _mutation('body-goal', LocalMutationOperation.update, goal),
                goal,
                5,
              )!
              as Map<String, dynamic>;
      expect(goalPayload['goalId'], _aggregateId);
      expect(goalPayload['targetWeightKg'], 85);
    },
  );

  test('normalizes template and rotation nested identifiers for PWA edits', () {
    final template =
        SyncPayloadCodec.normalizeSnapshot('WorkoutTemplate', {
              'templateId': _aggregateId,
              'version': 7,
              'name': 'Push',
              'isArchived': false,
              'items': [
                {
                  'itemId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                  'exerciseId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                  'plannedSets': 3,
                  'minimumRepetitions': 8,
                  'maximumRepetitions': 10,
                  'targetRir': 2,
                  'restSeconds': 90,
                  'notes': 'controlled',
                },
              ],
            })!
            as Map<String, dynamic>;
    final templateItem = (template['items'] as List).single as Map;
    expect(templateItem['id'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(templateItem.containsKey('itemId'), isFalse);
    final templatePayload =
        SyncPayloadCodec.serverPayload(
              _mutation(
                'workout-template',
                LocalMutationOperation.update,
                template,
              ),
              template,
              7,
            )!
            as Map<String, dynamic>;
    expect(
      (templatePayload['items'] as List).single['itemId'],
      templateItem['id'],
    );

    final rotation =
        SyncPayloadCodec.normalizeSnapshot('WorkoutRotation', {
              'rotationId': _aggregateId,
              'version': 4,
              'entries': [
                {
                  'itemId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
                  'templateId': _aggregateId,
                },
              ],
              'lastCompletedTemplateId': null,
              'nextTemplateId': _aggregateId,
            })!
            as Map<String, dynamic>;
    final entry = (rotation['entries'] as List).single as Map;
    expect(entry['id'], 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    final rotationPayload =
        SyncPayloadCodec.serverPayload(
              _mutation(
                'workout-rotation',
                LocalMutationOperation.update,
                rotation,
              ),
              rotation,
              4,
            )!
            as Map<String, dynamic>;
    expect((rotationPayload['entries'] as List).single['itemId'], entry['id']);
  });

  test(
    'normalizes workout exercise and set IDs and maps them back on edit',
    () {
      final source = {
        'workoutId': _aggregateId,
        'version': 8,
        'sourceTemplateId': null,
        'templateNameSnapshot': 'Workout',
        'status': 'inProgress',
        'exercises': [
          {
            'workoutExerciseId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'sourceExerciseId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            'exerciseNameSnapshot': 'Squat',
            'plannedSets': 1,
            'minimumRepetitions': 5,
            'maximumRepetitions': 5,
            'targetRir': 2,
            'restSeconds': null,
            'notes': null,
            'sets': [
              {
                'setId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
                'weightKg': 80,
                'repetitions': 5,
                'rir': 2,
                'notes': null,
                'isCompleted': true,
                'completedAtUtc': '2026-01-01T12:00:00Z',
              },
            ],
          },
        ],
      };
      final working =
          SyncPayloadCodec.normalizeSnapshot('Workout', source)!
              as Map<String, dynamic>;
      final exercise = (working['exercises'] as List).single as Map;
      final set = (exercise['sets'] as List).single as Map;
      expect(exercise['id'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(set['id'], 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
      final payload =
          SyncPayloadCodec.serverPayload(
                _mutation('workout', LocalMutationOperation.update, working),
                working,
                8,
              )!
              as Map<String, dynamic>;
      final payloadExercise = (payload['exercises'] as List).single as Map;
      final payloadSet = (payloadExercise['sets'] as List).single as Map;
      expect(payloadExercise['workoutExerciseId'], exercise['id']);
      expect(payloadSet['setId'], set['id']);
      expect(source['exercises']!.toString(), contains('workoutExerciseId'));
    },
  );

  test(
    'preserves nutrition source metadata including barcode through edit DTO',
    () {
      final source = {
        'nutritionDayId': _aggregateId,
        'version': 2,
        'localDate': '2026-01-01',
        'entries': [
          {
            'entryId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'meal': 'breakfast',
            'position': 0,
            'productName': 'Oats',
            'brand': null,
            'amountGrams': 50,
            'totals': {'kilocalories': 190},
            'per100Grams': {
              'kilocalories': 380,
              'proteinGrams': 13,
              'carbohydrateGrams': 68,
              'fatGrams': 7,
            },
            'source': {
              'provider': 'OpenFoodFacts',
              'barcode': '4001234567890',
              'retrievedAtUtc': '2026-01-01T10:00:00Z',
              'basisGrams': 100,
            },
          },
        ],
      };
      final working =
          SyncPayloadCodec.normalizeSnapshot('NutritionDay', source)!
              as Map<String, dynamic>;
      final payload =
          SyncPayloadCodec.serverPayload(
                _mutation(
                  'nutrition-day',
                  LocalMutationOperation.update,
                  working,
                ),
                working,
                2,
              )!
              as Map<String, dynamic>;
      final entry = (payload['entries'] as List).single as Map;
      expect(entry['entryId'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(entry['kilocaloriesPer100Grams'], 380);
      expect(entry['source'], (source['entries'] as List).single['source']);
    },
  );

  test(
    'keeps reusable component and nutrition-target version snapshots editable',
    () {
      final meal =
          SyncPayloadCodec.normalizeSnapshot('ReusableMeal', {
                'reusableMealId': _aggregateId,
                'version': 3,
                'name': 'Oats',
                'description': null,
                'standardPortion': 1,
                'status': 'Active',
                'components': [
                  {
                    'componentId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                    'position': 0,
                    'name': 'Oats',
                    'brand': null,
                    'amountGrams': 50,
                    'per100Grams': {
                      'kilocalories': 380,
                      'proteinGrams': 13,
                      'carbohydrateGrams': 68,
                      'fatGrams': 7,
                    },
                    'source': {
                      'provider': 'OpenFoodFacts',
                      'barcode': '4001234567890',
                      'retrievedAtUtc': '2026-01-01T10:00:00Z',
                      'basisGrams': 100,
                    },
                  },
                ],
              })!
              as Map<String, dynamic>;
      final mealPayload =
          SyncPayloadCodec.serverPayload(
                _mutation('reusable-meal', LocalMutationOperation.update, meal),
                meal,
                3,
              )!
              as Map<String, dynamic>;
      final component = (mealPayload['components'] as List).single as Map;
      expect(component['componentId'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(component['source']['barcode'], '4001234567890');

      final schedule =
          SyncPayloadCodec.normalizeSnapshot('NutritionTargetSchedule', {
                'nutritionTargetScheduleId': _aggregateId,
                'version': 6,
                'versions': [
                  {
                    'targetVersionId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                    'name': 'Maintenance',
                    'category': 'maintenance',
                    'effectiveFrom': '2026-01-01',
                    'effectiveUntil': null,
                    'inputMode': 'grams',
                    'kilocalories': 2200,
                    'proteinGrams': 150,
                    'carbohydrateGrams': 250,
                    'fatGrams': 70,
                    'proteinPercent': null,
                    'carbohydratePercent': null,
                    'fatPercent': null,
                    'origin': 'manual',
                    'algorithmVersion': null,
                    'reason': null,
                  },
                ],
              })!
              as Map<String, dynamic>;
      final targetPayload =
          SyncPayloadCodec.serverPayload(
                _mutation(
                  'nutrition-target-schedule',
                  LocalMutationOperation.update,
                  schedule,
                ),
                schedule,
                6,
              )!
              as Map<String, dynamic>;
      expect(
        (targetPayload['versions'] as List).single['targetVersionId'],
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      );
    },
  );
}
