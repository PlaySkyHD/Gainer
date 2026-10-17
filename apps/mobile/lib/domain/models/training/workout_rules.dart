import 'exercise_catalog_model.dart';
import 'training_plan_model.dart';
import 'workout_model.dart';
import 'workout_validation.dart';

/// Ein Satz gilt als erfasst, wenn die Pflichtwerte seines Übungstyps gesetzt sind.
bool isSetRecorded(LoggedSet set, ExerciseKind kind) {
  final repetitions = set.repetitions;
  final hasRepetitions = repetitions != null && repetitions >= 1;
  return switch (kind) {
    ExerciseKind.strength ||
    ExerciseKind.assisted => set.weightKg != null && hasRepetitions,
    ExerciseKind.bodyweightLoaded ||
    ExerciseKind.bodyweightOnly => hasRepetitions,
  };
}

bool isBlockComplete(WorkoutBlock block) =>
    block.sets.isNotEmpty &&
    block.sets.every((set) => isSetRecorded(set, block.exerciseTypeSnapshot));

/// Normale Sätze werden fortlaufend nummeriert, Aufwärmsätze tragen „W“, Dropsätze „D“.
List<String> setLabels(List<LoggedSet> sets) {
  final labels = <String>[];
  var number = 0;
  for (final set in sets) {
    labels.add(switch (set.setType) {
      SetType.warmup => 'W',
      SetType.dropset => 'D',
      SetType.normal => '${++number}',
    });
  }
  return labels;
}

class SupersetGroup {
  const SupersetGroup({required this.supersetId, required this.blockIndexes});

  /// `null` für einzelne Blöcke ohne Superset.
  final String? supersetId;
  final List<int> blockIndexes;

  bool get isSuperset => supersetId != null && blockIndexes.length > 1;

  /// Buchstabe A–Z innerhalb eines Supersets; `null` außerhalb davon.
  String? labelAt(int position) {
    if (!isSuperset || position < 0 || position >= 26) return null;
    return String.fromCharCode(0x41 + position);
  }
}

/// Nur unmittelbar benachbarte Blöcke mit gleicher, nicht leerer Superset-ID
/// bilden eine Gruppe; jeder übrige Block ist eine eigene Gruppe.
List<SupersetGroup> supersetGroups(List<WorkoutBlock> blocks) {
  final groups = <SupersetGroup>[];
  var start = 0;
  while (start < blocks.length) {
    final id = _nonEmpty(blocks[start].supersetId);
    var end = start + 1;
    if (id != null) {
      while (end < blocks.length && blocks[end].supersetId == id) {
        end++;
      }
    }
    groups.add(
      SupersetGroup(
        supersetId: id,
        blockIndexes: [for (var i = start; i < end; i++) i],
      ),
    );
    start = end;
  }
  return groups;
}

class MissingValueSet {
  const MissingValueSet({
    required this.blockIndex,
    required this.setIndex,
    required this.workoutExerciseId,
    required this.setId,
  });

  final int blockIndex;
  final int setIndex;
  final String workoutExerciseId;
  final String setId;
}

/// Alle Sätze, denen Pflichtwerte für ihren Übungstyp fehlen.
List<MissingValueSet> missingValueSets(Workout workout) {
  final missing = <MissingValueSet>[];
  for (var b = 0; b < workout.exercises.length; b++) {
    final block = workout.exercises[b];
    for (var s = 0; s < block.sets.length; s++) {
      final set = block.sets[s];
      if (!isSetRecorded(set, block.exerciseTypeSnapshot)) {
        missing.add(
          MissingValueSet(
            blockIndex: b,
            setIndex: s,
            workoutExerciseId: block.workoutExerciseId,
            setId: set.setId,
          ),
        );
      }
    }
  }
  return missing;
}

/// Startet ein Training aus einem Plan: Aufwärmsätze zuerst, dann Arbeitssätze, alle ohne Werte.
Workout workoutFromPlan(
  TrainingPlanModel plan,
  List<CatalogExercise> catalog,
  IdFactory ids,
  DateTime now,
) {
  final workoutId = ids();
  final blocks = <WorkoutBlock>[];
  for (final entry in plan.entries) {
    final exercise = _exerciseById(catalog, entry.exerciseId);
    blocks.add(
      WorkoutBlock(
        workoutExerciseId: ids(),
        sourceExerciseId: exercise.id,
        exerciseNameSnapshot: exercise.name,
        exerciseTypeSnapshot: exercise.exerciseType,
        notes: entry.notes,
        supersetId: entry.supersetId,
        sets: [
          for (var i = 0; i < entry.warmupSets; i++)
            LoggedSet(setId: ids(), setType: SetType.warmup),
          for (var i = 0; i < entry.workingSets; i++)
            LoggedSet(setId: ids(), setType: SetType.normal),
        ],
      ),
    );
  }
  final workout = Workout(
    workoutId: workoutId,
    title: plan.name,
    notes: plan.notes,
    startedAtUtc: _roundToSecond(now),
    previousValueSource: plan.previousValueSource,
    sourcePlanId: plan.planId,
    exercises: blocks,
  );
  validateWorkout(workout);
  return workout;
}

/// Wiederholt ein Training: Struktur und Satztypen bleiben, Satzwerte fallen weg.
Workout workoutFromRepeat(
  Workout source,
  IdFactory ids,
  DateTime now,
  PreviousValueSource previousValueSource,
) {
  final workoutId = ids();
  final newSupersetIds = <String, String>{};
  final blocks = [
    for (final block in source.exercises)
      WorkoutBlock(
        workoutExerciseId: ids(),
        sourceExerciseId: block.sourceExerciseId,
        exerciseNameSnapshot: block.exerciseNameSnapshot,
        exerciseTypeSnapshot: block.exerciseTypeSnapshot,
        notes: block.notes,
        supersetId: _freshSupersetId(block.supersetId, newSupersetIds, ids),
        sets: [
          for (final set in block.sets)
            LoggedSet(setId: ids(), setType: set.setType),
        ],
      ),
  ];
  return Workout(
    workoutId: workoutId,
    title: source.title,
    startedAtUtc: _roundToSecond(now),
    previousValueSource: previousValueSource,
    sourceWorkoutId: source.workoutId,
    exercises: blocks,
  );
}

Workout emptyWorkout(IdFactory ids, DateTime now, String title) => Workout(
  workoutId: ids(),
  title: title,
  startedAtUtc: _roundToSecond(now),
  previousValueSource: PreviousValueSource.exercise,
);

class PlanFromWorkout {
  const PlanFromWorkout({required this.plan, this.existingPlan});

  final TrainingPlanModel plan;

  /// Nicht archivierter Plan mit gleichem Namen (ohne Groß-/Kleinschreibung).
  /// Die UI fragt dann, ob er überschrieben oder ein neuer Plan angelegt wird.
  final TrainingPlanModel? existingPlan;
}

/// Speichert ein Training als Plan. Blöcke ohne Sätze werden übersprungen,
/// weil ein Planeintrag mindestens einen Satz braucht.
PlanFromWorkout planFromWorkout(
  Workout workout,
  List<TrainingPlanModel> existingPlans,
  IdFactory ids,
) {
  final entries = <PlanEntry>[];
  for (final block in workout.exercises) {
    if (block.sets.isEmpty) continue;
    final warmupSets = block.sets
        .where((set) => set.setType == SetType.warmup)
        .length;
    entries.add(
      PlanEntry(
        entryId: ids(),
        exerciseId: block.sourceExerciseId,
        warmupSets: warmupSets,
        workingSets: block.sets.length - warmupSets,
        notes: block.notes,
        supersetId: block.supersetId,
      ),
    );
  }

  final nameKey = workout.title.trim().toLowerCase();
  TrainingPlanModel? existing;
  var nextSortOrder = 0;
  for (final plan in existingPlans) {
    if (!plan.isArchived &&
        existing == null &&
        plan.name.trim().toLowerCase() == nameKey) {
      existing = plan;
    }
    if (plan.sortOrder >= nextSortOrder) nextSortOrder = plan.sortOrder + 1;
  }

  return PlanFromWorkout(
    plan: TrainingPlanModel(
      planId: ids(),
      name: workout.title,
      notes: workout.notes,
      previousValueSource: workout.previousValueSource,
      entries: entries,
      sortOrder: nextSortOrder,
    ),
    existingPlan: existing,
  );
}

/// Nächster aktiver Plan nach dem jüngsten beendeten, nicht gelöschten Training
/// aus der Rotation. Ohne solches Training beginnt die Rotation vorn; nach dem
/// letzten Plan folgt wieder der erste. Archivierte Pläne werden übersprungen.
String? nextRotationPlanId(
  RotationModel rotation,
  List<TrainingPlanModel> plans,
  List<Workout> workouts,
) {
  final order = rotation.planIds;
  if (order.isEmpty) return null;

  final activePlanIds = {
    for (final plan in plans)
      if (!plan.isArchived) plan.planId,
  };

  String? lastPlanId;
  DateTime? lastEndedAt;
  for (final workout in workouts) {
    final planId = workout.sourcePlanId;
    final endedAt = workout.endedAtUtc;
    if (endedAt == null ||
        workout.deletedAtUtc != null ||
        planId == null ||
        !order.contains(planId)) {
      continue;
    }
    if (lastEndedAt == null || endedAt.isAfter(lastEndedAt)) {
      lastEndedAt = endedAt;
      lastPlanId = planId;
    }
  }

  final start = lastPlanId == null ? -1 : order.indexOf(lastPlanId);
  for (var step = 1; step <= order.length; step++) {
    final candidate = order[(start + step) % order.length];
    if (activePlanIds.contains(candidate)) return candidate;
  }
  return null;
}

CatalogExercise _exerciseById(List<CatalogExercise> catalog, String id) {
  for (final exercise in catalog) {
    if (exercise.id == id) return exercise;
  }
  throw WorkoutValidationException({
    'exerciseId': 'Die Übung ist nicht im Katalog vorhanden.',
  });
}

String? _freshSupersetId(
  String? supersetId,
  Map<String, String> newIds,
  IdFactory ids,
) {
  final id = _nonEmpty(supersetId);
  if (id == null) return null;
  return newIds.putIfAbsent(id, ids);
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

/// Sekundengenau in UTC, damit die Startzeit in JSON und Sync stabil ist.
DateTime _roundToSecond(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
}
