import '../../models/local/local_mutation.dart';

const _bodyGoalType = 'body-goal';
const _dailyCheckInType = 'daily-check-in';
const _customExerciseType = 'custom-exercise';
const _workoutTemplateType = 'workout-template';
const _workoutRotationType = 'workout-rotation';
const _nutritionDayType = 'nutrition-day';
const _reusableMealType = 'reusable-meal';
const _nutritionTargetScheduleType = 'nutrition-target-schedule';

/// Pure translation between PWA-shaped local aggregates and the Sync v2
/// backend DTOs. Keep transport orchestration out of this codec.
class SyncPayloadCodec {
  static String? aggregateTypeForResource(String resourceType) =>
      switch (resourceType) {
        'BodyGoal' => _bodyGoalType,
        'DailyCheckIn' => _dailyCheckInType,
        'CustomExercise' => _customExerciseType,
        'WorkoutTemplate' => _workoutTemplateType,
        'WorkoutRotation' => _workoutRotationType,
        'Workout' => 'workout',
        'NutritionDay' => _nutritionDayType,
        'ReusableMeal' => _reusableMealType,
        'NutritionTargetSchedule' => _nutritionTargetScheduleType,
        _ => null,
      };

  static String serverOperation(
    LocalMutation mutation,
    Map<String, dynamic> body,
  ) {
    switch (mutation.aggregateType) {
      case _bodyGoalType:
        return 'activateBodyGoal';
      case _dailyCheckInType:
        return mutation.operation == LocalMutationOperation.create
            ? 'createDailyCheckIn'
            : 'correctDailyCheckIn';
      case _customExerciseType:
        return _customExerciseOperation(mutation, body);
      case _workoutTemplateType:
        return mutation.operation == LocalMutationOperation.update &&
                body['isArchived'] == true
            ? 'archiveWorkoutTemplate'
            : 'saveWorkoutTemplate';
      case _workoutRotationType:
        return 'saveWorkoutRotation';
      case 'workout':
        return switch (mutation.operation) {
          LocalMutationOperation.create => 'startWorkout',
          LocalMutationOperation.complete => 'completeWorkout',
          LocalMutationOperation.discard => 'discardWorkout',
          _ => 'editWorkout',
        };
      case _nutritionDayType:
        return mutation.operation == LocalMutationOperation.delete
            ? 'deleteNutritionDay'
            : 'saveNutritionDay';
      case _reusableMealType:
        return body['status'] == 'Archived'
            ? 'archiveReusableMeal'
            : 'saveReusableMeal';
      case _nutritionTargetScheduleType:
        return 'saveNutritionTargetSchedule';
      default:
        throw ArgumentError.value(mutation.aggregateType, 'aggregateType');
    }
  }

  static String _customExerciseOperation(
    LocalMutation mutation,
    Map<String, dynamic> body,
  ) {
    if (mutation.operation == LocalMutationOperation.create) {
      return 'createCustomExercise';
    }
    return body['isArchived'] == true
        ? 'archiveCustomExercise'
        : 'updateCustomExercise';
  }

  static Object? serverPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    switch (mutation.aggregateType) {
      case _dailyCheckInType:
        return _dailyCheckInPayload(mutation, body, baseVersion);
      case _customExerciseType:
        return _customExercisePayload(mutation, body, baseVersion);
      case _bodyGoalType:
        return _bodyGoalPayload(mutation, body);
      case _workoutTemplateType:
        return _workoutTemplatePayload(mutation, body, baseVersion);
      case _workoutRotationType:
        return _workoutRotationPayload(mutation, body, baseVersion);
      case 'workout':
        return _workoutPayload(mutation, body, baseVersion);
      case _nutritionDayType:
        return _nutritionDayPayload(mutation, body, baseVersion);
      case _reusableMealType:
        return _reusableMealPayload(mutation, body, baseVersion);
      case _nutritionTargetScheduleType:
        return _nutritionTargetSchedulePayload(mutation, body, baseVersion);
      default:
        throw ArgumentError.value(mutation.aggregateType, 'aggregateType');
    }
  }

  static Object? _dailyCheckInPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
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
        ? {'checkInId': id, 'localDate': body['localDate'], 'values': values}
        : {'checkInId': id, 'baseVersion': baseVersion, 'values': values};
  }

  static Object? _customExercisePayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
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
  }

  static Object? _bodyGoalPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
  ) {
    return {
      'goalId': mutation.aggregateId,
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
  }

  static Object? _workoutTemplatePayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
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
  }

  static Object? _workoutRotationPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    return {
      'rotationId': mutation.aggregateId,
      'baseVersion': baseVersion,
      'entries': _mappedList(
        body['entries'],
        (entry) => {'itemId': entry['id'], 'templateId': entry['templateId']},
      ),
    };
  }

  static Object? _workoutPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
    if (mutation.operation == LocalMutationOperation.create) {
      return {'workoutId': id, 'templateId': body['sourceTemplateId']};
    }
    if (mutation.operation == LocalMutationOperation.complete) {
      final rotation = body['rotation'];
      return {
        'workoutId': id,
        'baseVersion': baseVersion,
        'rotationId': rotation is Map<String, dynamic> ? rotation['id'] : null,
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
  }

  static Object? _nutritionDayPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
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
  }

  static Object? _reusableMealPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
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
  }

  static Object? _nutritionTargetSchedulePayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    return {
      'nutritionTargetScheduleId': mutation.aggregateId,
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
    _normalizeNestedSnapshotIds(resourceType, snapshot);
    return snapshot;
  }

  static void _normalizeNestedSnapshotIds(
    String resourceType,
    Map<String, dynamic> snapshot,
  ) {
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
