import 'exercise_catalog_model.dart';
import 'muscles.dart';
import 'training_plan_model.dart';
import 'workout_input.dart';
import 'workout_model.dart';

class WorkoutValidationException implements Exception {
  const WorkoutValidationException(this.fields);

  final Map<String, String> fields;

  @override
  String toString() => 'WorkoutValidationException($fields)';
}

const int _maxNameLength = 160;

/// Höchstlänge eines Plannamens.
const int maxPlanNameLength = _maxNameLength;
const int _maxNotesLength = 2000;
const int _maxBlocks = 50;
const int _maxSets = 50;
const int _maxWarmupSets = 20;
const int _maxWorkingSets = 50;
const int _maxCategoryIds = 10;
const double _maxWeightFactor = 10;

/// Prüft ein Training gegen die Vertragsgrenzen und wirft alle Fehler gesammelt.
void validateWorkout(Workout workout) {
  final fields = <String, String>{};
  _checkName(workout.title, 'title', fields);
  _checkNotes(workout.notes, 'notes', fields);

  final endedAt = workout.endedAtUtc;
  if (endedAt != null && !endedAt.isAfter(workout.startedAtUtc)) {
    fields['endedAtUtc'] = 'Die Endzeit muss nach der Startzeit liegen.';
  }

  if (workout.exercises.length > _maxBlocks) {
    fields['exercises'] = 'Ein Training enthält höchstens $_maxBlocks Übungen.';
  }

  for (var i = 0; i < workout.exercises.length; i++) {
    _checkBlock(workout.exercises[i], 'exercises[$i]', fields);
  }

  _throwIfAny(fields);
}

void _checkBlock(
  WorkoutBlock block,
  String prefix,
  Map<String, String> fields,
) {
  _checkName(
    block.exerciseNameSnapshot,
    '$prefix.exerciseNameSnapshot',
    fields,
  );
  _checkNotes(block.notes, '$prefix.notes', fields);

  if (block.sets.length > _maxSets) {
    fields['$prefix.sets'] = 'Eine Übung enthält höchstens $_maxSets Sätze.';
  }
  for (var j = 0; j < block.sets.length; j++) {
    _checkSet(block.sets[j], '$prefix.sets[$j]', fields);
  }
}

void _checkSet(LoggedSet set, String setPrefix, Map<String, String> fields) {
  final weight = set.weightKg;
  if (weight != null && (weight.isNaN || weight < 0 || weight > maxWeightKg)) {
    fields['$setPrefix.weightKg'] =
        'Das Gewicht muss zwischen 0 und ${maxWeightKg.toInt()} kg liegen.';
  }
  final repetitions = set.repetitions;
  if (repetitions != null &&
      (repetitions < 0 || repetitions > maxRepetitions)) {
    fields['$setPrefix.repetitions'] =
        'Wiederholungen müssen zwischen 0 und $maxRepetitions liegen.';
  }
  final rir = set.rir;
  if (rir != null && (rir < 0 || rir > maxRir)) {
    fields['$setPrefix.rir'] = 'RIR muss zwischen 0 und $maxRir liegen.';
  }
  _checkNotes(set.notes, '$setPrefix.notes', fields);
}

/// Prüft einen Plan gegen die Vertragsgrenzen.
void validateTrainingPlan(TrainingPlanModel plan) {
  final fields = <String, String>{};
  _checkName(plan.name, 'name', fields);
  _checkNotes(plan.notes, 'notes', fields);

  if (plan.entries.length > _maxBlocks) {
    fields['entries'] = 'Ein Plan enthält höchstens $_maxBlocks Übungen.';
  }
  for (var i = 0; i < plan.entries.length; i++) {
    final entry = plan.entries[i];
    final prefix = 'entries[$i]';
    if (entry.warmupSets < 0 || entry.warmupSets > _maxWarmupSets) {
      fields['$prefix.warmupSets'] =
          'Aufwärmsätze müssen zwischen 0 und $_maxWarmupSets liegen.';
    }
    if (entry.workingSets < 0 || entry.workingSets > _maxWorkingSets) {
      fields['$prefix.workingSets'] =
          'Arbeitssätze müssen zwischen 0 und $_maxWorkingSets liegen.';
    } else if (entry.warmupSets + entry.workingSets < 1) {
      fields['$prefix.workingSets'] =
          'Ein Eintrag braucht mindestens einen Satz.';
    } else if (entry.warmupSets + entry.workingSets > _maxSets) {
      // A started workout block may hold at most this many sets.
      fields['$prefix.workingSets'] =
          'Ein Eintrag darf höchstens $_maxSets Sätze haben.';
    }
    _checkNotes(entry.notes, '$prefix.notes', fields);
  }

  _throwIfAny(fields);
}

/// Prüft eine eigene oder Basisübung gegen die Vertragsgrenzen.
void validateCatalogExercise(CatalogExercise exercise) {
  final fields = <String, String>{};
  _checkName(exercise.name, 'name', fields);
  _checkNotes(exercise.notes, 'notes', fields);

  final bodyweightFactor = exercise.bodyweightFactor;
  if (bodyweightFactor != null &&
      (bodyweightFactor < 0 || bodyweightFactor > 1)) {
    fields['bodyweightFactor'] =
        'Der Körpergewichtsfaktor muss zwischen 0 und 1 liegen.';
  }
  final weightFactor = exercise.weightFactor;
  if (weightFactor != null &&
      (weightFactor <= 0 || weightFactor > _maxWeightFactor)) {
    fields['weightFactor'] =
        'Der Zusatzgewichtsfaktor muss größer 0 und höchstens $_maxWeightFactor sein.';
  }
  if (exercise.categoryIds.length > _maxCategoryIds) {
    fields['categoryIds'] =
        'Eine Übung hat höchstens $_maxCategoryIds Kategorien.';
  } else if (exercise.categoryIds.toSet().length !=
      exercise.categoryIds.length) {
    fields['categoryIds'] = 'Kategorien dürfen nicht doppelt vorkommen.';
  }
  final primary = exercise.primaryMuscles;
  final secondary = exercise.secondaryMuscles;
  if (primary.length > maxPrimaryMuscles ||
      secondary.length > maxSecondaryMuscles) {
    fields['primaryMuscles'] =
        'Höchstens $maxPrimaryMuscles Haupt- und $maxSecondaryMuscles Hilfsmuskeln.';
  } else if ({...primary, ...secondary}.length !=
      primary.length + secondary.length) {
    fields['primaryMuscles'] = 'Ein Muskel darf nur einmal vorkommen.';
  }

  _throwIfAny(fields);
}

/// Prüft eine eigene Kategorie gegen die Vertragsgrenzen.
void validateCatalogCategory(CatalogCategory category) {
  final fields = <String, String>{};
  _checkName(category.name, 'name', fields);
  _throwIfAny(fields);
}

void _checkName(String value, String key, Map<String, String> fields) {
  final length = value.trim().length;
  if (length < 1 || length > _maxNameLength) {
    fields[key] =
        'Der Name muss zwischen 1 und $_maxNameLength Zeichen lang sein.';
  }
}

void _checkNotes(String? value, String key, Map<String, String> fields) {
  if (value != null && value.length > _maxNotesLength) {
    fields[key] = 'Die Notiz darf höchstens $_maxNotesLength Zeichen haben.';
  }
}

void _throwIfAny(Map<String, String> fields) {
  if (fields.isNotEmpty) throw WorkoutValidationException(fields);
}
