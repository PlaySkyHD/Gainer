import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';

const _exerciseId = '00000000-0000-4000-8000-000000000004';
const _workoutA = '00000000-0000-4000-8000-000000000010';
const _workoutB = '00000000-0000-4000-8000-000000000011';

void main() {
  test('parses exercise progress with empty records and bodyweight gaps', () {
    final progress = ApiExerciseProgress.fromJson({
      'asOfRevision': 7,
      'exerciseId': _exerciseId,
      'windowDays': null,
      'fromUtc': '2026-01-01T00:00:00Z',
      'throughUtc': '2026-10-14T23:59:59Z',
      'volumeAlgorithmVersion': 'training-volume-v2',
      'estimatedOneRepMaxAlgorithmVersion': 'e1rm-epley-v2',
      'points': [
        {
          'workoutId': _workoutA,
          'completedAtUtc': '2026-10-12T08:00:00Z',
          'volumeKgRepetitions': 480,
          'maxWeightKg': null,
          'maxRepetitions': 12,
          'estimatedOneRepMaxKg': null,
          'bodyweightMissing': true,
        },
      ],
      'bestSet': null,
      'records': {
        'maxWeightKg': null,
        'estimatedOneRepMaxKg': null,
        'volumeKgRepetitions': null,
        'maxRepetitions': null,
        'repetitionRecords': [
          {'repetitions': 12, 'maxWeightKg': null},
        ],
      },
    });

    expect(progress.windowDays, isNull);
    expect(progress.volumeAlgorithmVersion, 'training-volume-v2');
    expect(progress.estimatedOneRepMaxAlgorithmVersion, 'e1rm-epley-v2');
    expect(progress.bestSet, isNull);
    final point = progress.points.single;
    expect(point.maxWeightKg, isNull);
    expect(point.maxRepetitions, 12);
    expect(point.estimatedOneRepMaxKg, isNull);
    expect(point.bodyweightMissing, isTrue);
    expect(progress.records.maxWeightKg, isNull);
    expect(progress.records.estimatedOneRepMaxKg, isNull);
    expect(progress.records.volumeKgRepetitions, isNull);
    expect(progress.records.maxRepetitions, isNull);
    expect(progress.records.repetitionRecords.single.repetitions, 12);
    expect(progress.records.repetitionRecords.single.maxWeightKg, isNull);
  });

  test('parses records, effective best set and string-encoded numbers', () {
    final progress = ApiExerciseProgress.fromJson({
      'asOfRevision': '8',
      'exerciseId': _exerciseId,
      'windowDays': 30,
      'fromUtc': '2026-09-14T00:00:00Z',
      'throughUtc': '2026-10-14T23:59:59Z',
      'volumeAlgorithmVersion': 'training-volume-v2',
      'estimatedOneRepMaxAlgorithmVersion': 'e1rm-epley-v2',
      'points': [
        {
          'workoutId': _workoutA,
          'completedAtUtc': '2026-10-05T08:00:00Z',
          'volumeKgRepetitions': '1100',
          'maxWeightKg': '110',
          'maxRepetitions': '3',
          'estimatedOneRepMaxKg': '121.0',
          'bodyweightMissing': false,
        },
      ],
      'bestSet': {
        'workoutId': _workoutA,
        'exerciseId': _exerciseId,
        'completedAtUtc': '2026-10-05T08:00:00Z',
        'effectiveWeightKg': '110',
        'repetitions': '3',
        'estimatedOneRepMaxKg': '121.0',
      },
      'records': {
        'maxWeightKg': {'workoutId': _workoutA, 'value': 110},
        'estimatedOneRepMaxKg': {'workoutId': _workoutA, 'value': 121},
        'volumeKgRepetitions': {'workoutId': _workoutB, 'value': 1200.5},
        'maxRepetitions': {'workoutId': _workoutB, 'value': 5},
        'repetitionRecords': [
          {'repetitions': 3, 'maxWeightKg': 110},
          {'repetitions': 5, 'maxWeightKg': null},
        ],
      },
    });

    expect(progress.asOfRevision, 8);
    expect(progress.windowDays, 30);
    expect(progress.points.single.maxWeightKg, 110);
    expect(progress.points.single.maxRepetitions, 3);
    expect(progress.points.single.estimatedOneRepMaxKg, 121.0);
    expect(progress.bestSet?.effectiveWeightKg, 110);
    expect(progress.bestSet?.repetitions, 3);
    expect(progress.records.maxWeightKg?.workoutId, _workoutA);
    expect(progress.records.maxWeightKg?.value, 110);
    expect(progress.records.estimatedOneRepMaxKg?.value, 121);
    expect(progress.records.volumeKgRepetitions?.workoutId, _workoutB);
    expect(progress.records.volumeKgRepetitions?.value, 1200.5);
    expect(progress.records.maxRepetitions?.value, 5);
    expect(progress.records.repetitionRecords.map((item) => item.repetitions), [
      3,
      5,
    ]);
    expect(progress.records.repetitionRecords.last.maxWeightKg, isNull);
  });

  test('round-trips exercise progress through the cache JSON shape', () {
    final original = ApiExerciseProgress.fromJson({
      'asOfRevision': 9,
      'exerciseId': _exerciseId,
      'windowDays': null,
      'fromUtc': '2026-01-01T00:00:00Z',
      'throughUtc': '2026-10-14T23:59:59Z',
      'volumeAlgorithmVersion': 'training-volume-v2',
      'estimatedOneRepMaxAlgorithmVersion': 'e1rm-epley-v2',
      'points': [
        {
          'workoutId': _workoutA,
          'completedAtUtc': '2026-10-05T08:00:00Z',
          'volumeKgRepetitions': 300,
          'maxWeightKg': 60,
          'maxRepetitions': 5,
          'estimatedOneRepMaxKg': 70,
          'bodyweightMissing': true,
        },
      ],
      'bestSet': null,
      'records': {
        'maxWeightKg': {'workoutId': _workoutA, 'value': 60},
        'estimatedOneRepMaxKg': null,
        'volumeKgRepetitions': null,
        'maxRepetitions': null,
        'repetitionRecords': [],
      },
    });

    final restored = ApiExerciseProgress.fromJson(original.toJson());

    expect(restored.points.single.bodyweightMissing, isTrue);
    expect(restored.points.single.maxRepetitions, 5);
    expect(restored.records.maxWeightKg?.value, 60);
    expect(restored.records.estimatedOneRepMaxKg, isNull);
    expect(restored.volumeAlgorithmVersion, 'training-volume-v2');
  });

  test('parses training insights with bodyweight flag and best set', () {
    final training = ApiTrainingInsights.fromJson({
      'volumeAlgorithmVersion': 'training-volume-v2',
      'estimatedOneRepMaxAlgorithmVersion': 'e1rm-epley-v2',
      'volumeUnit': 'kg-repetitions',
      'workoutCount': 4,
      'volumeKgRepetitions': 2150.5,
      'bestSet': {
        'workoutId': _workoutA,
        'exerciseId': _exerciseId,
        'completedAtUtc': '2026-10-05T08:00:00Z',
        'effectiveWeightKg': 92.5,
        'repetitions': 6,
        'estimatedOneRepMaxKg': 116.7,
      },
      'bodyweightMissing': true,
    });

    expect(training.workoutCount, 4);
    expect(training.bestSet?.effectiveWeightKg, 92.5);
    expect(training.bodyweightMissing, isTrue);
  });

  test('rejects training insights without the bodyweight flag', () {
    expect(
      () => ApiTrainingInsights.fromJson({
        'volumeAlgorithmVersion': 'training-volume-v2',
        'estimatedOneRepMaxAlgorithmVersion': 'e1rm-epley-v2',
        'volumeUnit': 'kg-repetitions',
        'workoutCount': 0,
        'volumeKgRepetitions': 0,
        'bestSet': null,
      }),
      throwsFormatException,
    );
  });
}
