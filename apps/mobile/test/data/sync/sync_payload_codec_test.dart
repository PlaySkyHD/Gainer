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
  test('maps every backend resource name to its local aggregate type', () {
    expect(
      [
        'BodyGoal',
        'DailyCheckIn',
        'CustomExercise',
        'ExerciseCategory',
        'TrainingPlan',
        'TrainingSchedule',
        'Workout',
        'NutritionDay',
        'ReusableMeal',
        'NutritionTargetSchedule',
      ].map(SyncPayloadCodec.aggregateTypeForResource).toList(),
      [
        'body-goal',
        'daily-check-in',
        'custom-exercise',
        'exercise-category',
        'training-plan',
        'training-schedule',
        'workout',
        'nutrition-day',
        'reusable-meal',
        'nutrition-target-schedule',
      ],
    );
    expect(
      SyncPayloadCodec.aggregateTypeForResource('WorkoutRotation'),
      isNull,
    );
    expect(
      SyncPayloadCodec.aggregateTypeForResource('WorkoutTemplate'),
      isNull,
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
            'portion': {'pieceGrams': 25, 'pieceCount': 2},
            'totals': {'kilocalories': 190},
            'per100Grams': {
              'kilocalories': 380,
              'proteinGrams': 13,
              'carbohydrateGrams': 68,
              'fatGrams': 7,
              'saltGrams': 0.9,
              'fiberGrams': 10,
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
      expect(entry['saltGramsPer100Grams'], 0.9);
      expect(entry['fiberGramsPer100Grams'], 10);
      expect(entry['pieceGrams'], 25);
      expect(entry['pieceCount'], 2);
      expect(entry['source'], (source['entries'] as List).single['source']);

      // Ohne Salz wird das Feld weggelassen, damit ältere Server nichts sehen.
      final withoutSalt = Map<String, dynamic>.from(working);
      final plainEntry = Map<String, dynamic>.from(
        (working['entries'] as List).single as Map,
      );
      plainEntry['per100Grams'] =
          Map<String, dynamic>.from(plainEntry['per100Grams'] as Map)
            ..remove('saltGrams')
            ..remove('fiberGrams');
      withoutSalt['entries'] = [plainEntry];
      final plainPayload =
          SyncPayloadCodec.serverPayload(
                _mutation(
                  'nutrition-day',
                  LocalMutationOperation.update,
                  withoutSalt,
                ),
                withoutSalt,
                2,
              )!
              as Map<String, dynamic>;
      expect(
        ((plainPayload['entries'] as List).single as Map).containsKey(
          'saltGramsPer100Grams',
        ),
        isFalse,
      );
      expect(
        ((plainPayload['entries'] as List).single as Map).containsKey(
          'fiberGramsPer100Grams',
        ),
        isFalse,
      );
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
                      'fiberGrams': 10,
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
      expect(component['fiberGramsPer100Grams'], 10);

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
                    'fiberGrams': 25,
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
      expect((targetPayload['versions'] as List).single['fiberGrams'], 25);
    },
  );
}
