import 'dart:convert';
import 'dart:math';

import '../../../domain/models/training/training.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../sync/local_sync_store.dart';

typedef TrainingIdFactory = String Function();

const _customExerciseType = 'custom-exercise';
const _workoutTemplateType = 'workout-template';
const _workoutRotationType = 'workout-rotation';

abstract interface class ExerciseCatalogProvider {
  Future<List<ExerciseCatalogEntry>> loadExercises();
}

abstract interface class RestTimerNotificationPort {
  Future<void> schedule({
    required String workoutId,
    required DateTime targetUtc,
  });
  Future<void> cancel({required String workoutId});
}

class TrainingPlanningSnapshot {
  const TrainingPlanningSnapshot({
    required this.exercises,
    required this.customExercises,
    required this.templates,
    required this.rotation,
    required this.nextTemplateId,
  });

  final List<ExerciseCatalogEntry> exercises;
  final List<({String id, ExerciseValues value, bool isArchived})>
  customExercises;
  final List<({String id, TrainingTemplate value})> templates;
  final ({String id, TrainingRotation value})? rotation;
  final String? nextTemplateId;
}

class TrainingHistoryEntry {
  const TrainingHistoryEntry({required this.id, required this.value});
  final String id;
  final WorkoutRecord value;
}

class PreviousPerformance {
  const PreviousPerformance({
    required this.workoutId,
    required this.completedAtUtc,
    required this.sets,
  });
  final String workoutId;
  final String completedAtUtc;
  final List<WorkoutSetRecord> sets;
}

/// Training planning and execution over the account's persistent local store.
class TrainingRepository {
  TrainingRepository({
    required this.store,
    required this.catalog,
    this.notifications,
    TrainingIdFactory? ids,
    DateTime Function()? clock,
    this.onNotificationUnavailable,
    this.transactionFaultForTesting,
  }) : ids = ids ?? _newUuidV4,
       clock = clock ?? DateTime.now;

  final LocalSyncStore store;
  final ExerciseCatalogProvider catalog;
  final RestTimerNotificationPort? notifications;
  final TrainingIdFactory ids;
  final DateTime Function() clock;
  final void Function()? transactionFaultForTesting;
  final void Function()? onNotificationUnavailable;

  Future<TrainingPlanningSnapshot> readPlanning() async {
    final available = await catalog.loadExercises();
    final customs = await store.readAggregates(_customExerciseType);
    final templates = await store.readAggregates(_workoutTemplateType);
    final rotations = await store.readAggregates(_workoutRotationType);
    final customValues = [
      for (final row in customs)
        (
          id: row.aggregateId,
          value: ExerciseValues(
            name: _str(_map(row.workingCopy), 'name'),
            description: _stringOrNull(_map(row.workingCopy)['description']),
            targetMuscle: _stringOrNull(_map(row.workingCopy)['targetMuscle']),
            muscleGroup: _stringOrNull(_map(row.workingCopy)['muscleGroup']),
            equipment: _stringOrNull(_map(row.workingCopy)['equipment']),
          ),
          isArchived: _map(row.workingCopy)['isArchived'] == true,
        ),
    ];
    final templateValues = [
      for (final row in templates)
        (
          id: row.aggregateId,
          value: TrainingTemplate.fromJson(_map(row.workingCopy)),
        ),
    ];
    final rotation = rotations.isEmpty
        ? null
        : (
            id: rotations.first.aggregateId,
            value: TrainingRotation.fromJson(_map(rotations.first.workingCopy)),
          );
    final active = templateValues
        .where((item) => !item.value.isArchived)
        .toList();
    final next = _nextTemplate(rotation, active.map((item) => item.id).toSet());
    return TrainingPlanningSnapshot(
      exercises: List.unmodifiable(available),
      customExercises: List.unmodifiable(customValues),
      templates: List.unmodifiable(templateValues),
      rotation: rotation,
      nextTemplateId: next,
    );
  }

  Future<String> createCustomExercise(ExerciseValues input) async {
    final normalized = _normalizeExercise(input);
    final id = ids();
    final now = clock().toUtc().toIso8601String();
    final value = {
      ...normalized.toJson(),
      'isArchived': false,
      'createdAtUtc': now,
      'updatedAtUtc': now,
    };
    await _commit(
      type: _customExerciseType,
      id: id,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: value,
      envelope: localEnvelope(aggregateId: id, workingCopy: value),
    );
    return id;
  }

  Future<void> updateCustomExercise(String id, ExerciseValues input) async {
    final old = await _requireAggregate(_customExerciseType, id);
    final prior = _map(old.workingCopy);
    if (prior['isArchived'] == true) {
      throw StateError('Archived exercises are immutable.');
    }
    final value = {
      ..._normalizeExercise(input).toJson(),
      'isArchived': false,
      'createdAtUtc': prior['createdAtUtc'],
      'updatedAtUtc': clock().toUtc().toIso8601String(),
    };
    await _commit(
      type: _customExerciseType,
      id: id,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: value,
      envelope: _pending(old, value),
    );
  }

  Future<void> archiveCustomExercise(String id) async {
    final old = await _requireAggregate(_customExerciseType, id);
    final value = _map(old.workingCopy);
    if (value['isArchived'] == true) {
      throw StateError('The exercise is already archived.');
    }
    final changed = {
      ...value,
      'isArchived': true,
      'updatedAtUtc': clock().toUtc().toIso8601String(),
    };
    await _commit(
      type: _customExerciseType,
      id: id,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: changed,
      envelope: _pending(old, changed),
    );
  }

  Map<String, String> _templateInputErrors(
    String trimmedName,
    List<TrainingTemplateItem> items,
  ) {
    final errors = <String, String>{};
    if (trimmedName.isEmpty || trimmedName.length > 120) {
      errors['name'] = 'Name erforderlich (maximal 120 Zeichen).';
    }
    if (items.isEmpty) {
      errors['items'] = 'Mindestens eine Übung ist erforderlich.';
    }
    if (items.map((item) => item.id).toSet().length != items.length) {
      errors['items'] = 'Eintrags-IDs müssen eindeutig sein.';
    }
    for (var i = 0; i < items.length; i++) {
      try {
        validateTemplateItem(items[i]);
      } on TrainingValidationException catch (error) {
        errors.addAll({
          for (final entry in error.fields.entries)
            'items.$i.${entry.key}': entry.value,
        });
      }
    }
    return errors;
  }

  Future<String> saveTemplate({
    String? id,
    required String name,
    required List<TrainingTemplateItem> items,
  }) async {
    final trimmedName = name.trim();
    final errors = _templateInputErrors(trimmedName, items);
    final plan = await readPlanning();
    final availableIds = {
      ...plan.exercises.map((item) => item.id),
      ...plan.customExercises
          .where((item) => !item.isArchived)
          .map((item) => item.id),
    };
    for (var i = 0; i < items.length; i++) {
      if (!availableIds.contains(items[i].exerciseId)) {
        errors['items.$i.exerciseId'] = 'Die Übung ist nicht verfügbar.';
      }
    }
    if (errors.isNotEmpty) {
      throw TrainingValidationException(errors);
    }
    final existing = id == null
        ? null
        : await _requireAggregate(_workoutTemplateType, id);
    if (existing != null && _map(existing.workingCopy)['isArchived'] == true) {
      throw StateError('Archived templates are immutable.');
    }
    final aggregateId = id ?? ids();
    final now = clock().toUtc().toIso8601String();
    final old = existing == null ? null : _map(existing.workingCopy);
    final value = TrainingTemplate(
      name: trimmedName,
      items: List.unmodifiable(items),
      isArchived: false,
      createdAtUtc: old?['createdAtUtc'] as String? ?? now,
      updatedAtUtc: now,
    ).toJson();
    await _commit(
      type: _workoutTemplateType,
      id: aggregateId,
      operation: existing == null
          ? LocalMutationOperation.create
          : LocalMutationOperation.update,
      baseVersion: existing?.serverVersion,
      body: value,
      envelope: existing == null
          ? localEnvelope(aggregateId: aggregateId, workingCopy: value)
          : _pending(existing, value),
    );
    return aggregateId;
  }

  Future<void> archiveTemplate(String id) async {
    final old = await _requireAggregate(_workoutTemplateType, id);
    final value = _map(old.workingCopy);
    if (value['isArchived'] == true) {
      throw StateError('The template is already archived.');
    }
    final changed = {
      ...value,
      'isArchived': true,
      'updatedAtUtc': clock().toUtc().toIso8601String(),
    };
    await _commit(
      type: _workoutTemplateType,
      id: id,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: changed,
      envelope: _pending(old, changed),
    );
  }

  Future<String> saveRotation(List<String> templateIds) async {
    if (templateIds.toSet().length != templateIds.length) {
      throw const TrainingValidationException({
        'rotation': 'Jedes Template darf nur einmal vorkommen.',
      });
    }
    final templates = await store.readAggregates(_workoutTemplateType);
    final indexed = {for (final item in templates) item.aggregateId: item};
    for (final templateId in templateIds) {
      final item = indexed[templateId];
      if (item == null || _map(item.workingCopy)['isArchived'] == true) {
        throw const TrainingValidationException({
          'rotation': 'Die Rotation enthält ein nicht verfügbares Template.',
        });
      }
    }
    final rows = await store.readAggregates(_workoutRotationType);
    final old = rows.isEmpty ? null : rows.first;
    final prior = old == null
        ? null
        : TrainingRotation.fromJson(_map(old.workingCopy));
    final id = old?.aggregateId ?? ids();
    final now = clock().toUtc().toIso8601String();
    final rotation = TrainingRotation(
      entries: List.unmodifiable(
        templateIds.map(
          (templateId) =>
              TrainingRotationEntry(id: ids(), templateId: templateId),
        ),
      ),
      lastCompletedTemplateId:
          prior?.lastCompletedTemplateId != null &&
              templateIds.contains(prior!.lastCompletedTemplateId)
          ? prior.lastCompletedTemplateId
          : null,
      updatedAtUtc: now,
    ).toJson();
    await _commit(
      type: _workoutRotationType,
      id: id,
      operation: old == null
          ? LocalMutationOperation.create
          : LocalMutationOperation.update,
      baseVersion: old?.serverVersion,
      body: rotation,
      envelope: old == null
          ? localEnvelope(aggregateId: id, workingCopy: rotation)
          : _pending(old, rotation),
    );
    return id;
  }

  Future<String> startWorkout(String templateId) async {
    final running = await _runningWorkout();
    if (running != null) {
      throw StateError('Es läuft bereits ein Workout.');
    }
    final templateEnvelope = await _requireAggregate(
      _workoutTemplateType,
      templateId,
    );
    final templateMap = _map(templateEnvelope.workingCopy);
    final template = TrainingTemplate.fromJson(templateMap);
    if (template.isArchived || template.items.isEmpty) {
      throw StateError('Das Template ist nicht verfügbar.');
    }
    final planning = await readPlanning();
    final names = <String, String>{
      for (final entry in planning.exercises) entry.id: entry.name,
      for (final entry in planning.customExercises.where(
        (item) => !item.isArchived,
      ))
        entry.id: entry.value.name,
    };
    final now = clock().toUtc().toIso8601String();
    final workoutId = ids();
    final workout = WorkoutRecord(
      sourceTemplateId: templateId,
      templateNameSnapshot: template.name,
      status: 'running',
      startedAtUtc: now,
      completedAtUtc: null,
      discardedAtUtc: null,
      updatedAtUtc: now,
      restTimer: null,
      exercises: List.unmodifiable(
        template.items.asMap().entries.map((entry) {
          final item = entry.value;
          final exerciseName = names[item.exerciseId];
          if (exerciseName == null) {
            throw StateError('A template exercise is no longer available.');
          }
          return WorkoutExerciseRecord(
            id: ids(),
            sourceExerciseId: item.exerciseId,
            exerciseNameSnapshot: exerciseName,
            position: entry.key,
            plannedSets: item.plannedSets,
            minimumRepetitions: item.minimumRepetitions,
            maximumRepetitions: item.maximumRepetitions,
            targetRir: item.targetRir,
            restSeconds: item.restSeconds,
            notes: item.notes,
            sets: List.unmodifiable(
              List.generate(
                item.plannedSets,
                (position) => WorkoutSetRecord(
                  id: ids(),
                  position: position,
                  weightKg: null,
                  repetitions: null,
                  rir: null,
                  notes: null,
                  isCompleted: false,
                  completedAtUtc: null,
                ),
              ),
            ),
          );
        }),
      ),
    );
    final value = workout.toJson();
    await _commit(
      type: 'workout',
      id: workoutId,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: value,
      envelope: localEnvelope(aggregateId: workoutId, workingCopy: value),
    );
    return workoutId;
  }

  Future<List<TrainingHistoryEntry>> readHistory() async {
    final rows = await store.readAggregates('workout');
    final history =
        [
          for (final row in rows)
            if (WorkoutRecord.fromJson(_map(row.workingCopy)).isCompleted)
              TrainingHistoryEntry(
                id: row.aggregateId,
                value: WorkoutRecord.fromJson(_map(row.workingCopy)),
              ),
        ]..sort(
          (left, right) => (right.value.completedAtUtc ?? '').compareTo(
            left.value.completedAtUtc ?? '',
          ),
        );
    return List.unmodifiable(history);
  }

  Future<TrainingHistoryEntry?> readWorkout(String workoutId) async {
    final envelope = await store.readAggregate('workout', workoutId);
    if (envelope == null) return null;
    return TrainingHistoryEntry(
      id: workoutId,
      value: WorkoutRecord.fromJson(_map(envelope.workingCopy)),
    );
  }

  Future<PreviousPerformance?> previousPerformance(
    String exerciseId, {
    DateTime? before,
  }) async {
    final cutoff = (before ?? clock()).toUtc();
    final candidates = <TrainingHistoryEntry>[];
    for (final item in await readHistory()) {
      final completed = item.value.completedAtUtc;
      if (completed == null ||
          !DateTime.parse(completed).toUtc().isBefore(cutoff)) {
        continue;
      }
      if (item.value.exercises.any(
        (exercise) => exercise.sourceExerciseId == exerciseId,
      )) {
        candidates.add(item);
      }
    }
    if (candidates.isEmpty) {
      return null;
    }
    final best = candidates.first;
    final exercise = best.value.exercises.firstWhere(
      (item) => item.sourceExerciseId == exerciseId,
    );
    final sets = exercise.sets
        .where(
          (set) =>
              set.isCompleted &&
              set.weightKg != null &&
              set.repetitions != null,
        )
        .toList(growable: false);
    return PreviousPerformance(
      workoutId: best.id,
      completedAtUtc: best.value.completedAtUtc!,
      sets: sets,
    );
  }

  Future<WorkoutRecord?> readRunningWorkout() async {
    final result = await _runningWorkout();
    return result?.value;
  }

  Future<WorkoutRecord> logSet({
    required String workoutId,
    required String exerciseId,
    required String setId,
    required double? weightKg,
    required int? repetitions,
    required double? rir,
    required String? notes,
    required bool complete,
  }) async {
    validateWorkoutSet(
      weightKg: weightKg,
      repetitions: repetitions,
      rir: rir,
      notes: notes,
      complete: complete,
    );
    final current = await _requireRunningWorkout(workoutId);
    final json = _mutable(_map(current.workingCopy));
    final exercises = _mapList(json['exercises']);
    final exercise = exercises.firstWhere((item) => item['id'] == exerciseId);
    final sets = _mapList(exercise['sets']);
    final set = sets.firstWhere((item) => item['id'] == setId);
    final wasComplete = set['isCompleted'] == true;
    final now = clock().toUtc();
    set.addAll({
      'weightKg': weightKg,
      'repetitions': repetitions,
      'rir': rir,
      'notes': _clean(notes),
      'isCompleted': complete,
      'completedAtUtc': complete
          ? set['completedAtUtc'] ?? now.toIso8601String()
          : null,
    });
    Map<String, Object?>? timer;
    final restSeconds = exercise['restSeconds'];
    if (complete && !wasComplete && restSeconds is int && restSeconds > 0) {
      timer = {
        'sourceSetId': setId,
        'durationSeconds': restSeconds,
        'targetAtUtc': now
            .add(Duration(seconds: restSeconds))
            .toIso8601String(),
      };
    }
    json['restTimer'] = timer ?? json['restTimer'];
    json['updatedAtUtc'] = now.toIso8601String();
    final updated = WorkoutRecord.fromJson(json);
    await _commit(
      type: 'workout',
      id: workoutId,
      operation: LocalMutationOperation.update,
      baseVersion: current.serverVersion,
      body: json,
      envelope: _pending(current, json),
    );
    if (timer case final value?) {
      await _scheduleTimerNotification(
        workoutId: workoutId,
        targetUtc: DateTime.parse(value['targetAtUtc'] as String).toUtc(),
      );
    }
    return updated;
  }

  Future<WorkoutRecord> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) async {
    final plan = await readPlanning();
    final catalogEntry = plan.exercises.where((item) => item.id == exerciseId);
    final customEntry = plan.customExercises.where(
      (item) => item.id == exerciseId && !item.isArchived,
    );
    String? name;
    if (catalogEntry.isNotEmpty) {
      name = catalogEntry.first.name;
    } else if (customEntry.isNotEmpty) {
      name = customEntry.first.value.name;
    }
    if (name == null) {
      throw const TrainingValidationException({
        'exerciseId': 'Die Übung ist nicht verfügbar.',
      });
    }
    return _mutateWorkout(workoutId, (workout) {
      final exercises = _mapList(workout['exercises']);
      exercises.add({
        'id': ids(),
        'sourceExerciseId': exerciseId,
        'exerciseNameSnapshot': name,
        'position': exercises.length,
        'plannedSets': 1,
        'minimumRepetitions': 1,
        'maximumRepetitions': 1,
        'targetRir': null,
        'restSeconds': null,
        'notes': null,
        'sets': [_emptySet(0)],
      });
      workout['exercises'] = exercises;
    });
  }

  Future<WorkoutRecord> removeExerciseFromWorkout({
    required String workoutId,
    required String workoutExerciseId,
  }) => _mutateWorkout(workoutId, (workout) {
    final exercises = _mapList(workout['exercises']);
    final oldLength = exercises.length;
    exercises.removeWhere((item) => item['id'] == workoutExerciseId);
    if (exercises.length == oldLength) {
      throw StateError('Die Workout-Übung ist nicht verfügbar.');
    }
    _reindex(exercises);
    workout['exercises'] = exercises;
  });

  Future<WorkoutRecord> addSet({
    required String workoutId,
    required String workoutExerciseId,
  }) => _mutateWorkout(workoutId, (workout) {
    final exercise = _findExercise(workout, workoutExerciseId);
    final sets = _mapList(exercise['sets']);
    sets.add(_emptySet(sets.length));
    exercise['sets'] = sets;
  });

  Future<WorkoutRecord> removeSet({
    required String workoutId,
    required String workoutExerciseId,
    required String setId,
  }) => _mutateWorkout(workoutId, (workout) {
    final exercise = _findExercise(workout, workoutExerciseId);
    final sets = _mapList(exercise['sets']);
    final oldLength = sets.length;
    sets.removeWhere((item) => item['id'] == setId);
    if (sets.length == oldLength) {
      throw StateError('Der Satz ist nicht verfügbar.');
    }
    _reindex(sets);
    exercise['sets'] = sets;
  });

  Future<WorkoutRecord> moveExercise({
    required String workoutId,
    required String workoutExerciseId,
    required int targetPosition,
  }) => _mutateWorkout(workoutId, (workout) {
    final exercises = _mapList(workout['exercises']);
    _move(exercises, workoutExerciseId, targetPosition);
    workout['exercises'] = exercises;
  });

  Future<WorkoutRecord> moveSet({
    required String workoutId,
    required String workoutExerciseId,
    required String setId,
    required int targetPosition,
  }) => _mutateWorkout(workoutId, (workout) {
    final sets = _mapList(_findExercise(workout, workoutExerciseId)['sets']);
    _move(sets, setId, targetPosition);
  });

  Future<void> completeWorkout(String workoutId) async {
    final current = await _requireRunningWorkout(workoutId);
    final original = _map(current.workingCopy);
    final workout = WorkoutRecord.fromJson(original);
    if (!workout.exercises.any(
      (exercise) => exercise.sets.any((set) => set.isCompleted),
    )) {
      throw const TrainingValidationException({
        'workout': 'Mindestens ein abgeschlossener Satz ist erforderlich.',
      });
    }
    final now = clock().toUtc().toIso8601String();
    final changed = _mutable(original)
      ..['status'] = 'completed'
      ..['completedAtUtc'] = now
      ..['updatedAtUtc'] = now
      ..['restTimer'] = null;
    final rotationRows = await store.readAggregates(_workoutRotationType);
    final rotationEnvelope = rotationRows.isEmpty ? null : rotationRows.first;
    Map<String, LocalAggregateEnvelope<Object?>> related = const {};
    Map<String, Object?>? rotationBase;
    if (rotationEnvelope != null && workout.sourceTemplateId != null) {
      rotationBase = _mutable(rotationEnvelope.workingCopy);
      final entries = _mapList(rotationBase['entries']);
      if (entries.any(
        (entry) => entry['templateId'] == workout.sourceTemplateId,
      )) {
        rotationBase['lastCompletedTemplateId'] = workout.sourceTemplateId;
        rotationBase['updatedAtUtc'] = now;
        related = {
          _workoutRotationType: _pending(rotationEnvelope, rotationBase),
        };
      } else {
        rotationBase = null;
      }
    }
    final payload = <String, Object?>{
      ...changed,
      'rotation': rotationEnvelope == null || rotationBase == null
          ? null
          : {
              'id': rotationEnvelope.aggregateId,
              'serverVersion': rotationEnvelope.serverVersion,
              'value': rotationBase,
            },
    };
    await _commit(
      type: 'workout',
      id: workoutId,
      operation: LocalMutationOperation.complete,
      baseVersion: current.serverVersion,
      body: payload,
      envelope: _pending(current, changed),
      relatedEnvelopes: related,
    );
    await _cancelTimerNotification(workoutId);
  }

  Future<void> discardWorkout(String workoutId) async {
    final current = await _requireRunningWorkout(workoutId);
    final now = clock().toUtc().toIso8601String();
    final changed = _mutable(_map(current.workingCopy))
      ..['status'] = 'discarded'
      ..['discardedAtUtc'] = now
      ..['updatedAtUtc'] = now
      ..['restTimer'] = null;
    await _commit(
      type: 'workout',
      id: workoutId,
      operation: LocalMutationOperation.discard,
      baseVersion: current.serverVersion,
      body: changed,
      envelope: _pending(current, changed),
    );
    await _cancelTimerNotification(workoutId);
  }

  Future<WorkoutRecord> extendRestTimer(
    String workoutId, {
    int seconds = 30,
  }) async {
    if (seconds < 1 || seconds > 3600) {
      throw const TrainingValidationException({
        'timer': 'Timer-Verlängerung ist ungültig.',
      });
    }
    return _changeTimer(workoutId, (timer) {
      final target = DateTime.parse(timer['targetAtUtc'] as String).toUtc();
      timer['targetAtUtc'] = target
          .add(Duration(seconds: seconds))
          .toIso8601String();
    });
  }

  Future<WorkoutRecord> restartRestTimer(String workoutId) async =>
      _changeTimer(workoutId, (timer) {
        timer['targetAtUtc'] = clock()
            .toUtc()
            .add(Duration(seconds: timer['durationSeconds'] as int))
            .toIso8601String();
      });

  Future<WorkoutRecord> skipRestTimer(String workoutId) async {
    final result = await _changeTimer(workoutId, (_) {}, clear: true);
    await _cancelTimerNotification(workoutId);
    return result;
  }

  int? remainingRestSeconds(RestTimerRecord? timer, {DateTime? now}) =>
      timer?.remainingSeconds((now ?? clock()).toUtc());

  Future<WorkoutRecord> _changeTimer(
    String workoutId,
    void Function(Map<String, dynamic>) change, {
    bool clear = false,
  }) async {
    final current = await _requireRunningWorkout(workoutId);
    final json = _mutable(_map(current.workingCopy));
    final timer = json['restTimer'];
    if (timer is! Map<String, dynamic>) {
      throw StateError('Es läuft kein Pausentimer.');
    }
    if (clear) {
      json['restTimer'] = null;
    } else {
      change(timer);
    }
    json['updatedAtUtc'] = clock().toUtc().toIso8601String();
    await _commit(
      type: 'workout',
      id: workoutId,
      operation: LocalMutationOperation.update,
      baseVersion: current.serverVersion,
      body: json,
      envelope: _pending(current, json),
    );
    if (clear) {
      await _cancelTimerNotification(workoutId);
    } else {
      final updatedTimer = json['restTimer'] as Map<String, dynamic>;
      await _scheduleTimerNotification(
        workoutId: workoutId,
        targetUtc: DateTime.parse(updatedTimer['targetAtUtc'] as String)
            .toUtc(),
      );
    }
    return WorkoutRecord.fromJson(json);
  }

  /// Rebuilds the OS notification from the durable UTC deadline after launch.
  Future<void> resumeRestTimerNotification() async {
    final running = await _runningWorkout();
    final timer = running?.value.restTimer;
    if (running == null || timer == null) return;
    if (timer.remainingSeconds(clock().toUtc()) == 0) {
      await _cancelTimerNotification(running.id);
      return;
    }
    await _scheduleTimerNotification(
      workoutId: running.id,
      targetUtc: DateTime.parse(timer.targetAtUtc).toUtc(),
    );
  }

  Future<LocalAggregateEnvelope<Object?>> _requireAggregate(
    String type,
    String id,
  ) async =>
      await store.readAggregate(type, id) ??
      (throw StateError('The $type resource is unavailable.'));

  Future<void> _scheduleTimerNotification({
    required String workoutId,
    required DateTime targetUtc,
  }) async {
    try {
      await notifications?.schedule(workoutId: workoutId, targetUtc: targetUtc);
    } catch (_) {
      _reportNotificationUnavailable();
    }
  }

  Future<void> _cancelTimerNotification(String workoutId) async {
    try {
      await notifications?.cancel(workoutId: workoutId);
    } catch (_) {
      _reportNotificationUnavailable();
    }
  }

  void _reportNotificationUnavailable() {
    try {
      onNotificationUnavailable?.call();
    } catch (_) {
      // A status callback must never change the result of a durable workout write.
    }
  }

  Future<LocalAggregateEnvelope<Object?>> _requireRunningWorkout(
    String id,
  ) async {
    final envelope = await _requireAggregate('workout', id);
    if (!WorkoutRecord.fromJson(_map(envelope.workingCopy)).isRunning) {
      throw StateError('Only a running workout can be edited.');
    }
    return envelope;
  }

  Future<WorkoutRecord> _mutateWorkout(
    String workoutId,
    void Function(Map<String, dynamic>) mutate,
  ) async {
    final current = await _requireRunningWorkout(workoutId);
    final json = _mutable(current.workingCopy);
    mutate(json);
    json['updatedAtUtc'] = clock().toUtc().toIso8601String();
    final updated = WorkoutRecord.fromJson(json);
    await _commit(
      type: 'workout',
      id: workoutId,
      operation: LocalMutationOperation.update,
      baseVersion: current.serverVersion,
      body: json,
      envelope: _pending(current, json),
    );
    return updated;
  }

  Future<({String id, WorkoutRecord value})?> _runningWorkout() async {
    for (final envelope in await store.readAggregates('workout')) {
      final value = WorkoutRecord.fromJson(_map(envelope.workingCopy));
      if (value.isRunning) {
        return (id: envelope.aggregateId, value: value);
      }
    }
    return null;
  }

  Future<void> _commit({
    required String type,
    required String id,
    required LocalMutationOperation operation,
    required int? baseVersion,
    required Object? body,
    required LocalAggregateEnvelope<Object?> envelope,
    Map<String, LocalAggregateEnvelope<Object?>> relatedEnvelopes = const {},
  }) async => store.commitMutation(
    mutationId: ids(),
    aggregateType: type,
    aggregateId: id,
    operation: operation,
    baseVersion: baseVersion,
    body: body,
    envelope: envelope,
    relatedEnvelopes: relatedEnvelopes,
    createdAtUtc: clock().toUtc(),
    afterEnvelopeWriteForTesting: transactionFaultForTesting,
  );
}

LocalAggregateEnvelope<Object?> _pending(
  LocalAggregateEnvelope<Object?> old,
  Object? value,
) => LocalAggregateEnvelope(
  aggregateId: old.aggregateId,
  serverSnapshot: old.serverSnapshot,
  workingCopy: value,
  serverVersion: old.serverVersion,
  optimisticVersion: old.optimisticVersion + 1,
  syncState: LocalSyncState.pending,
);

ExerciseValues _normalizeExercise(ExerciseValues input) {
  validateExerciseValues(input);
  return ExerciseValues(
    name: input.name.trim(),
    description: _clean(input.description),
    targetMuscle: _clean(input.targetMuscle),
    muscleGroup: _clean(input.muscleGroup),
    equipment: _clean(input.equipment),
  );
}

String? _clean(String? value) =>
    value?.trim().isEmpty ?? true ? null : value!.trim();
String? _stringOrNull(Object? value) => value is String ? value : null;
String _str(Map<String, dynamic> value, String key) => value[key] is String
    ? value[key] as String
    : (throw FormatException('Invalid $key.'));
Map<String, dynamic> _map(Object? value) => value is Map<String, dynamic>
    ? value
    : (throw const FormatException('Expected a training object.'));
List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
    throw const FormatException('Expected a list of training objects.');
  }
  return value.cast<Map<String, dynamic>>();
}

Map<String, dynamic> _mutable(Object? value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
Map<String, Object?> _emptySet(int position) => {
  'id': _newUuidV4(),
  'position': position,
  'weightKg': null,
  'repetitions': null,
  'rir': null,
  'notes': null,
  'isCompleted': false,
  'completedAtUtc': null,
};
Map<String, dynamic> _findExercise(Map<String, dynamic> workout, String id) =>
    _mapList(workout['exercises']).firstWhere(
      (item) => item['id'] == id,
      orElse: () => throw StateError('Die Workout-Übung ist nicht verfügbar.'),
    );
void _reindex(List<Map<String, dynamic>> items) {
  for (var index = 0; index < items.length; index++) {
    items[index]['position'] = index;
  }
}

void _move(List<Map<String, dynamic>> items, String id, int target) {
  if (target < 0 || target >= items.length) {
    throw RangeError.range(target, 0, items.length - 1, 'targetPosition');
  }
  final source = items.indexWhere((item) => item['id'] == id);
  if (source < 0) throw StateError('Der Eintrag ist nicht verfügbar.');
  final item = items.removeAt(source);
  items.insert(target, item);
  _reindex(items);
}

String? _nextTemplate(
  ({String id, TrainingRotation value})? rotation,
  Set<String> activeIds,
) {
  if (rotation == null || activeIds.isEmpty || rotation.value.entries.isEmpty) {
    return null;
  }
  final entries = rotation.value.entries;
  final last = rotation.value.lastCompletedTemplateId;
  final index = last == null
      ? -1
      : entries.indexWhere((entry) => entry.templateId == last);
  for (var offset = 1; offset <= entries.length; offset++) {
    final candidate =
        entries[(index + offset + entries.length) % entries.length].templateId;
    if (activeIds.contains(candidate)) return candidate;
  }
  return null;
}

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((item) => item.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
