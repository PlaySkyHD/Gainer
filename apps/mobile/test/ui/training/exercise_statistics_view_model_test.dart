import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_statistics.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/exercise_statistics_view_model.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_view_model.dart';

import 'training_statistics_test_support.dart';
import 'training_test_support.dart';

void main() {
  late TrainingHarness harness;

  setUp(() async {
    harness = await TrainingHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<ExerciseStatisticsViewModel> loadExercise(
    String exerciseId, {
    DateTime? now,
  }) async {
    final model = ExerciseStatisticsViewModel(
      repository: harness.repository,
      exerciseId: exerciseId,
      clock: () => now ?? DateTime(2026, 10, 17),
    );
    await model.load();
    return model;
  }

  test('Kennzahlen stimmen mit den Funktionen der Domäne überein', () async {
    await seedSquatScenario(harness);
    final model = await loadExercise(kneeExerciseId);

    final inputs = await loadStatisticsInputs(harness.repository);
    final expected = exerciseRecords(
      inputs.workouts,
      checkIns: inputs.checkIns,
      catalog: inputs.catalog,
    )[kneeExerciseId]!;

    expect(model.records, isNotNull);
    expect(
      model.records!.maxWeight.map((event) => event.value),
      orderedEquals(expected.maxWeight.map((event) => event.value)),
    );
    expect(
      model.records!.estimatedOneRepMax.map((event) => event.value),
      orderedEquals(expected.estimatedOneRepMax.map((event) => event.value)),
    );
    expect(
      model.records!.volume.map((event) => event.value),
      orderedEquals(expected.volume.map((event) => event.value)),
    );
    expect(model.sessions, hasLength(3));
    expect(model.sessions.map((session) => session.volumeKg), [
      1600,
      550,
      1100,
    ]);
  });

  test(
    'Gleichstand ist kein Rekord, gelöschte und laufende Trainings fehlen',
    () async {
      await seedSquatScenario(harness);
      final model = await loadExercise(kneeExerciseId);
      final records = model.records!;

      // 110 kg × 5 aus Training 2 und 3 ergeben dasselbe 1RM, nur Training 2 zählt.
      expect(records.estimatedOneRepMax, hasLength(2));
      expect(records.estimatedOneRepMax.last.value, closeTo(128.33, 0.01));
      expect(records.maxWeight.map((event) => event.value), [100, 110]);
      expect(records.volume.map((event) => event.value), [1600]);
      // Das gelöschte 200 kg × 1 und das laufende 150 kg × 3 fließen nicht ein.
      expect(records.maxWeight.last.value, 110);
    },
  );

  test(
    'Wiederholungsrekorde: ein Satz zählt für niedrigere Wiederholungszahlen',
    () async {
      await seedSingleSquatSet(harness);
      final model = await loadExercise(kneeExerciseId);
      final repRecords = model.records!.repRecords;

      expect(repRecords[1], 100);
      expect(repRecords[3], 100);
      expect(repRecords[5], 100);
      expect(repRecords[8], 100);
      expect(repRecords[10], isNull);
      expect(repRecords[12], isNull);
    },
  );

  test(
    'Aufwärmsätze ändern die Satzanzahl nur mit eingeschaltetem Schalter',
    () async {
      await harness.seedWorkout(
        title: 'Schultern',
        start: DateTime(2026, 10, 2, 18).toUtc(),
        end: DateTime(2026, 10, 2, 19).toUtc(),
        blocks: [
          statBlock(
            exerciseId: pressExerciseId,
            name: 'Schulterdrücken',
            sets: [
              statSet('w', kg: 20, reps: 10, type: SetType.warmup),
              statSet('n', kg: 30, reps: 8),
            ],
          ),
        ],
      );
      final model = await loadExercise(pressExerciseId);
      expect(model.includeWarmups, isFalse);
      expect(model.sessions.single.setCount, 1);

      await model.setIncludeWarmups(true);
      expect(model.includeWarmups, isTrue);
      expect(model.sessions.single.setCount, 2);
      expect(await readIncludeWarmupSets(harness.store), isTrue);
    },
  );

  test('Fehlender Check-in markiert Körpergewichtsübungen', () async {
    await harness.seedWorkout(
      title: 'Push',
      start: DateTime(2026, 10, 15, 18).toUtc(),
      end: DateTime(2026, 10, 15, 19).toUtc(),
      blocks: [
        statBlock(
          exerciseId: pushupExerciseId,
          name: 'Liegestütz',
          kind: ExerciseKind.bodyweightOnly,
          sets: [statSet('p1', reps: 10)],
        ),
      ],
    );
    final missing = await loadExercise(pushupExerciseId);
    expect(missing.bodyweightMissing, isTrue);
    expect(missing.sessions.single.maxWeightKg, 0);

    await saveWeightCheckIn(harness, localDate: '2026-10-14', weightKg: 80);
    final withCheckIn = await loadExercise(pushupExerciseId);
    expect(withCheckIn.bodyweightMissing, isFalse);
    expect(withCheckIn.sessions.single.maxWeightKg, 80);
    expect(
      withCheckIn.records!.estimatedOneRepMax.single.value,
      closeTo(106.67, 0.01),
    );
  });

  test(
    'Trainingsliste nach zuletzt trainiert und nur gezählte Sätze',
    () async {
      await seedSquatScenario(harness);
      final inputs = await loadStatisticsInputs(harness.repository);
      final summaries = summarizeTrainedExercises(
        inputs,
        includeWarmups: false,
      );

      expect([for (final s in summaries) s.name], ['Kniebeuge', 'Bankdrücken']);
      expect(summaries.first.maxWeightKg, 110);
      expect(summaries.last.estimatedOneRepMaxKg, closeTo(70, 0.01));
    },
  );

  test('Zeitraum des Graphen filtert Trainings nach dem Startdatum', () async {
    await seedSquatScenario(harness);
    final model = await loadExercise(kneeExerciseId);
    expect(model.chartPoints, hasLength(3));

    model.selectPeriod(ChartPeriod.threeMonths);
    expect(model.chartPoints, hasLength(3));

    final later = await loadExercise(
      kneeExerciseId,
      now: DateTime(2027, 1, 10),
    );
    later.selectPeriod(ChartPeriod.threeMonths);
    expect(later.chartPoints, isEmpty);
    later.selectPeriod(ChartPeriod.oneYear);
    expect(later.chartPoints, hasLength(3));
    later.selectPeriod(ChartPeriod.all);
    expect(later.chartPoints, hasLength(3));
  });

  test('Verlaufswerte sind identisch zu exerciseTotalsPerWorkout', () async {
    await seedSquatScenario(harness);
    final model = await loadExercise(kneeExerciseId);
    final inputs = await loadStatisticsInputs(harness.repository);
    final expected = exerciseTotalsPerWorkout(
      inputs.workouts,
      checkIns: inputs.checkIns,
      catalog: inputs.catalog,
    )[kneeExerciseId]!;

    expect(model.sessions, hasLength(expected.length));
    for (var i = 0; i < expected.length; i++) {
      final session = model.sessions[i];
      expect(session.workoutId, expected[i].workoutId);
      expect(session.volumeKg, expected[i].volumeKg);
      expect(session.maxWeightKg, expected[i].maxWeightKg);
      expect(session.estimatedOneRepMaxKg, expected[i].estimatedOneRepMaxKg);
      expect(session.setCount, expected[i].setCount);
    }
    expect(model.exerciseName, expected.last.exerciseName);
  });
}
