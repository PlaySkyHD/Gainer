import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/training_trends.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

import '../../support/contract_fixture.dart';

/// Die Verlaufskacheln rechnen wie der Server (`get_training_trends`).
void main() {
  for (final testCase in loadFixtureCases('training-trends.json')) {
    test('Fall ${testCase['name']}', () => _verify(testCase));
  }
}

void _verify(Map<String, Object?> testCase) {
  final checkIns = [
    for (final item in fixtureList(testCase['checkIns']))
      _checkIn(item! as Map<String, Object?>),
  ];
  final entries = workoutTrendEntries(
    [
      for (final item in fixtureList(testCase['workouts']))
        Workout.fromJson({
          ...item! as Map<String, Object?>,
          'previousValueSource': 'exercise',
        }),
    ],
    checkIns: checkIns,
    catalog: [
      for (final item in fixtureList(testCase['exercises']))
        _exercise(item! as Map<String, Object?>),
    ],
    includeWarmups: testCase['includeWarmups']! as bool,
    dayOf: berlinDayOf,
  );
  final trends = TrainingTrends.compute(
    entries,
    checkIns: checkIns,
    period: TrendPeriod.values.byName(testCase['period']! as String),
    today: LocalDay.parse(testCase['today']! as String),
  );
  final expected = testCase['expected']! as Map<String, Object?>;

  expect(trends.start.toIso(), expected['start']);
  expect(
    trends.bucketStarts.map((day) => day.toIso()).toList(),
    expected['bucketStarts'],
  );
  expect(trends.workoutCount, expected['workoutCount']);
  expectFixtureNumber(
    trends.workoutsPerWeek,
    expected['workoutsPerWeek'],
    'workoutsPerWeek',
  );
  expect(
    trends.averageDuration?.inSeconds,
    expected['averageDurationSeconds'],
    reason: 'averageDuration',
  );
  expect(trends.totalDuration.inSeconds, expected['totalDurationSeconds']);
  expectFixtureNumber(trends.volumeKg, expected['volumeKg'], 'volumeKg');
  expect(trends.setCount, expected['setCount']);
  expect(trends.repetitions, expected['repetitions']);
  expectFixtureNumber(
    trends.repetitionsPerSet,
    expected['repetitionsPerSet'],
    'repetitionsPerSet',
  );
  expectFixtureNumber(
    trends.latestBodyweightKg,
    expected['latestBodyweightKg'],
    'latestBodyweightKg',
  );

  final series = expected['series']! as Map<String, Object?>;
  for (final metric in TrendMetric.values) {
    final want = series[metric.name]! as List<Object?>;
    final actual = trends.series[metric]!;
    expect(actual, hasLength(want.length), reason: metric.name);
    for (var i = 0; i < want.length; i++) {
      expectFixtureNumber(actual[i], want[i], '${metric.name}[$i]');
    }
  }
}

CatalogExercise _exercise(Map<String, Object?> json) => CatalogExercise(
  id: json['id']! as String,
  name: json['id']! as String,
  exerciseType: ExerciseKind.fromWireValue(json['exerciseType']! as String),
  bodyweightFactor: (json['bodyweightFactor'] as num?)?.toDouble(),
  weightFactor: (json['weightFactor'] as num?)?.toDouble(),
  isBase: true,
);

DailyCheckIn _checkIn(Map<String, Object?> json) => DailyCheckIn(
  localDate: json['localDate']! as String,
  weightKg: (json['weightKg']! as num).toDouble(),
  caloriesKcal: null,
  proteinGrams: null,
  carbohydrateGrams: null,
  fatGrams: null,
  steps: null,
  sleepMinutes: null,
  createdAtUtc: '2026-01-01T00:00:00Z',
  updatedAtUtc: '2026-01-01T00:00:00Z',
);
