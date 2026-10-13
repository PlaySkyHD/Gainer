import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training.dart';

void main() {
  test('exercise and template validation enforce user input bounds', () {
    expect(
      () => validateExerciseValues(const ExerciseValues(name: '  ')),
      throwsA(isA<TrainingValidationException>()),
    );
    expect(
      () => validateTemplateItem(
        const TrainingTemplateItem(
          id: 'set',
          exerciseId: 'exercise',
          plannedSets: 0,
          minimumRepetitions: 10,
          maximumRepetitions: 5,
          targetRir: 11,
          restSeconds: -1,
          notes: null,
        ),
      ),
      throwsA(isA<TrainingValidationException>()),
    );
  });

  test(
    'rest timer rounds up and preserves extensions past original duration',
    () {
      final now = DateTime.utc(2026, 10, 12, 10);
      final timer = RestTimerRecord(
        sourceSetId: 'set',
        durationSeconds: 90,
        targetAtUtc: now
            .add(const Duration(milliseconds: 1500))
            .toIso8601String(),
      );
      expect(timer.remainingSeconds(now), 2);
      expect(timer.remainingSeconds(now.add(const Duration(seconds: 100))), 0);
      expect(
        timer.remainingSeconds(now.subtract(const Duration(seconds: 100))),
        102,
      );
    },
  );

  test('workout codec retains snapshot facts and nested set IDs', () {
    final record = WorkoutRecord.fromJson({
      'sourceTemplateId': 'template',
      'templateNameSnapshot': 'Upper A',
      'status': 'completed',
      'exercises': [
        {
          'id': 'workout-exercise',
          'sourceExerciseId': 'exercise',
          'exerciseNameSnapshot': 'Press',
          'position': 0,
          'plannedSets': 1,
          'minimumRepetitions': 6,
          'maximumRepetitions': 8,
          'targetRir': 2.0,
          'restSeconds': 90,
          'notes': null,
          'sets': [
            {
              'id': 'logged-set',
              'position': 0,
              'weightKg': 60,
              'repetitions': 8,
              'rir': 2,
              'notes': null,
              'isCompleted': true,
              'completedAtUtc': '2026-10-12T10:00:00Z',
            },
          ],
        },
      ],
      'startedAtUtc': '2026-10-12T09:00:00Z',
      'completedAtUtc': '2026-10-12T10:00:00Z',
      'discardedAtUtc': null,
      'updatedAtUtc': '2026-10-12T10:00:00Z',
      'restTimer': null,
    });
    expect(record.isCompleted, isTrue);
    expect(record.exercises.single.sets.single.id, 'logged-set');
    expect(record.toJson()['templateNameSnapshot'], 'Upper A');
  });
}
