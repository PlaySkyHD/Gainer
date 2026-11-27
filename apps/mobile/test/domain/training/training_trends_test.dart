import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/training_trends.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

/// Donnerstag; die laufende Woche beginnt Montag, 23. November 2026.
final _today = LocalDay(2026, 11, 26);

WorkoutTrendEntry _entry(
  LocalDay day, {
  int minutes = 60,
  int sets = 10,
  int reps = 80,
  double volume = 4000,
}) => WorkoutTrendEntry(
  day: day,
  duration: Duration(minutes: minutes),
  setCount: sets,
  repetitions: reps,
  volumeKg: volume,
);

DailyCheckIn _checkIn(String date, double kg) => DailyCheckIn(
  localDate: date,
  weightKg: kg,
  caloriesKcal: null,
  proteinGrams: null,
  carbohydrateGrams: null,
  fatGrams: null,
  steps: null,
  sleepMinutes: null,
  createdAtUtc: '2026-01-01T00:00:00Z',
  updatedAtUtc: '2026-01-01T00:00:00Z',
);

TrainingTrends _compute(
  List<WorkoutTrendEntry> entries, {
  TrendPeriod period = TrendPeriod.fourWeeks,
  List<DailyCheckIn> checkIns = const [],
}) => TrainingTrends.compute(
  entries,
  checkIns: checkIns,
  period: period,
  today: _today,
);

void main() {
  group('Zeiträume', () {
    test('4 W: vier Wochen ab Montag, die letzte enthält heute', () {
      final trends = _compute(const []);
      expect(trends.start, LocalDay(2026, 11, 2));
      expect(trends.bucketStarts, [
        LocalDay(2026, 11, 2),
        LocalDay(2026, 11, 9),
        LocalDay(2026, 11, 16),
        LocalDay(2026, 11, 23),
      ]);
    });

    test('3 M: 13 Wochen', () {
      final trends = _compute(const [], period: TrendPeriod.threeMonths);
      expect(trends.bucketStarts, hasLength(13));
      expect(trends.start, LocalDay(2026, 8, 31));
    });

    test('1 J: zwölf Monate inklusive des laufenden', () {
      final trends = _compute(const [], period: TrendPeriod.year);
      expect(trends.start, LocalDay(2025, 12, 1));
      expect(trends.bucketStarts, hasLength(12));
      expect(trends.bucketStarts.last, LocalDay(2026, 11, 1));
    });

    test('Alle: ab dem Monat des ersten Trainings oder Check-ins', () {
      final trends = _compute(
        [_entry(LocalDay(2026, 3, 14))],
        period: TrendPeriod.all,
        checkIns: [_checkIn('2026-01-20', 82)],
      );
      expect(trends.start, LocalDay(2026, 1, 1));
      expect(trends.bucketStarts, hasLength(11));
    });
  });

  test('Summen, Durchschnitte und Punkte je Woche', () {
    final trends = _compute([
      _entry(LocalDay(2026, 11, 3), minutes: 50, sets: 12, reps: 96),
      _entry(LocalDay(2026, 11, 5), minutes: 70, sets: 8, reps: 64),
      _entry(LocalDay(2026, 11, 24), minutes: 90, sets: 20, reps: 120),
      // Vor dem Zeitraum: zählt nicht.
      _entry(LocalDay(2026, 10, 30), minutes: 999, sets: 99, reps: 999),
    ]);

    expect(trends.workoutCount, 3);
    expect(trends.totalDuration, const Duration(minutes: 210));
    expect(trends.averageDuration, const Duration(minutes: 70));
    expect(trends.setCount, 40);
    expect(trends.repetitions, 280);
    expect(trends.repetitionsPerSet, 7);
    expect(trends.volumeKg, 12000);
    // Zeitraum 2. bis 26. November: 25 Tage.
    expect(trends.workoutsPerWeek, closeTo(3 / (25 / 7), 1e-9));
    expect(trends.series[TrendMetric.workoutsPerWeek], [2, 0, 0, 1]);
    expect(trends.series[TrendMetric.averageDuration], [60, null, null, 90]);
    expect(trends.series[TrendMetric.totalDuration], [120, 0, 0, 90]);
    expect(trends.series[TrendMetric.repetitionsPerSet], [8, null, null, 6]);
  });

  test('Körpergewicht: Durchschnitt je Woche, Lücken bleiben leer', () {
    final trends = _compute(
      const [],
      checkIns: [
        _checkIn('2026-11-03', 82),
        _checkIn('2026-11-04', 81),
        _checkIn('2026-11-25', 80.5),
        _checkIn('2026-10-20', 90),
        _checkIn('kein-datum', 70),
      ],
    );

    expect(trends.series[TrendMetric.bodyweight], [81.5, null, null, 80.5]);
    expect(trends.latestBodyweightKg, 80.5);
    expect(trends.isEmpty, isFalse);
  });

  test('Ohne Training und Check-in ist der Zeitraum leer', () {
    final trends = _compute([_entry(LocalDay(2026, 9, 1))]);
    expect(trends.isEmpty, isTrue);
    expect(trends.averageDuration, isNull);
    expect(trends.repetitionsPerSet, isNull);
  });

  test('Einträge aus Trainings übernehmen Dauer und Satzsummen', () {
    final workout = Workout(
      workoutId: 'w1',
      title: 'Push',
      startedAtUtc: DateTime.utc(2026, 11, 24, 17),
      endedAtUtc: DateTime.utc(2026, 11, 24, 18, 15),
      previousValueSource: PreviousValueSource.exercise,
      exercises: [
        WorkoutBlock(
          workoutExerciseId: 'we1',
          sourceExerciseId: 'bench',
          exerciseNameSnapshot: 'Bankdrücken',
          exerciseTypeSnapshot: ExerciseKind.strength,
          sets: [
            LoggedSet(
              setId: 's0',
              setType: SetType.warmup,
              weightKg: 40,
              repetitions: 10,
            ),
            LoggedSet(setId: 's1', weightKg: 80, repetitions: 8),
            LoggedSet(setId: 's2', weightKg: 80, repetitions: 6),
          ],
        ),
      ],
    );

    final entries = workoutTrendEntries(
      [workout],
      checkIns: const [],
      catalog: const [],
      includeWarmups: false,
      dayOf: (utc) => LocalDay.of(utc),
    );

    expect(entries, hasLength(1));
    expect(entries.single.day, LocalDay(2026, 11, 24));
    expect(entries.single.duration, const Duration(minutes: 75));
    expect(entries.single.setCount, 2);
    expect(entries.single.repetitions, 14);
    expect(entries.single.volumeKg, 1120);

    final withWarmups = workoutTrendEntries(
      [workout],
      checkIns: const [],
      catalog: const [],
      includeWarmups: true,
      dayOf: (utc) => LocalDay.of(utc),
    );
    expect(withWarmups.single.setCount, 3);
    expect(withWarmups.single.volumeKg, 1520);
  });
}
