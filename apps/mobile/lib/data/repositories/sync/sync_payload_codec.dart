import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/training_plan_model.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../models/local/local_mutation.dart';

const _bodyGoalType = 'body-goal';
const _dailyCheckInType = 'daily-check-in';
const _customExerciseType = 'custom-exercise';
const _exerciseCategoryType = 'exercise-category';
const _trainingPlanType = 'training-plan';
const _workoutType = 'workout';
const _trainingScheduleType = 'training-schedule';
const _nutritionDayType = 'nutrition-day';
const _reusableMealType = 'reusable-meal';
const _nutritionTargetScheduleType = 'nutrition-target-schedule';
const _cardioSessionType = 'cardio-session';

/// Pure translation between PWA-shaped local aggregates and the Sync v2
/// backend DTOs. Keep transport orchestration out of this codec.
class SyncPayloadCodec {
  static String? aggregateTypeForResource(String resourceType) =>
      switch (resourceType) {
        'BodyGoal' => _bodyGoalType,
        'DailyCheckIn' => _dailyCheckInType,
        'CustomExercise' => _customExerciseType,
        'ExerciseCategory' => _exerciseCategoryType,
        'TrainingPlan' => _trainingPlanType,
        'TrainingSchedule' => _trainingScheduleType,
        'Workout' => _workoutType,
        'NutritionDay' => _nutritionDayType,
        'ReusableMeal' => _reusableMealType,
        'NutritionTargetSchedule' => _nutritionTargetScheduleType,
        'CardioSession' => _cardioSessionType,
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
        return _dailyCheckInOperation(mutation);
      case _customExerciseType:
        return _customExerciseOperation(mutation, body);
      case _exerciseCategoryType:
        return _exerciseCategoryOperation(mutation, body);
      case _trainingPlanType:
        return _trainingPlanOperation(mutation, body);
      case _trainingScheduleType:
        return mutation.operation == LocalMutationOperation.delete
            ? 'deleteTrainingSchedule'
            : 'saveTrainingSchedule';
      case _workoutType:
        return _workoutOperation(mutation);
      case _nutritionDayType:
        return _nutritionDayOperation(mutation);
      case _reusableMealType:
        return _reusableMealOperation(body);
      case _nutritionTargetScheduleType:
        return 'saveNutritionTargetSchedule';
      case _cardioSessionType:
        return _cardioSessionOperation(mutation);
      default:
        throw ArgumentError.value(mutation.aggregateType, 'aggregateType');
    }
  }

  static String _dailyCheckInOperation(LocalMutation mutation) =>
      mutation.operation == LocalMutationOperation.create
      ? 'createDailyCheckIn'
      : 'correctDailyCheckIn';

  static String _exerciseCategoryOperation(
    LocalMutation mutation,
    Map<String, dynamic> body,
  ) {
    return switch (mutation.operation) {
      LocalMutationOperation.create => 'createExerciseCategory',
      _ =>
        body['isArchived'] == true
            ? 'archiveExerciseCategory'
            : 'updateExerciseCategory',
    };
  }

  static String _trainingPlanOperation(
    LocalMutation mutation,
    Map<String, dynamic> body,
  ) {
    return switch (mutation.operation) {
      LocalMutationOperation.create => 'createTrainingPlan',
      LocalMutationOperation.reorder => 'reorderTrainingPlans',
      _ =>
        body['isArchived'] == true
            ? 'archiveTrainingPlan'
            : 'updateTrainingPlan',
    };
  }

  static String _workoutOperation(LocalMutation mutation) {
    return switch (mutation.operation) {
      LocalMutationOperation.create => 'createWorkout',
      LocalMutationOperation.delete => 'deleteWorkout',
      _ => 'saveWorkout',
    };
  }

  static String _nutritionDayOperation(LocalMutation mutation) =>
      mutation.operation == LocalMutationOperation.delete
      ? 'deleteNutritionDay'
      : 'saveNutritionDay';

  static String _cardioSessionOperation(LocalMutation mutation) =>
      mutation.operation == LocalMutationOperation.delete
      ? 'deleteCardioSession'
      : 'saveCardioSession';

  static String _reusableMealOperation(Map<String, dynamic> body) =>
      body['status'] == 'Archived' ? 'archiveReusableMeal' : 'saveReusableMeal';

  static String _customExerciseOperation(
    LocalMutation mutation,
    Map<String, dynamic> body,
  ) {
    return switch (mutation.operation) {
      LocalMutationOperation.create => 'createCustomExercise',
      LocalMutationOperation.merge => 'mergeExercises',
      _ =>
        body['isArchived'] == true
            ? 'archiveCustomExercise'
            : 'updateCustomExercise',
    };
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
      case _exerciseCategoryType:
        return _exerciseCategoryPayload(mutation, body, baseVersion);
      case _trainingPlanType:
        return _trainingPlanPayload(mutation, body, baseVersion);
      case _trainingScheduleType:
        return _trainingSchedulePayload(mutation, body, baseVersion);
      case _workoutType:
        return _workoutPayload(mutation, body, baseVersion);
      case _nutritionDayType:
        return _nutritionDayPayload(mutation, body, baseVersion);
      case _reusableMealType:
        return _reusableMealPayload(mutation, body, baseVersion);
      case _nutritionTargetScheduleType:
        return _nutritionTargetSchedulePayload(mutation, body, baseVersion);
      case _cardioSessionType:
        return _cardioSessionPayload(mutation, body, baseVersion);
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
      // Neue optionale Werte nur senden, wenn gesetzt (alte Server kennen sie
      // nicht).
      for (final key in ['restingHeartRateBpm', 'restingHrvMs'])
        if (body[key] != null) key: body[key],
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
    if (mutation.operation == LocalMutationOperation.merge) {
      return {
        'sourceExerciseId': id,
        'sourceBaseVersion': baseVersion,
        'targetExerciseId': body['targetExerciseId'],
      };
    }
    if (mutation.operation != LocalMutationOperation.create &&
        body['isArchived'] == true) {
      return {'exerciseId': id, 'baseVersion': baseVersion};
    }
    final values = _compact({
      'name': body['name'],
      'exerciseType': body['exerciseType'],
      'description': body['description'],
      'targetMuscle': body['targetMuscle'],
      'muscleGroup': body['muscleGroup'],
      'equipment': body['equipment'],
      'notes': body['notes'],
      'bodyweightFactor': body['bodyweightFactor'],
      'weightFactor': body['weightFactor'],
      'categoryIds': body['categoryIds'],
      'primaryMuscles': _nonEmptyList(body['primaryMuscles']),
      'secondaryMuscles': _nonEmptyList(body['secondaryMuscles']),
    });
    return mutation.operation == LocalMutationOperation.create
        ? {'exerciseId': id, 'values': values}
        : {'exerciseId': id, 'baseVersion': baseVersion, 'values': values};
  }

  static Object? _exerciseCategoryPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
    if (mutation.operation == LocalMutationOperation.create) {
      return {'categoryId': id, 'name': body['name']};
    }
    if (body['isArchived'] == true) {
      return {'categoryId': id, 'baseVersion': baseVersion};
    }
    return {'categoryId': id, 'baseVersion': baseVersion, 'name': body['name']};
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

  static Object? _trainingPlanPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
    if (mutation.operation == LocalMutationOperation.reorder) {
      return {
        'plans': _mappedList(
          body['plans'],
          (plan) => {
            'planId': plan['planId'],
            'baseVersion': plan['baseVersion'],
          },
        ),
      };
    }
    if (mutation.operation == LocalMutationOperation.update &&
        body['isArchived'] == true) {
      return {'planId': id, 'baseVersion': baseVersion};
    }
    final plan = _trainingPlanValue(body);
    return mutation.operation == LocalMutationOperation.create
        ? {'plan': plan}
        : {'baseVersion': baseVersion, 'plan': plan};
  }

  static Map<String, Object?> _trainingPlanValue(Map<String, dynamic> body) =>
      _compact({
        'planId': body['planId'],
        'name': body['name'],
        'notes': body['notes'],
        'previousValueSource': body['previousValueSource'],
        'entries': _mappedList(
          body['entries'],
          (entry) => _compact({
            'entryId': entry['entryId'],
            'exerciseId': entry['exerciseId'],
            'warmupSets': entry['warmupSets'],
            'workingSets': entry['workingSets'],
            'notes': entry['notes'],
            'supersetId': entry['supersetId'],
          }),
        ),
      });

  /// Vollständiger Stand des Rhythmus (D3a). Kinder werden bei jeder
  /// Mutation ersetzt; Datumsfelder sind lokale Tage als „YYYY-MM-DD“.
  static Object? _trainingSchedulePayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
    if (mutation.operation == LocalMutationOperation.delete) {
      return {'scheduleId': id, 'baseVersion': baseVersion};
    }
    final mode = body['mode'];
    return {
      'scheduleId': id,
      'baseVersion': baseVersion,
      'mode': mode,
      'anchorDate': mode == 'cycle' ? body['anchorDate'] : null,
      'validFrom': body['validFrom'],
      'slots': _mappedList(body['slots'], (slot) => {'planId': slot['planId']}),
      'shifts': _mappedList(
        body['shifts'] ?? const <Object?>[],
        (shift) => {'fromDate': shift['fromDate'], 'days': shift['days']},
      ),
      'exceptions': _mappedList(
        body['exceptions'] ?? const <Object?>[],
        (exception) => {
          'date': exception['date'],
          'planId': exception['planId'],
          'movedToDate': exception['movedToDate'],
        },
      ),
    };
  }

  static Object? _workoutPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    final id = mutation.aggregateId;
    if (mutation.operation == LocalMutationOperation.delete) {
      return {'workoutId': id, 'baseVersion': baseVersion};
    }
    final workout = _workoutValue(body);
    return mutation.operation == LocalMutationOperation.create
        ? {'workout': workout}
        : {'baseVersion': baseVersion, 'workout': workout};
  }

  static Map<String, Object?> _workoutValue(Map<String, dynamic> body) =>
      _compact({
        'workoutId': body['workoutId'],
        'title': body['title'],
        'notes': body['notes'],
        'startedAtUtc': body['startedAtUtc'],
        'endedAtUtc': body['endedAtUtc'],
        'previousValueSource': body['previousValueSource'],
        'sourcePlanId': body['sourcePlanId'],
        'sourceWorkoutId': body['sourceWorkoutId'],
        'exercises': _mappedList(
          body['exercises'],
          (exercise) => _compact({
            'workoutExerciseId': exercise['workoutExerciseId'],
            'sourceExerciseId': exercise['sourceExerciseId'],
            'exerciseNameSnapshot': exercise['exerciseNameSnapshot'],
            'exerciseTypeSnapshot': exercise['exerciseTypeSnapshot'],
            'notes': exercise['notes'],
            'supersetId': exercise['supersetId'],
            'sets': _mappedList(
              exercise['sets'],
              (set) => _compact({
                'setId': set['setId'],
                'setType': set['setType'],
                'weightKg': set['weightKg'],
                'repetitions': set['repetitions'],
                'rir': set['rir'],
                'notes': set['notes'],
              }),
            ),
          }),
        ),
      });

  /// IDs lokaler Ressourcen, auf die der Body einer Mutation verweist: Übungen
  /// in Trainings und Plänen, Kategorien in Übungen, Quellplan und
  /// Quelltraining, Pläne im Rhythmus und in der Umsortierung, Ziel einer
  /// Zusammenführung. Die Ressource selbst zählt nicht.
  static Set<String> referencedAggregateIds(LocalMutation mutation) {
    final body = mutation.body;
    if (body is! Map) return const {};
    final ids = <String>{};
    void add(Object? value) {
      if (value is String && value.isNotEmpty) ids.add(value);
    }

    void addAll(Object? list, Object? Function(Map<dynamic, dynamic>) pick) {
      if (list is! List) return;
      for (final entry in list) {
        if (entry is Map) add(pick(entry));
      }
    }

    switch (mutation.aggregateType) {
      case _workoutType:
        add(body['sourcePlanId']);
        add(body['sourceWorkoutId']);
        addAll(body['exercises'], (e) => e['sourceExerciseId']);
      case _trainingPlanType:
        addAll(body['entries'], (e) => e['exerciseId']);
        addAll(body['plans'], (e) => e['planId']);
      case _customExerciseType:
        final categories = body['categoryIds'];
        if (categories is List) categories.forEach(add);
        add(body['targetExerciseId']);
      case _trainingScheduleType:
        addAll(body['slots'], (slot) => slot['planId']);
        addAll(body['exceptions'], (exception) => exception['planId']);
    }
    ids.remove(mutation.aggregateId);
    return ids;
  }

  /// Optionale Felder ohne Wert fehlen in der Payload, wie der Vertrag sie
  /// vorsieht; ein Update ersetzt die Werte vollständig.
  static Object? _nonEmptyList(Object? value) =>
      value is List && value.isEmpty ? null : value;

  static Map<String, Object?> _compact(Map<String, Object?> source) => {
    for (final entry in source.entries)
      if (entry.value != null) entry.key: entry.value,
  };

  static Object? _cardioSessionPayload(
    LocalMutation mutation,
    Map<String, dynamic> body,
    int baseVersion,
  ) {
    if (mutation.operation == LocalMutationOperation.delete) {
      return {'sessionId': mutation.aggregateId, 'baseVersion': baseVersion};
    }
    return {
      'baseVersion': baseVersion,
      'session': _compact({
        'sessionId': body['sessionId'],
        'activityType': body['activityType'],
        'startedAtUtc': body['startedAtUtc'],
        'endedAtUtc': body['endedAtUtc'],
        'targetZone': body['targetZone'],
        'sampleIntervalSeconds': body['sampleIntervalSeconds'],
        'heartRateBpm': body['heartRateBpm'],
        'rrIntervalsMs': body['rrIntervalsMs'],
        'sensorName': body['sensorName'],
        'distanceKm': body['distanceKm'],
        'averagePowerWatts': body['averagePowerWatts'],
        'energyKcal': body['energyKcal'],
        'notes': body['notes'],
        'recoveryStartBpm': body['recoveryStartBpm'],
        'recoveryEndBpm': body['recoveryEndBpm'],
        'templateName': body['templateName'],
        'phases': body['phases'],
      }),
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
          // Nur senden, wenn gesetzt; ältere Server kennen Salz nicht.
          if (per100['saltGrams'] != null)
            'saltGramsPer100Grams': per100['saltGrams'],
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
          if (per100['saltGrams'] != null)
            'saltGramsPer100Grams': per100['saltGrams'],
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
          if (version['saltGrams'] != null) 'saltGrams': version['saltGrams'],
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

  /// Prüft einen normalisierten Trainings-Snapshot gegen das lokale Modell.
  /// Ein unlesbarer Snapshot (z. B. unbekannter Übungstyp) bricht den Pull ab,
  /// damit der Cursor nicht über ihn hinweg vorrückt.
  static void verifyTrainingSnapshot(String resourceType, Object? snapshot) {
    switch (resourceType) {
      case 'Workout':
        Workout.fromJson(_mapValue(snapshot));
      case 'TrainingPlan':
        TrainingPlanModel.fromJson(_mapValue(snapshot));
      case 'TrainingSchedule':
        TrainingSchedule.fromJson(_mapValue(snapshot));
      case 'CustomExercise':
        CatalogExercise.fromJson(_mapValue(snapshot));
      case 'ExerciseCategory':
        CatalogCategory.fromJson(_mapValue(snapshot));
    }
  }

  /// Snapshots der Trainingstypen behalten ihre Modell-IDs, weil die lokalen
  /// Modelle sie unverändert lesen. Nur Server-Metadaten wie `version` fallen weg.
  static Object? normalizeSnapshot(String resourceType, Object? snapshotValue) {
    if (snapshotValue is! Map<String, dynamic>) return snapshotValue;
    final snapshot = Map<String, dynamic>.from(snapshotValue);
    if (resourceType == 'ExerciseCategory') {
      return _normalizedCategorySnapshot(snapshot);
    }
    if (resourceType == 'DailyCheckIn' || resourceType == 'CustomExercise') {
      final values = snapshot['values'];
      if (values is Map<String, dynamic>) {
        return _normalizedValuesSnapshot(resourceType, snapshot, values);
      }
    }
    for (final key in [
      'version',
      'goalId',
      'nutritionDayId',
      'reusableMealId',
      'nutritionTargetScheduleId',
    ]) {
      snapshot.remove(key);
    }
    return snapshot;
  }

  static Map<String, Object?> _normalizedCategorySnapshot(
    Map<String, dynamic> snapshot,
  ) => {
    'id': snapshot['categoryId'],
    'name': snapshot['name'],
    'isBase': false,
    'isArchived': snapshot['isArchived'] ?? false,
    'createdAtUtc': snapshot['createdAtUtc'],
    'updatedAtUtc': snapshot['updatedAtUtc'],
  };

  static Map<String, Object?> _normalizedValuesSnapshot(
    String resourceType,
    Map<String, dynamic> snapshot,
    Map<String, dynamic> values,
  ) => {
    ...values,
    if (resourceType == 'CustomExercise') ...{
      'id': snapshot['exerciseId'],
      'isBase': false,
    },
    for (final key in [
      'localDate',
      'isArchived',
      'createdAtUtc',
      'updatedAtUtc',
    ])
      if (snapshot.containsKey(key)) key: snapshot[key],
  };
}
