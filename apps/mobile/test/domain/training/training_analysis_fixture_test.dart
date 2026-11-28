import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_analysis.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/training_trends.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

import '../../support/contract_fixture.dart';

/// Die Trainingsanalyse rechnet wie der Server (`get_training_analysis`).
void main() {
  final cases = loadFixtureCases('training-analysis.json');
  for (final testCase in cases) {
    test('Fall ${testCase['name']}', () {
      final analysis = _compute(testCase);
      _expectMatches('expected', testCase['expected'], _toJson(analysis));
    });
  }

  test('jeder Status, jedes Signal und jede Empfehlung ist abgedeckt', () {
    final seen = <String>{};
    for (final testCase in cases) {
      final expected = testCase['expected']! as Map<String, Object?>;
      for (final item in fixtureList(expected['exercises'])) {
        final exercise = item! as Map<String, Object?>;
        seen.add(exercise['status']! as String);
        seen.add(
          (exercise['recommendation']! as Map<String, Object?>)['kind']!
              as String,
        );
        for (final signal in fixtureList(exercise['fatigueSignals'])) {
          seen.add((signal! as Map<String, Object?>)['kind']! as String);
        }
      }
    }
    for (final value in [
      ...ExerciseProgressStatus.values,
      ...FatigueSignalKind.values,
      ...RecommendationKind.values,
    ]) {
      expect(seen, contains(value.name));
    }
  });

  test('Zeitraum „Alle“ ist nicht erlaubt', () {
    expect(
      () => TrainingAnalysis.compute(
        const [],
        checkIns: const [],
        catalog: const [],
        period: TrendPeriod.all,
        today: LocalDay(2026, 11, 25),
      ),
      throwsArgumentError,
    );
  });

  test('Zahlen deutsch formatiert', () {
    expect(formatAnalysisNumber(1002.5), '1.002,5');
    expect(formatAnalysisNumber(92.5), '92,5');
    expect(formatAnalysisNumber(120), '120');
  });
}

TrainingAnalysis _compute(Map<String, Object?> testCase) {
  return TrainingAnalysis.compute(
    [
      for (final item in fixtureList(testCase['workouts']))
        Workout.fromJson({
          ...item! as Map<String, Object?>,
          'previousValueSource': 'exercise',
        }),
    ],
    checkIns: [
      for (final item in fixtureList(testCase['checkIns']))
        _checkIn(item! as Map<String, Object?>),
    ],
    catalog: [
      for (final item in fixtureList(testCase['exercises']))
        _exercise(item! as Map<String, Object?>),
    ],
    period: TrendPeriod.values.byName(testCase['period']! as String),
    today: LocalDay.parse(testCase['today']! as String),
    dayOf: berlinDayOf,
  );
}

Map<String, Object?> _toJson(TrainingAnalysis analysis) => {
  'start': analysis.start.toIso(),
  'exercises': [for (final item in analysis.exercises) _exerciseJson(item)],
  'overall': {
    'weeks': [
      for (final week in analysis.overall.weeks)
        {
          'start': week.start.toIso(),
          'complete': week.complete,
          'volumeKg': week.volumeKg,
          'workingSets': week.workingSets,
        },
    ],
    'weeklyVolumeChangePercent': analysis.overall.weeklyVolumeChangePercent,
    'exercisesWithFatigue': analysis.overall.exercisesWithFatigue,
    'eligibleExercises': analysis.overall.eligibleExercises,
    'fatigued': analysis.overall.fatigued,
  },
};

Map<String, Object?> _exerciseJson(ExerciseAnalysis item) => {
  'exerciseId': item.exerciseId,
  'name': item.name,
  'exerciseType': item.exerciseType.wireValue,
  'status': item.status.name,
  'sessions': [
    for (final session in item.sessions)
      {
        'workoutId': session.workoutId,
        'day': session.day.toIso(),
        'workingSets': session.workingSets,
        'volumeKg': session.volumeKg,
        'estimatedOneRepMaxKg': session.estimatedOneRepMaxKg,
        'topWeightKg': session.topWeightKg,
        'topSetMinRepetitions': session.topSetMinRepetitions,
        'topSetMaxRepetitions': session.topSetMaxRepetitions,
      },
  ],
  'bestEstimatedOneRepMaxKg': item.bestEstimatedOneRepMaxKg,
  'sessionsSinceBest': item.sessionsSinceBest,
  'estimatedOneRepMaxFirstKg': item.estimatedOneRepMaxFirstKg,
  'estimatedOneRepMaxLastKg': item.estimatedOneRepMaxLastKg,
  'estimatedOneRepMaxChangePercent': item.estimatedOneRepMaxChangePercent,
  'topWeightChangePercent': item.topWeightChangePercent,
  'topRepetitionsChange': item.topRepetitionsChange,
  'volumeChangePercent': item.volumeChangePercent,
  'volumePerWeekKg': item.volumePerWeekKg,
  'workingSetsPerWeek': item.workingSetsPerWeek,
  'fatigueSignals': [
    for (final signal in item.fatigueSignals)
      {
        'kind': signal.kind.name,
        'sessions': signal.sessions,
        'fromRepetitions': signal.fromRepetitions,
        'toRepetitions': signal.toRepetitions,
        'weightKg': signal.weightKg,
        'zeroRirSets': signal.zeroRirSets,
        'ratedSets': signal.ratedSets,
        'volumeChangePercent': signal.volumeChangePercent,
        'estimatedOneRepMaxChangePercent':
            signal.estimatedOneRepMaxChangePercent,
      },
  ],
  'recommendation': {
    'kind': item.recommendation.kind.name,
    'suggestedWeightKg': item.recommendation.suggestedWeightKg,
    'suggestedRepetitions': item.recommendation.suggestedRepetitions,
    'repetitionRangeLow': item.recommendation.repetitionRangeLow,
    'repetitionRangeHigh': item.recommendation.repetitionRangeHigh,
    'weightStepKg': item.recommendation.weightStepKg,
    'text': item.recommendation.text(),
  },
};

/// Jede erwartete Eigenschaft muss passen, und keine berechnete darf fehlen.
void _expectMatches(String path, Object? expected, Object? actual) {
  switch (expected) {
    case final Map<String, Object?> map:
      final actualMap = actual! as Map<String, Object?>;
      expect(actualMap.keys.toSet(), map.keys.toSet(), reason: path);
      for (final entry in map.entries) {
        _expectMatches('$path.${entry.key}', entry.value, actualMap[entry.key]);
      }
    case final List<Object?> list:
      final actualList = actual! as List<Object?>;
      expect(actualList, hasLength(list.length), reason: path);
      for (var i = 0; i < list.length; i++) {
        _expectMatches('$path[$i]', list[i], actualList[i]);
      }
    case final num number:
      expectFixtureNumber(actual as num?, number, path);
    default:
      expect(actual, expected, reason: path);
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
