import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_statistics.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

/// Gemeinsame Vertrags-Fixture für App und Backend (siehe design.md, D7).
/// Der Pfad ist relativ zum Paketverzeichnis `apps/mobile`.
const _fixturePath = '../../contracts/fixtures/training-statistics.json';

void main() {
  final fixture =
      jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>;
  final cases = [
    for (final item in fixture['cases'] as List<Object?>)
      item! as Map<String, Object?>,
  ];

  test('Fixture enthält die erwarteten Algorithmusversionen', () {
    expect(fixture['algorithmVersions'], {
      'volume': 'training-volume-v2',
      'e1rm': 'e1rm-epley-v2',
    });
  });

  for (final testCase in cases) {
    test('Fall ${testCase['name']}', () {
      _verifyCase(testCase);
    });
  }
}

void _verifyCase(Map<String, Object?> testCase) {
  final localDayOf = _localDayOf(testCase['timeZone'] as String);
  final includeWarmups = testCase['includeWarmups'] as bool? ?? false;
  final catalog = [
    for (final item in _list(testCase['exercises']))
      _catalogExercise(item as Map<String, Object?>),
  ];
  final checkIns = [
    for (final item in _list(testCase['checkIns']))
      _checkIn(item as Map<String, Object?>),
  ];
  final workouts = [
    for (final item in _list(testCase['workouts']))
      Workout.fromJson({
        ...item! as Map<String, Object?>,
        'previousValueSource': 'exercise',
      }),
  ];
  final expected = testCase['expected']! as Map<String, Object?>;

  final actualStats = [
    for (final workout in workouts)
      if (isCountedWorkout(workout))
        ...workoutExerciseStats(
          workout,
          checkIns: checkIns,
          catalog: catalog,
          localDayOf: localDayOf,
          includeWarmups: includeWarmups,
        ),
  ];
  final expectedWorkouts = [
    for (final workout in _list(expected['workouts']))
      workout! as Map<String, Object?>,
  ];
  final expectedStats = [
    for (final workout in expectedWorkouts)
      for (final exercise in _list(workout['exercises']))
        exercise! as Map<String, Object?>,
  ];

  expect(
    actualStats.map((stat) => stat.workoutExerciseId).toList(),
    expectedStats.map((stat) => stat['workoutExerciseId']).toList(),
    reason: 'Blöcke in Trainings',
  );
  for (var i = 0; i < expectedStats.length; i++) {
    _expectStats(actualStats[i], expectedStats[i]);
  }

  final records = exerciseRecords(
    workouts,
    checkIns: checkIns,
    catalog: catalog,
    localDayOf: localDayOf,
    includeWarmups: includeWarmups,
  );
  for (final exercise in _list(expected['exercises'])) {
    final expectedRecords = exercise! as Map<String, Object?>;
    final exerciseId = expectedRecords['exerciseId'] as String;
    final actual = records[exerciseId];
    expect(actual, isNotNull, reason: 'Rekorde für $exerciseId');
    _expectRecords(actual!, expectedRecords);
  }

  final summaryJson = expected['summary'] as Map<String, Object?>?;
  if (summaryJson != null) {
    final summaryWorkout = workouts.singleWhere(
      (workout) => workout.workoutId == summaryJson['workoutId'],
    );
    final summary = summarizeTraining(
      summaryWorkout,
      history: workouts,
      checkIns: checkIns,
      catalog: catalog,
      localDayOf: localDayOf,
      includeWarmups: includeWarmups,
    );
    _expectSummary(summary, summaryJson);
  }
}

void _expectStats(ExerciseStats actual, Map<String, Object?> expected) {
  final label = expected['workoutExerciseId'] as String;
  expect(actual.setCount, expected['setCount'], reason: '$label setCount');
  expect(
    actual.totalRepetitions,
    expected['totalRepetitions'],
    reason: '$label totalRepetitions',
  );
  expect(
    actual.maxRepetitions,
    expected['maxRepetitions'],
    reason: '$label maxRepetitions',
  );
  _expectNumber(actual.volumeKg, expected['volumeKg'], '$label volumeKg');
  _expectNumber(
    actual.maxWeightKg,
    expected['maxWeightKg'],
    '$label maxWeightKg',
  );
  _expectNumber(
    actual.averageWeightKg,
    expected['averageWeightKg'],
    '$label averageWeightKg',
  );
  _expectNumber(
    actual.estimatedOneRepMaxKg,
    expected['estimatedOneRepMaxKg'],
    '$label estimatedOneRepMaxKg',
  );
  _expectNumber(
    actual.bodyweightKg,
    expected['bodyweightKg'],
    '$label bodyweightKg',
  );
  expect(
    actual.bodyweightMissing,
    expected['bodyweightMissing'],
    reason: '$label bodyweightMissing',
  );
}

void _expectRecords(ExerciseRecords actual, Map<String, Object?> expected) {
  final id = expected['exerciseId'];
  final records = expected['records'] as Map<String, Object?>?;
  if (records != null) {
    for (final kind in RecordKind.values) {
      final key = kind.name;
      if (!records.containsKey(key)) continue;
      _expectEvents(actual.eventsOf(kind), _list(records[key]), '$id $key');
    }
  }
  final repRecords = expected['repRecords'] as Map<String, Object?>?;
  if (repRecords != null) {
    for (final entry in repRecords.entries) {
      _expectNumber(
        actual.repRecords[int.parse(entry.key)],
        entry.value,
        '$id repRecords ${entry.key}',
      );
    }
  }
}

void _expectEvents(
  List<RecordEvent> actual,
  List<Object?> expected,
  String label,
) {
  expect(actual.map((event) => event.workoutId).toList(), [
    for (final item in expected) (item! as Map)['workoutId'],
  ], reason: '$label Ereignisse');
  for (var i = 0; i < expected.length; i++) {
    _expectNumber(
      actual[i].value,
      (expected[i]! as Map)['value'],
      '$label Wert $i',
    );
  }
}

void _expectSummary(TrainingSummary actual, Map<String, Object?> expected) {
  expect(
    actual.duration.inSeconds,
    expected['durationSeconds'],
    reason: 'Dauer',
  );
  expect(actual.setCount, expected['setCount'], reason: 'Satzanzahl');
  expect(
    actual.totalRepetitions,
    expected['totalRepetitions'],
    reason: 'Wiederholungen',
  );
  _expectNumber(actual.volumeKg, expected['volumeKg'], 'Volumen');

  final expectedBest = [
    for (final item in _list(expected['bestSets']))
      item! as Map<String, Object?>,
  ];
  expect(actual.bestSets.map((best) => best.sourceExerciseId).toList(), [
    for (final item in expectedBest) item['exerciseId'],
  ], reason: 'Beste Sätze');
  for (var i = 0; i < expectedBest.length; i++) {
    final best = actual.bestSets[i].set;
    _expectNumber(
      best.effectiveWeightKg,
      expectedBest[i]['weightKg'],
      'bester Satz $i Gewicht',
    );
    expect(best.repetitions, expectedBest[i]['repetitions']);
    _expectNumber(
      best.estimatedOneRepMaxKg,
      expectedBest[i]['estimatedOneRepMaxKg'],
      'bester Satz $i 1RM',
    );
  }

  final expectedNew = [
    for (final item in _list(expected['newRecords']))
      item! as Map<String, Object?>,
  ];
  expect(
    actual.newRecords
        .map((record) => '${record.sourceExerciseId}/${record.kind.name}')
        .toList(),
    [for (final item in expectedNew) '${item['exerciseId']}/${item['kind']}'],
    reason: 'Neue Rekorde',
  );
  for (var i = 0; i < expectedNew.length; i++) {
    _expectNumber(
      actual.newRecords[i].value,
      expectedNew[i]['value'],
      'neuer Rekord $i',
    );
  }
}

/// Vergleicht auf zwei Nachkommastellen gerundet; `null` muss exakt passen.
void _expectNumber(double? actual, Object? expected, String label) {
  if (expected == null) {
    expect(actual, isNull, reason: label);
    return;
  }
  expect(actual, isNotNull, reason: label);
  expect(
    roundToTwoDecimals(actual!),
    closeTo((expected as num).toDouble(), 1e-9),
    reason: label,
  );
}

List<Object?> _list(Object? value) =>
    value == null ? const [] : (value as List<Object?>);

CatalogExercise _catalogExercise(Map<String, Object?> json) => CatalogExercise(
  id: json['id'] as String,
  name: json['id'] as String,
  exerciseType: ExerciseKind.fromWireValue(json['exerciseType'] as String),
  bodyweightFactor: (json['bodyweightFactor'] as num?)?.toDouble(),
  weightFactor: (json['weightFactor'] as num?)?.toDouble(),
  isBase: true,
);

DailyCheckIn _checkIn(Map<String, Object?> json) => DailyCheckIn(
  localDate: json['localDate'] as String,
  weightKg: (json['weightKg'] as num).toDouble(),
  caloriesKcal: null,
  proteinGrams: null,
  carbohydrateGrams: null,
  fatGrams: null,
  steps: null,
  sleepMinutes: null,
  createdAtUtc: '2026-10-01T00:00:00Z',
  updatedAtUtc: '2026-10-01T00:00:00Z',
);

LocalDayOf _localDayOf(String timeZone) => switch (timeZone) {
  'Europe/Berlin' => _berlinDay,
  'UTC' => (instant) => formatCalendarDay(instant.toUtc()),
  _ => throw ArgumentError.value(timeZone, 'timeZone', 'Nicht unterstützt.'),
};

/// Mitteleuropäische Zeit mit Sommerzeit (letzter Sonntag im März bis letzter Sonntag im Oktober, je 01:00 UTC).
String _berlinDay(DateTime instant) {
  final utc = instant.toUtc();
  final summerTime =
      !utc.isBefore(_lastSundayAt1Utc(utc.year, 3)) &&
      utc.isBefore(_lastSundayAt1Utc(utc.year, 10));
  final offset = summerTime ? 2 : 1;
  return formatCalendarDay(utc.add(Duration(hours: offset)));
}

DateTime _lastSundayAt1Utc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  final sunday = lastDay.subtract(Duration(days: lastDay.weekday % 7));
  return sunday.add(const Duration(hours: 1));
}
