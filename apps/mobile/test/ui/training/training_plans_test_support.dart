import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';

import 'training_test_support.dart';

/// Legt eine eigene Übung an. Kategorien müssen vorher existieren.
Future<CatalogExercise> seedExercise(
  TrainingHarness harness, {
  required String name,
  ExerciseKind kind = ExerciseKind.strength,
  List<String> categoryIds = const [],
  bool archived = false,
}) async {
  final exercise = await harness.repository.createCustomExercise(
    CatalogExercise(
      id: harness.repository.newId(),
      name: name,
      exerciseType: kind,
      categoryIds: categoryIds,
      isBase: false,
    ),
  );
  if (!archived) return exercise;
  await harness.repository.archiveCustomExercise(exercise.id);
  return exercise.copyWith(isArchived: true);
}

Future<CatalogCategory> seedCategory(TrainingHarness harness, String name) =>
    harness.repository.createCategory(
      CatalogCategory(
        id: harness.repository.newId(),
        name: name,
        isBase: false,
      ),
    );

Future<TrainingPlanModel> seedPlan(
  TrainingHarness harness, {
  required String name,
  List<PlanEntry> entries = const [],
}) => harness.repository.createPlan(
  TrainingPlanModel(
    planId: harness.repository.newId(),
    name: name,
    previousValueSource: PreviousValueSource.exercise,
    entries: entries,
  ),
);

PlanEntry planEntry(
  TrainingHarness harness, {
  required String exerciseId,
  int warmupSets = 0,
  int workingSets = 3,
  String? supersetId,
}) => PlanEntry(
  entryId: harness.repository.newId(),
  exerciseId: exerciseId,
  warmupSets: warmupSets,
  workingSets: workingSets,
  supersetId: supersetId,
);

/// Startet ein Training aus einem Plan und beendet es zum Startzeitpunkt plus
/// einer Stunde, damit der Plan als Rotationsvorschlag zählt.
Future<void> seedFinishedFromPlan(
  TrainingHarness harness,
  TrainingPlanModel plan,
  DateTime start,
) async {
  harness.now = start;
  final workout = await harness.repository.startFromPlan(plan.planId);
  harness.now = start.add(const Duration(hours: 1));
  await harness.repository.finishWorkout(workout.workoutId);
}

/// Aktives Training, das im Tagebuch als laufend gilt.
Future<Workout> seedActiveWorkout(TrainingHarness harness, String title) =>
    harness.repository.startEmpty(title: title);

/// Plan, der als synchronisiert gilt: Server-Version 1 und ohne ausstehende Mutation.
Future<TrainingPlanModel> seedSyncedPlan(
  TrainingHarness harness, {
  required String name,
  int sortOrder = 0,
}) async {
  final plan = TrainingPlanModel(
    planId: harness.repository.newId(),
    name: name,
    previousValueSource: PreviousValueSource.exercise,
    sortOrder: sortOrder,
  );
  await harness.store.ensureAccountBound();
  await harness.database
      .into(harness.database.localResources)
      .insertOnConflictUpdate(
        LocalResourcesCompanion.insert(
          aggregateType: 'training-plan',
          aggregateId: plan.planId,
          envelopeJson: serverEnvelope(
            aggregateId: plan.planId,
            snapshot: plan.toJson(),
            version: 1,
          ).encode(),
          updatedAtEpochMs: harness.now.millisecondsSinceEpoch,
        ),
      );
  return plan;
}

/// Zeile der Übungsauswahl mit diesem Namen; schließt Eingabefeld-Treffer aus.
Finder pickerRow(String name) => find.widgetWithText(GainerListRow, name);

/// iPhone-Größe wie in den Trainings-Goldens, damit Schaltflächen sichtbar sind.
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
