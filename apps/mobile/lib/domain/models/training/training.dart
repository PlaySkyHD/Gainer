class TrainingValidationException implements Exception {
  const TrainingValidationException(this.fields);

  final Map<String, String> fields;

  @override
  String toString() => 'TrainingValidationException($fields)';
}

class ExerciseValues {
  const ExerciseValues({
    required this.name,
    this.description,
    this.targetMuscle,
    this.muscleGroup,
    this.equipment,
  });

  final String name;
  final String? description;
  final String? targetMuscle;
  final String? muscleGroup;
  final String? equipment;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'targetMuscle': targetMuscle,
    'muscleGroup': muscleGroup,
    'equipment': equipment,
  };
}

class ExerciseCatalogEntry extends ExerciseValues {
  const ExerciseCatalogEntry({
    required this.id,
    required super.name,
    super.description,
    super.targetMuscle,
    super.muscleGroup,
    super.equipment,
    required this.catalogVersion,
  });

  final String id;
  final int catalogVersion;
}

class TrainingTemplateItem {
  const TrainingTemplateItem({
    required this.id,
    required this.exerciseId,
    required this.plannedSets,
    required this.minimumRepetitions,
    required this.maximumRepetitions,
    required this.targetRir,
    required this.restSeconds,
    required this.notes,
  });

  final String id;
  final String exerciseId;
  final int plannedSets;
  final int minimumRepetitions;
  final int maximumRepetitions;
  final double? targetRir;
  final int? restSeconds;
  final String? notes;

  factory TrainingTemplateItem.fromJson(Map<String, dynamic> json) =>
      TrainingTemplateItem(
        id: _str(json, 'id'),
        exerciseId: _str(json, 'exerciseId'),
        plannedSets: _int(json, 'plannedSets'),
        minimumRepetitions: _int(json, 'minimumRepetitions'),
        maximumRepetitions: _int(json, 'maximumRepetitions'),
        targetRir: _nullableDouble(json, 'targetRir'),
        restSeconds: json['restSeconds'] as int?,
        notes: json['notes'] as String?,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'exerciseId': exerciseId,
    'plannedSets': plannedSets,
    'minimumRepetitions': minimumRepetitions,
    'maximumRepetitions': maximumRepetitions,
    'targetRir': targetRir,
    'restSeconds': restSeconds,
    'notes': notes,
  };
}

class TrainingTemplate {
  const TrainingTemplate({
    required this.name,
    required this.items,
    required this.isArchived,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String name;
  final List<TrainingTemplateItem> items;
  final bool isArchived;
  final String createdAtUtc;
  final String updatedAtUtc;

  factory TrainingTemplate.fromJson(Map<String, dynamic> json) =>
      TrainingTemplate(
        name: _str(json, 'name'),
        items: _objects(json['items'])
            .map(TrainingTemplateItem.fromJson)
            .toList(growable: false),
        isArchived: json['isArchived'] as bool? ?? false,
        createdAtUtc: _str(json, 'createdAtUtc'),
        updatedAtUtc: _str(json, 'updatedAtUtc'),
      );

  Map<String, Object?> toJson() => {
    'name': name,
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'isArchived': isArchived,
    'createdAtUtc': createdAtUtc,
    'updatedAtUtc': updatedAtUtc,
  };
}

class TrainingRotationEntry {
  const TrainingRotationEntry({required this.id, required this.templateId});

  final String id;
  final String templateId;

  Map<String, Object?> toJson() => {'id': id, 'templateId': templateId};
}

class TrainingRotation {
  const TrainingRotation({
    required this.entries,
    required this.lastCompletedTemplateId,
    required this.updatedAtUtc,
  });

  final List<TrainingRotationEntry> entries;
  final String? lastCompletedTemplateId;
  final String updatedAtUtc;

  factory TrainingRotation.fromJson(Map<String, dynamic> json) =>
      TrainingRotation(
        entries: _objects(json['entries'])
            .map(
              (entry) => TrainingRotationEntry(
                id: _str(entry, 'id'),
                templateId: _str(entry, 'templateId'),
              ),
            )
            .toList(growable: false),
        lastCompletedTemplateId: json['lastCompletedTemplateId'] as String?,
        updatedAtUtc: _str(json, 'updatedAtUtc'),
      );

  Map<String, Object?> toJson() => {
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    'lastCompletedTemplateId': lastCompletedTemplateId,
    'updatedAtUtc': updatedAtUtc,
  };
}

class WorkoutSetRecord {
  const WorkoutSetRecord({
    required this.id,
    required this.position,
    required this.weightKg,
    required this.repetitions,
    required this.rir,
    required this.notes,
    required this.isCompleted,
    required this.completedAtUtc,
  });

  final String id;
  final int position;
  final double? weightKg;
  final int? repetitions;
  final double? rir;
  final String? notes;
  final bool isCompleted;
  final String? completedAtUtc;

  factory WorkoutSetRecord.fromJson(Map<String, dynamic> json) =>
      WorkoutSetRecord(
        id: _str(json, 'id'),
        position: _int(json, 'position'),
        weightKg: _nullableDouble(json, 'weightKg'),
        repetitions: json['repetitions'] as int?,
        rir: _nullableDouble(json, 'rir'),
        notes: json['notes'] as String?,
        isCompleted: json['isCompleted'] as bool? ?? false,
        completedAtUtc: json['completedAtUtc'] as String?,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'position': position,
    'weightKg': weightKg,
    'repetitions': repetitions,
    'rir': rir,
    'notes': notes,
    'isCompleted': isCompleted,
    'completedAtUtc': completedAtUtc,
  };
}

class WorkoutExerciseRecord {
  const WorkoutExerciseRecord({
    required this.id,
    required this.sourceExerciseId,
    required this.exerciseNameSnapshot,
    required this.position,
    required this.plannedSets,
    required this.minimumRepetitions,
    required this.maximumRepetitions,
    required this.targetRir,
    required this.restSeconds,
    required this.notes,
    required this.sets,
  });

  final String id;
  final String? sourceExerciseId;
  final String exerciseNameSnapshot;
  final int position;
  final int plannedSets;
  final int minimumRepetitions;
  final int maximumRepetitions;
  final double? targetRir;
  final int? restSeconds;
  final String? notes;
  final List<WorkoutSetRecord> sets;

  factory WorkoutExerciseRecord.fromJson(Map<String, dynamic> json) =>
      WorkoutExerciseRecord(
        id: _str(json, 'id'),
        sourceExerciseId: json['sourceExerciseId'] as String?,
        exerciseNameSnapshot: _str(json, 'exerciseNameSnapshot'),
        position: _int(json, 'position'),
        plannedSets: _int(json, 'plannedSets'),
        minimumRepetitions: _int(json, 'minimumRepetitions'),
        maximumRepetitions: _int(json, 'maximumRepetitions'),
        targetRir: _nullableDouble(json, 'targetRir'),
        restSeconds: json['restSeconds'] as int?,
        notes: json['notes'] as String?,
        sets: _objects(json['sets'])
            .map(WorkoutSetRecord.fromJson)
            .toList(growable: false),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceExerciseId': sourceExerciseId,
    'exerciseNameSnapshot': exerciseNameSnapshot,
    'position': position,
    'plannedSets': plannedSets,
    'minimumRepetitions': minimumRepetitions,
    'maximumRepetitions': maximumRepetitions,
    'targetRir': targetRir,
    'restSeconds': restSeconds,
    'notes': notes,
    'sets': sets.map((set) => set.toJson()).toList(growable: false),
  };
}

class WorkoutRecord {
  const WorkoutRecord({
    required this.sourceTemplateId,
    required this.templateNameSnapshot,
    required this.status,
    required this.exercises,
    required this.startedAtUtc,
    required this.completedAtUtc,
    required this.discardedAtUtc,
    required this.updatedAtUtc,
    required this.restTimer,
  });

  final String? sourceTemplateId;
  final String templateNameSnapshot;
  final String status;
  final List<WorkoutExerciseRecord> exercises;
  final String startedAtUtc;
  final String? completedAtUtc;
  final String? discardedAtUtc;
  final String updatedAtUtc;
  final RestTimerRecord? restTimer;

  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get isRunning => status.toLowerCase() == 'running';

  factory WorkoutRecord.fromJson(Map<String, dynamic> json) => WorkoutRecord(
    sourceTemplateId: json['sourceTemplateId'] as String?,
    templateNameSnapshot: _str(json, 'templateNameSnapshot'),
    status: _str(json, 'status'),
    exercises: _objects(json['exercises'])
        .map(WorkoutExerciseRecord.fromJson)
        .toList(growable: false),
    startedAtUtc: _str(json, 'startedAtUtc'),
    completedAtUtc: json['completedAtUtc'] as String?,
    discardedAtUtc: json['discardedAtUtc'] as String?,
    updatedAtUtc: _str(json, 'updatedAtUtc'),
    restTimer: json['restTimer'] == null
        ? null
        : RestTimerRecord.fromJson(json['restTimer'] as Map<String, dynamic>),
  );

  Map<String, Object?> toJson() => {
    'sourceTemplateId': sourceTemplateId,
    'templateNameSnapshot': templateNameSnapshot,
    'status': status,
    'exercises': exercises.map((item) => item.toJson()).toList(growable: false),
    'startedAtUtc': startedAtUtc,
    'completedAtUtc': completedAtUtc,
    'discardedAtUtc': discardedAtUtc,
    'updatedAtUtc': updatedAtUtc,
    'restTimer': restTimer?.toJson(),
  };
}

class RestTimerRecord {
  const RestTimerRecord({
    required this.sourceSetId,
    required this.durationSeconds,
    required this.targetAtUtc,
  });

  final String sourceSetId;
  final int durationSeconds;
  final String targetAtUtc;

  int remainingSeconds(DateTime now) {
    final target = DateTime.parse(targetAtUtc).toUtc();
    final remaining = target.difference(now.toUtc()).inMilliseconds;
    if (remaining <= 0) return 0;
    return (remaining + 999) ~/ 1000;
  }

  Map<String, Object?> toJson() => {
    'sourceSetId': sourceSetId,
    'durationSeconds': durationSeconds,
    'targetAtUtc': targetAtUtc,
  };

  factory RestTimerRecord.fromJson(Map<String, dynamic> json) =>
      RestTimerRecord(
        sourceSetId: _str(json, 'sourceSetId'),
        durationSeconds: _int(json, 'durationSeconds'),
        targetAtUtc: _str(json, 'targetAtUtc'),
      );
}

void validateExerciseValues(ExerciseValues input) {
  final name = input.name.trim();
  final errors = <String, String>{};
  if (name.isEmpty || name.length > 160) {
    errors['name'] = 'Name erforderlich (maximal 160 Zeichen).';
  }
  if ((input.description?.trim().length ?? 0) > 2_000) {
    errors['description'] = 'Beschreibung ist zu lang.';
  }
  if ((input.targetMuscle?.trim().length ?? 0) > 80) {
    errors['targetMuscle'] = 'Muskelangabe ist zu lang.';
  }
  if ((input.muscleGroup?.trim().length ?? 0) > 80) {
    errors['muscleGroup'] = 'Muskelgruppe ist zu lang.';
  }
  if ((input.equipment?.trim().length ?? 0) > 100) {
    errors['equipment'] = 'Geräteangabe ist zu lang.';
  }
  if (errors.isNotEmpty) {
    throw TrainingValidationException(errors);
  }
}

void validateTemplateItem(TrainingTemplateItem item) {
  final errors = <String, String>{};
  if (item.plannedSets < 1 || item.plannedSets > 100) {
    errors['plannedSets'] = 'Sätze müssen zwischen 1 und 100 liegen.';
  }
  if (item.minimumRepetitions < 1 ||
      item.maximumRepetitions < item.minimumRepetitions) {
    errors['repetitions'] = 'Der Wiederholungsbereich ist ungültig.';
  }
  if (item.targetRir != null &&
      (!item.targetRir!.isFinite ||
          item.targetRir! < 0 ||
          item.targetRir! > 10)) {
    errors['targetRir'] = 'RIR muss zwischen 0 und 10 liegen.';
  }
  if (item.restSeconds != null &&
      (item.restSeconds! < 0 || item.restSeconds! > 86400)) {
    errors['restSeconds'] = 'Die Pausenzeit ist ungültig.';
  }
  if ((item.notes?.trim().length ?? 0) > 2000) {
    errors['notes'] = 'Die Notiz ist zu lang.';
  }
  if (errors.isNotEmpty) {
    throw TrainingValidationException(errors);
  }
}

void validateWorkoutSet({
  required double? weightKg,
  required int? repetitions,
  required double? rir,
  required String? notes,
  required bool complete,
}) {
  final errors = <String, String>{};
  if (weightKg != null && (!weightKg.isFinite || weightKg < 0)) {
    errors['weightKg'] = 'Gewicht darf nicht negativ sein.';
  }
  if (repetitions != null && repetitions < 0) {
    errors['repetitions'] = 'Wiederholungen dürfen nicht negativ sein.';
  }
  if (rir != null && (!rir.isFinite || rir < 0 || rir > 10)) {
    errors['rir'] = 'RIR muss zwischen 0 und 10 liegen.';
  }
  if ((notes?.trim().length ?? 0) > 2000) {
    errors['notes'] = 'Die Notiz ist zu lang.';
  }
  if (complete &&
      (weightKg == null || repetitions == null || repetitions < 1)) {
    errors['complete'] = 'Für einen abgeschlossenen Satz werden Gewicht und Wiederholungen benötigt.';
  }
  if (errors.isNotEmpty) {
    throw TrainingValidationException(errors);
  }
}

String _str(Map<String, dynamic> value, String key) {
  final item = value[key];
  if (item is! String || item.isEmpty) {
    throw FormatException('Invalid $key.');
  }
  return item;
}

int _int(Map<String, dynamic> value, String key) {
  final item = value[key];
  if (item is int) {
    return item;
  }
  throw FormatException('Invalid $key.');
}

double? _nullableDouble(Map<String, dynamic> value, String key) {
  final item = value[key];
  if (item == null) {
    return null;
  }
  if (item is num && item.toDouble().isFinite) return item.toDouble();
  throw FormatException('Invalid $key.');
}

List<Map<String, dynamic>> _objects(Object? value) {
  if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
    throw const FormatException('Expected a list of training objects.');
  }
  return value.cast<Map<String, dynamic>>();
}
