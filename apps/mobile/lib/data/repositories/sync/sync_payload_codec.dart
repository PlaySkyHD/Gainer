import '../../models/local/local_mutation.dart';

/// Pure translation between PWA-shaped local aggregates and the Sync v2
/// backend DTOs. Keep transport orchestration out of this codec.
class SyncPayloadCodec {
  static String? aggregateTypeForResource(String resourceType) =>
      switch (resourceType) {
        'BodyGoal' => 'body-goal',
        'DailyCheckIn' => 'daily-check-in',
        'CustomExercise' => 'custom-exercise',
        'WorkoutTemplate' => 'workout-template',
        'WorkoutRotation' => 'workout-rotation',
        'Workout' => 'workout',
        'NutritionDay' => 'nutrition-day',
        'ReusableMeal' => 'reusable-meal',
        'NutritionTargetSchedule' => 'nutrition-target-schedule',
        _ => null,
      };

  static String serverOperation(
    LocalMutation mutation,
    Map<String, dynamic> body,
  ) {
    switch (mutation.aggregateType) {
      case 'body-goal':
        return 'activateBodyGoal';
      case 'daily-check-in':
        return mutation.operation == LocalMutationOperation.create
            ? 'createDailyCheckIn'
            : 'correctDailyCheckIn';
      case 'custom-exercise':
        if (mutation.operation == LocalMutationOperation.create) {
          return 'createCustomExercise';
        }
        return body['isArchived'] == true
            ? 'archiveCustomExercise'
            : 'updateCustomExercise';
      case 'workout-template':
        return mutation.operation == LocalMutationOperation.update &&
                body['isArchived'] == true
            ? 'archiveWorkoutTemplate'
            : 'saveWorkoutTemplate';
      case 'workout-rotation':
        return 'saveWorkoutRotation';
      case 'workout':
        return switch (mutation.operation) {
          LocalMutationOperation.create => 'startWorkout',
          LocalMutationOperation.complete => 'completeWorkout',
          LocalMutationOperation.discard => 'discardWorkout',
          _ => 'editWorkout',
        };
      case 'nutrition-day':
        return mutation.operation == LocalMutationOperation.delete
            ? 'deleteNutritionDay'
            : 'saveNutritionDay';
      case 'reusable-meal':
        return body['status'] == 'Archived'
            ? 'archiveReusableMeal'
            : 'saveReusableMeal';
      case 'nutrition-target-schedule':
        return 'saveNutritionTargetSchedule';
      default:
        throw ArgumentError.value(mutation.aggregateType, 'aggregateType');
    }
  }

  static Object? serverPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
    switch (mutation.aggregateType) {
      case 'daily-check-in':
        final values = {
          for (final key in [
            'weightKg',
            'caloriesKcal',
            'proteinGrams',
            'carbohydrateGrams',
            'fatGrams',
            'steps',
            'sleepMinutes',
          ])
            if (body.containsKey(key)) key: body[key],
        };
        return mutation.operation == LocalMutationOperation.create
            ? {
                'checkInId': id,
                'localDate': body['localDate'],
                'values': values,
              }
            : {'checkInId': id, 'baseVersion': baseVersion, 'values': values};
      case 'custom-exercise':
        if (mutation.operation != LocalMutationOperation.create &&
            body['isArchived'] == true) {
          return {'exerciseId': id, 'baseVersion': baseVersion};
        }
        final values = {
          for (final key in [
            'name',
            'description',
            'targetMuscle',
            'muscleGroup',
            'equipment',
          ])
            if (body.containsKey(key)) key: body[key],
        };
        return mutation.operation == LocalMutationOperation.create
            ? {'exerciseId': id, 'values': values}
            : {'exerciseId': id, 'baseVersion': baseVersion, 'values': values};
      case 'body-goal':
        return {
          'goalId': id,
          for (final key in [
            'kind',
            'startWeightKg',
            'targetWeightKg',
            'startDate',
            'targetDate',
          ])
            if (body.containsKey(key)) key: body[key],
          'expectedActiveGoalId': body['expectedActiveGoalId'],
          'expectedActiveGoalVersion': body['expectedActiveGoalVersion'],
        };
      case 'workout-template':
        if (mutation.operation == LocalMutationOperation.update &&
            body['isArchived'] == true) {
          return {'templateId': id, 'baseVersion': baseVersion};
        }
        return {
          'templateId': id,
          'baseVersion': baseVersion,
          'name': body['name'],
          'items': _mappedList(
            body['items'],
            (item) => {
              'itemId': item['id'],
              'exerciseId': item['exerciseId'],
              'plannedSets': item['plannedSets'],
              'minimumRepetitions': item['minimumRepetitions'],
              'maximumRepetitions': item['maximumRepetitions'],
              'targetRir': item['targetRir'],
              'restSeconds': item['restSeconds'],
              'notes': item['notes'],
            },
          ),
        };
      case 'workout-rotation':
        return {
          'rotationId': id,
          'baseVersion': baseVersion,
          'entries': _mappedList(
            body['entries'],
            (entry) => {
              'itemId': entry['id'],
              'templateId': entry['templateId'],
            },
          ),
        };
      case 'workout':
        if (mutation.operation == LocalMutationOperation.create) {
          return {'workoutId': id, 'templateId': body['sourceTemplateId']};
        }
        if (mutation.operation == LocalMutationOperation.complete) {
          final rotation = body['rotation'];
          return {
            'workoutId': id,
            'baseVersion': baseVersion,
            'rotationId': rotation is Map<String, dynamic>
                ? rotation['id']
                : null,
            'rotationBaseVersion': rotation is Map<String, dynamic>
                ? rotation['serverVersion']
                : null,
          };
        }
        if (mutation.operation == LocalMutationOperation.discard) {
          return {'workoutId': id, 'baseVersion': baseVersion};
        }
        return {
          'workoutId': id,
          'baseVersion': baseVersion,
          'exercises': _mappedList(
            body['exercises'],
            (exercise) => {
              'workoutExerciseId': exercise['id'],
              'sourceExerciseId': exercise['sourceExerciseId'],
              'exerciseNameSnapshot': exercise['exerciseNameSnapshot'],
              'plannedSets': exercise['plannedSets'],
              'minimumRepetitions': exercise['minimumRepetitions'],
              'maximumRepetitions': exercise['maximumRepetitions'],
              'targetRir': exercise['targetRir'],
              'restSeconds': exercise['restSeconds'],
              'notes': exercise['notes'],
              'sets': _mappedList(
                exercise['sets'],
                (set) => {
                  'setId': set['id'],
                  'weightKg': set['weightKg'],
                  'repetitions': set['repetitions'],
                  'rir': set['rir'],
                  'notes': set['notes'],
                  'isCompleted': set['isCompleted'],
                  'completedAtUtc': set['completedAtUtc'],
                },
              ),
            },
          ),
        };
      case 'nutrition-day':
        if (mutation.operation == LocalMutationOperation.delete) {
          return {'nutritionDayId': id, 'baseVersion': baseVersion};
        }
        return {
          'nutritionDayId': id,
          'localDate': body['localDate'],
          'baseVersion': baseVersion,
          'entries': _mappedList(body['entries'], (entry) {
            final per100 = _mapValue(entry['per100Grams']);
            return {
              'entryId': entry['entryId'],
              'meal': entry['meal'],
              'position': entry['position'],
              'productName': entry['productName'],
              'brand': entry['brand'],
              'amountGrams': entry['amountGrams'],
              'kilocaloriesPer100Grams': per100['kilocalories'],
              'proteinGramsPer100Grams': per100['proteinGrams'],
              'carbohydrateGramsPer100Grams': per100['carbohydrateGrams'],
              'fatGramsPer100Grams': per100['fatGrams'],
              'source': entry['source'],
            };
          }),
        };
      case 'reusable-meal':
        if (body['status'] == 'Archived') {
          return {'reusableMealId': id, 'baseVersion': baseVersion};
        }
        return {
          'reusableMealId': id,
          'baseVersion': baseVersion,
          'name': body['name'],
          'description': body['description'],
          'standardPortion': body['standardPortion'],
          'components': _mappedList(body['components'], (component) {
            final per100 = _mapValue(component['per100Grams']);
            return {
              'componentId': component['componentId'],
              'position': component['position'],
              'name': component['name'],
              'brand': component['brand'],
              'amountGrams': component['amountGrams'],
              'kilocaloriesPer100Grams': per100['kilocalories'],
              'proteinGramsPer100Grams': per100['proteinGrams'],
              'carbohydrateGramsPer100Grams': per100['carbohydrateGrams'],
              'fatGramsPer100Grams': per100['fatGrams'],
              'source': component['source'],
            };
          }),
        };
      case 'nutrition-target-schedule':
        return {
          'nutritionTargetScheduleId': id,
          'baseVersion': baseVersion,
          'versions': _mappedList(
            body['versions'],
            (version) => {
              'targetVersionId': version['targetVersionId'],
              'name': version['name'],
              'category': version['category'],
              'effectiveFrom': version['effectiveFrom'],
              'effectiveUntil': version['effectiveUntil'],
              'inputMode': version['inputMode'],
              'kilocalories': version['kilocalories'],
              'proteinGrams': version['proteinGrams'],
              'carbohydrateGrams': version['carbohydrateGrams'],
              'fatGrams': version['fatGrams'],
              'proteinPercent': version['proteinPercent'],
              'carbohydratePercent': version['carbohydratePercent'],
              'fatPercent': version['fatPercent'],
              'origin': version['origin'],
              'algorithmVersion': version['algorithmVersion'],
              'reason': version['reason'],
            },
          ),
        };
      default:
        throw ArgumentError.value(mutation.aggregateType, 'aggregateType');
    }
  }

  static Map<String, dynamic> _mapValue(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected a sync payload object.');
    }
    return value;
  }

  static List<Map<String, dynamic>> _mappedList(
    Object? source,
    Map<String, Object?> Function(Map<String, dynamic>) map,
  ) {
    if (source is! List ||
        source.any((entry) => entry is! Map<String, dynamic>)) {
      throw const FormatException('Expected a list of sync objects.');
    }
    return source.cast<Map<String, dynamic>>().map(map).toList(growable: false);
  }

  static Object? normalizeSnapshot(String resourceType, Object? snapshotValue) {
    if (snapshotValue is! Map<String, dynamic>) return snapshotValue;
    final snapshot = Map<String, dynamic>.from(snapshotValue);
    if (resourceType == 'DailyCheckIn' || resourceType == 'CustomExercise') {
      final values = snapshot['values'];
      if (values is Map<String, dynamic>) {
        return {
          ...values,
          for (final key in [
            'localDate',
            'isArchived',
            'createdAtUtc',
            'updatedAtUtc',
          ])
            if (snapshot.containsKey(key)) key: snapshot[key],
        };
      }
    }
    for (final key in [
      'version',
      'goalId',
      'templateId',
      'rotationId',
      'workoutId',
      'nutritionDayId',
      'reusableMealId',
      'nutritionTargetScheduleId',
    ]) {
      snapshot.remove(key);
    }
    if (resourceType == 'WorkoutTemplate') {
      snapshot['items'] = _normalizeNestedIds(snapshot['items'], 'itemId');
    } else if (resourceType == 'WorkoutRotation') {
      snapshot['entries'] = _normalizeNestedIds(snapshot['entries'], 'itemId');
    } else if (resourceType == 'Workout') {
      snapshot['exercises'] = _normalizeNestedIds(
        snapshot['exercises'],
        'workoutExerciseId',
        nestedKey: 'sets',
        nestedIdKey: 'setId',
      );
    }
    return snapshot;
  }

  static List<Map<String, dynamic>> _normalizeNestedIds(
    Object? value,
    String idKey, {
    String? nestedKey,
    String? nestedIdKey,
  }) {
    if (value is! List ||
        value.any((entry) => entry is! Map<String, dynamic>)) {
      throw const FormatException('Expected a list of sync snapshot objects.');
    }
    return value
        .cast<Map<String, dynamic>>()
        .map((source) {
          final item = Map<String, dynamic>.from(source);
          if (item.containsKey(idKey)) {
            item['id'] = item.remove(idKey);
          }
          if (nestedKey != null && item.containsKey(nestedKey)) {
            item[nestedKey] = _normalizeNestedIds(
              item[nestedKey],
              nestedIdKey!,
            );
          }
          return item;
        })
        .toList(growable: false);
  }
}
