import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/muscle_volume.dart';
import 'package:gainer_mobile/domain/models/training/muscles.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

import '../../support/contract_fixture.dart';

/// Die Muskelkarte rechnet wie der Server (`get_muscle_volume`).
void main() {
  for (final testCase in loadFixtureCases('muscle-volume.json')) {
    test('Fall ${testCase['name']}', () => _verify(testCase));
  }
}

void _verify(Map<String, Object?> testCase) {
  final exercises = {
    for (final item in fixtureList(testCase['exercises']))
      (item! as Map<String, Object?>)['id']! as String: _exercise(
        item as Map<String, Object?>,
      ),
  };
  final volume = testCase['source'] == 'planned'
      ? MuscleVolume.fromPlans([
          for (final item in fixtureList(testCase['plans']))
            _plan(item! as Map<String, Object?>),
        ], exercises)
      : MuscleVolume.fromWorkouts(
          [
            for (final item in fixtureList(testCase['workouts']))
              Workout.fromJson({
                ...item! as Map<String, Object?>,
                'previousValueSource': 'exercise',
              }),
          ],
          exercises,
          fromUtc: DateTime.parse(testCase['fromUtc']! as String),
          toUtc: DateTime.parse(testCase['toUtc']! as String),
          weeks: testCase['weeks']! as int,
        );
  final expected = testCase['expected']! as Map<String, Object?>;

  expect(
    volume.ranked.map((muscle) => muscle.wireValue).toList(),
    expected['ranked'],
  );
  final muscles = [
    for (final item in fixtureList(expected['muscles']))
      item! as Map<String, Object?>,
  ];
  expect(
    volume.ranked
        .where((muscle) => volume.setsFor(muscle) > 0)
        .map((muscle) => muscle.wireValue)
        .toList(),
    [for (final item in muscles) item['muscle']],
  );
  for (final item in muscles) {
    final muscle = Muscle.fromWireValue(item['muscle'])!;
    final label = muscle.wireValue;
    expectFixtureNumber(volume.setsFor(muscle), item['sets'], '$label sets');
    expect(volume.levelFor(muscle).name, item['level'], reason: label);
    final contributions = volume.contributionsFor(muscle);
    final want = fixtureList(item['contributions']);
    expect(contributions, hasLength(want.length), reason: label);
    for (var i = 0; i < want.length; i++) {
      final contribution = want[i]! as Map<String, Object?>;
      final actual = contributions[i];
      expect(actual.exerciseId, contribution['exerciseId'], reason: label);
      expect(actual.exerciseName, contribution['exerciseName'], reason: label);
      expect(actual.role.name, contribution['role'], reason: label);
      expectFixtureNumber(
        actual.workingSets,
        contribution['workingSets'],
        '$label workingSets',
      );
      expectFixtureNumber(actual.sets, contribution['sets'], '$label sets');
    }
  }
  expect([
    for (final exercise in volume.exercisesWithoutMuscles)
      {'id': exercise.id, 'name': exercise.name},
  ], expected['exercisesWithoutMuscles']);
}

CatalogExercise _exercise(Map<String, Object?> json) => CatalogExercise(
  id: json['id']! as String,
  name: json['name']! as String,
  exerciseType: ExerciseKind.fromWireValue(json['exerciseType']! as String),
  primaryMuscles: Muscle.listFromJson(json['primaryMuscles']),
  secondaryMuscles: Muscle.listFromJson(json['secondaryMuscles']),
  isBase: false,
);

TrainingPlanModel _plan(Map<String, Object?> json) => TrainingPlanModel(
  planId: json['planId']! as String,
  name: json['planId']! as String,
  previousValueSource: PreviousValueSource.exercise,
  isArchived: json['archived']! as bool,
  entries: [
    for (final (index, item) in fixtureList(json['entries']).indexed)
      _entry('${json['planId']}-$index', item! as Map<String, Object?>),
  ],
);

PlanEntry _entry(String id, Map<String, Object?> json) => PlanEntry(
  entryId: id,
  exerciseId: json['exerciseId']! as String,
  warmupSets: 0,
  workingSets: json['workingSets']! as int,
);
