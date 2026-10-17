import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_statistics.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

const _bench = CatalogExercise(
  id: 'base-bench',
  name: 'Bankdrücken',
  exerciseType: ExerciseKind.strength,
  isBase: true,
);

String _utcDay(DateTime instant) => formatCalendarDay(instant.toUtc());

Workout _workout(
  String id, {
  required DateTime startedAt,
  DateTime? endedAt,
  DateTime? deletedAt,
  List<LoggedSet> sets = const [],
}) => Workout(
  workoutId: id,
  title: 'Brust',
  startedAtUtc: startedAt,
  endedAtUtc: endedAt,
  deletedAtUtc: deletedAt,
  previousValueSource: PreviousValueSource.exercise,
  exercises: [
    WorkoutBlock(
      workoutExerciseId: '$id-bench',
      sourceExerciseId: _bench.id,
      exerciseNameSnapshot: _bench.name,
      exerciseTypeSnapshot: ExerciseKind.strength,
      sets: sets,
    ),
  ],
);

LoggedSet _set(String id, double kg, int reps, {SetType? type}) => LoggedSet(
  setId: id,
  setType: type ?? SetType.normal,
  weightKg: kg,
  repetitions: reps,
);

void main() {
  final start = DateTime.utc(2026, 10, 15, 8);

  group('Zusammenfassung', () {
    test('nennt Dauer, Sätze, Wiederholungen, Volumen und besten Satz', () {
      final workout = _workout(
        'w1',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 45)),
        sets: [_set('a', 50, 10), _set('b', 60, 5)],
      );

      final summary = summarizeTraining(
        workout,
        history: [workout],
        checkIns: const [],
        catalog: const [_bench],
      );

      expect(summary.duration, const Duration(minutes: 45));
      expect(summary.setCount, 2);
      expect(summary.totalRepetitions, 15);
      expect(summary.volumeKg, 800);
      expect(summary.bestSets.single.sourceExerciseId, _bench.id);
      expect(summary.bestSets.single.set.effectiveWeightKg, 60);
      expect(summary.bestSets.single.set.repetitions, 5);
    });

    test('Aufwärmsätze fehlen in Anzahl, Volumen und bestem Satz', () {
      final workout = _workout(
        'w1',
        startedAt: start,
        endedAt: start.add(const Duration(hours: 1)),
        sets: [
          _set('warm', 100, 5, type: SetType.warmup),
          _set('a', 50, 10),
        ],
      );

      final summary = summarizeTraining(
        workout,
        history: [workout],
        checkIns: const [],
        catalog: const [_bench],
      );

      expect(summary.setCount, 1);
      expect(summary.volumeKg, 500);
      expect(summary.bestSets.single.set.effectiveWeightKg, 50);
    });

    test('gleicher Wert wie in der Historie ist kein neuer Rekord', () {
      final previous = _workout(
        'w0',
        startedAt: DateTime.utc(2026, 10, 1, 8),
        endedAt: DateTime.utc(2026, 10, 1, 9),
        sets: [_set('p', 100, 5)],
      );
      final current = _workout(
        'w1',
        startedAt: start,
        endedAt: start.add(const Duration(hours: 1)),
        sets: [_set('c', 100, 5)],
      );

      final summary = summarizeTraining(
        current,
        history: [previous, current],
        checkIns: const [],
        catalog: const [_bench],
      );

      expect(summary.newRecords, isEmpty);
    });

    test('übertroffene Werte erscheinen als neue Rekorde', () {
      final previous = _workout(
        'w0',
        startedAt: DateTime.utc(2026, 10, 1, 8),
        endedAt: DateTime.utc(2026, 10, 1, 9),
        sets: [_set('p', 100, 5)],
      );
      final current = _workout(
        'w1',
        startedAt: start,
        endedAt: start.add(const Duration(hours: 1)),
        sets: [_set('c', 105, 6)],
      );

      final summary = summarizeTraining(
        current,
        history: [previous, current],
        checkIns: const [],
        catalog: const [_bench],
      );

      expect(
        {for (final record in summary.newRecords) record.kind},
        {
          RecordKind.maxWeight,
          RecordKind.estimatedOneRepMax,
          RecordKind.volume,
          RecordKind.maxRepetitions,
        },
      );
    });

    test('laufende Trainings können nicht zusammengefasst werden', () {
      final active = _workout('w1', startedAt: start, sets: [_set('a', 50, 5)]);

      expect(
        () => summarizeTraining(
          active,
          history: [active],
          checkIns: const [],
          catalog: const [_bench],
        ),
        throwsArgumentError,
      );
    });
  });

  group('Zähler „n. Training · m. diese Woche“', () {
    // Mittwoch 14.10.2026; die Woche läuft von Montag 12.10. bis Sonntag 18.10.
    final now = DateTime.utc(2026, 10, 14, 12);

    test('zählt beendete Trainings und die der laufenden Woche', () {
      final workouts = [
        _workout(
          'sonntag-vorwoche',
          startedAt: DateTime.utc(2026, 10, 11, 20),
          endedAt: DateTime.utc(2026, 10, 11, 21),
        ),
        _workout(
          'montag',
          startedAt: DateTime.utc(2026, 10, 12, 8),
          endedAt: DateTime.utc(2026, 10, 12, 9),
        ),
        _workout(
          'sonntag',
          startedAt: DateTime.utc(2026, 10, 18, 10),
          endedAt: DateTime.utc(2026, 10, 18, 11),
        ),
        _workout(
          'naechste-woche',
          startedAt: DateTime.utc(2026, 10, 19, 8),
          endedAt: DateTime.utc(2026, 10, 19, 9),
        ),
        _workout('laufend', startedAt: DateTime.utc(2026, 10, 13, 8)),
        _workout(
          'geloescht',
          startedAt: DateTime.utc(2026, 10, 13, 8),
          endedAt: DateTime.utc(2026, 10, 13, 9),
          deletedAt: DateTime.utc(2026, 10, 13, 10),
        ),
      ];

      final counts = workoutCounts(workouts, now: now, localDayOf: _utcDay);

      expect(counts.total, 4);
      expect(counts.thisWeek, 2);
    });

    test('Sonntag um 23:30 UTC zählt noch zur laufenden Woche', () {
      final workouts = [
        _workout(
          'sonntag-abend',
          startedAt: DateTime.utc(2026, 10, 18, 22),
          endedAt: DateTime.utc(2026, 10, 18, 23),
        ),
      ];

      final counts = workoutCounts(
        workouts,
        now: DateTime.utc(2026, 10, 18, 23, 30),
        localDayOf: _utcDay,
      );

      expect(counts.thisWeek, 1);
    });
  });

  group('effektives Gewicht', () {
    test('assistiert ergibt nie weniger als 0 kg', () {
      expect(
        effectiveWeightKg(
          kind: ExerciseKind.assisted,
          weightKg: 90,
          bodyweightFactor: 1,
          weightFactor: 1,
          bodyweightKg: 80,
        ),
        0,
      );
    });
  });

  group('Check-in-Auswahl', () {
    final workout = _workout('w1', startedAt: start, endedAt: start);

    test('ohne Check-in am oder vor dem Starttag fehlt das Körpergewicht', () {
      final checkIns = [
        DailyCheckIn(
          localDate: '2026-10-16',
          weightKg: 80,
          caloriesKcal: null,
          proteinGrams: null,
          carbohydrateGrams: null,
          fatGrams: null,
          steps: null,
          sleepMinutes: null,
          createdAtUtc: '2026-10-16T00:00:00Z',
          updatedAtUtc: '2026-10-16T00:00:00Z',
        ),
      ];

      expect(
        bodyweightForWorkout(workout, checkIns, localDayOf: _utcDay),
        isNull,
      );
    });
  });

  group('Kennzahlen je Training und Übung', () {
    test('fasst Blöcke derselben Übung je Training zusammen und sortiert chronologisch', () {
      final later = _workout(
        'w2',
        startedAt: start.add(const Duration(days: 2)),
        endedAt: start.add(const Duration(days: 2, hours: 1)),
        sets: [_set('c', 80, 6)],
      );
      final earlier = _workout(
        'w1',
        startedAt: start,
        endedAt: start.add(const Duration(hours: 1)),
        sets: [
          _set('a', 50, 10),
          _set('b', 60, 5, type: SetType.warmup),
        ],
      );
      final openWorkout = _workout(
        'w3',
        startedAt: start.add(const Duration(days: 3)),
        sets: [_set('d', 90, 1)],
      );

      final totals = exerciseTotalsPerWorkout(
        [later, earlier, openWorkout],
        checkIns: const [],
        catalog: const [_bench],
      );

      final bench = totals[_bench.id]!;
      expect([for (final t in bench) t.workoutId], ['w1', 'w2']);
      final first = bench.first;
      expect(first.exerciseName, 'Bankdrücken');
      expect(
        first.setCount,
        1,
        reason: 'Aufwärmsatz ist standardmäßig ausgeschlossen',
      );
      expect(first.volumeKg, 500);
      expect(first.maxWeightKg, 50);
      expect(first.estimatedOneRepMaxKg, closeTo(66.67, 0.01));
      expect(first.maxRepetitions, 10);
    });

    test('Rekorde leiten sich aus denselben Kennzahlen ab', () {
      final workout = _workout(
        'w1',
        startedAt: start,
        endedAt: start.add(const Duration(hours: 1)),
        sets: [_set('a', 100, 8)],
      );
      const catalog = [_bench];
      final totals = exerciseTotalsPerWorkout(
        [workout],
        checkIns: const [],
        catalog: catalog,
      )[_bench.id]!.single;
      final records = exerciseRecords(
        [workout],
        checkIns: const [],
        catalog: catalog,
      )[_bench.id]!;

      expect(records.maxWeight.single.value, totals.maxWeightKg);
      expect(
        records.estimatedOneRepMax.single.value,
        totals.estimatedOneRepMaxKg,
      );
      expect(records.volume.single.value, totals.volumeKg);
      expect(records.repRecords[8], 100);
    });
  });
}
