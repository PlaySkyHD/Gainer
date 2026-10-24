import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_heatmap.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';

// Samstag, 24. Oktober 2026.
final _today = LocalDay(2026, 10, 24);

/// Feste Zeitzone UTC+2, unabhängig von der Zeitzone des Testrechners.
LocalDay _utcPlus2(DateTime utc) =>
    LocalDay.of(utc.toUtc().add(const Duration(hours: 2)));

/// Einheit ab [hour] Uhr UTC am Tag [day] mit [minutes] Minuten.
TrainingInterval _session(LocalDay day, int minutes, {int hour = 10}) {
  final start = DateTime.utc(day.year, day.month, day.day, hour);
  return (
    startedAtUtc: start,
    endedAtUtc: start.add(Duration(minutes: minutes)),
  );
}

TrainingHeatmap _build(List<TrainingInterval> sessions) =>
    buildTrainingHeatmap(sessions, today: _today, dayOf: _utcPlus2);

TrainingHeatmapDay _dayOf(TrainingHeatmap heatmap, LocalDay date) {
  final cell = heatmap.cellOf(date)!;
  return heatmap.dayAt(cell.week, cell.weekday)!;
}

void main() {
  group('quartiles', () {
    test('interpoliert linear zwischen den Werten', () {
      expect(quartiles([40, 10, 30, 20]), [17.5, 25, 32.5]);
    });

    test('ein Wert ergibt drei gleiche Quartile', () {
      expect(quartiles([30]), [30, 30, 30]);
    });

    test('ohne Werte leer', () {
      expect(quartiles(const []), isEmpty);
    });
  });

  group('heatmapLevel', () {
    test('Stufen 1–4 aus den Quartilen', () {
      final bounds = heatmapBounds([10, 20, 30, 40]);
      expect(
        [
          for (final minutes in [10, 20, 30, 40]) heatmapLevel(minutes, bounds),
        ],
        [1, 2, 3, 4],
      );
    });

    test('alle Tage gleich lang ergeben überall Stufe 4', () {
      final bounds = heatmapBounds([30, 30, 30]);
      expect(bounds, isEmpty);
      expect(heatmapLevel(30, bounds), 4);
    });

    test('ein langer Tag hebt sich von vielen gleichen ab', () {
      final bounds = heatmapBounds([30, 30, 30, 30, 90]);
      expect(heatmapLevel(30, bounds), 1);
      expect(heatmapLevel(90, bounds), 4);
    });
  });

  group('buildTrainingHeatmap', () {
    test('Zeitraum: zwölf Monate bis heute in Wochen von Montag an', () {
      final heatmap = _build(const []);

      expect(heatmap.start, LocalDay(2025, 10, 25));
      expect(heatmap.firstMonday, LocalDay(2025, 10, 20));
      expect(heatmap.firstMonday.weekday, DateTime.monday);
      expect(heatmap.weeks, hasLength(53));
      expect(heatmap.weeks.every((week) => week.length == 7), isTrue);
      // Vor dem Start und nach heute gibt es keine Tage.
      expect(heatmap.dayAt(0, 0), isNull);
      expect(heatmap.dayAt(0, 4), isNull);
      expect(heatmap.dayAt(0, 5)!.date, heatmap.start);
      expect(heatmap.dayAt(52, 5)!.date, _today);
      expect(heatmap.dayAt(52, 6), isNull);
      expect(heatmap.dayAt(53, 0), isNull);
      expect(heatmap.dayAt(0, 7), isNull);
      expect(heatmap.dayAt(-1, 0), isNull);
    });

    test('Tage ohne Training haben Stufe 0 und zählen nicht', () {
      final heatmap = _build([_session(LocalDay(2026, 10, 20), 45)]);

      expect(heatmap.trainingDays, 1);
      final empty = _dayOf(heatmap, LocalDay(2026, 10, 19));
      expect(empty.minutes, 0);
      expect(empty.level, 0);
      expect(empty.hasTraining, isFalse);
      final trained = _dayOf(heatmap, LocalDay(2026, 10, 20));
      expect(trained.minutes, 45);
      expect(trained.level, 4);
      expect(trained.hasTraining, isTrue);
    });

    test('Kraft und Cardio am selben Tag werden addiert', () {
      final day = LocalDay(2026, 10, 14);
      final heatmap = _build([
        _session(day, 60, hour: 8),
        _session(day, 25, hour: 16),
        _session(LocalDay(2026, 10, 15), 30),
      ]);

      expect(heatmap.trainingDays, 2);
      expect(_dayOf(heatmap, day).minutes, 85);
      expect(_dayOf(heatmap, day).level, greaterThan(1));
      expect(_dayOf(heatmap, LocalDay(2026, 10, 15)).level, 1);
    });

    test('Quartile verteilen die Tage mit Training auf die Stufen', () {
      final heatmap = _build([
        _session(LocalDay(2026, 10, 1), 10),
        _session(LocalDay(2026, 10, 2), 20),
        _session(LocalDay(2026, 10, 3), 30),
        _session(LocalDay(2026, 10, 4), 40),
      ]);

      expect(
        [
          for (var day = 1; day <= 4; day++)
            _dayOf(heatmap, LocalDay(2026, 10, day)).level,
        ],
        [1, 2, 3, 4],
      );
    });

    test('alle Tage gleich lang ergeben Stufe 4', () {
      final heatmap = _build([
        for (var day = 1; day <= 5; day++) _session(LocalDay(2026, 9, day), 30),
      ]);

      expect(heatmap.trainingDays, 5);
      for (var day = 1; day <= 5; day++) {
        expect(_dayOf(heatmap, LocalDay(2026, 9, day)).level, 4);
      }
    });

    test('lokaler Tag zählt, nicht der UTC-Tag', () {
      // 22:30 UTC am 20. ist 00:30 Uhr am 21. in UTC+2.
      final heatmap = _build([
        (
          startedAtUtc: DateTime.utc(2026, 10, 20, 22, 30),
          endedAtUtc: DateTime.utc(2026, 10, 20, 23, 30),
        ),
      ]);

      expect(_dayOf(heatmap, LocalDay(2026, 10, 20)).minutes, 0);
      expect(_dayOf(heatmap, LocalDay(2026, 10, 21)).minutes, 60);
    });

    test('Einheit über Mitternacht zählt ganz für den Starttag', () {
      // 23:30 bis 00:30 Uhr in UTC+2.
      final heatmap = _build([
        (
          startedAtUtc: DateTime.utc(2026, 10, 10, 21, 30),
          endedAtUtc: DateTime.utc(2026, 10, 10, 22, 30),
        ),
      ]);

      expect(heatmap.trainingDays, 1);
      expect(_dayOf(heatmap, LocalDay(2026, 10, 10)).minutes, 60);
      expect(_dayOf(heatmap, LocalDay(2026, 10, 11)).minutes, 0);
    });

    test('Einheiten außerhalb des Zeitraums entfallen', () {
      final heatmap = _build([
        _session(LocalDay(2025, 10, 24), 30),
        _session(LocalDay(2025, 10, 25), 30),
        _session(LocalDay(2026, 10, 25), 30),
      ]);

      expect(heatmap.trainingDays, 1);
      expect(heatmap.cellOf(LocalDay(2025, 10, 24)), isNull);
      expect(heatmap.cellOf(LocalDay(2026, 10, 25)), isNull);
      expect(heatmap.cellOf(LocalDay(2025, 10, 25)), (week: 0, weekday: 5));
    });

    test('Ende vor Start zählt als Trainingstag ohne Minuten', () {
      final start = DateTime.utc(2026, 10, 5, 10);
      final heatmap = _build([
        (
          startedAtUtc: start,
          endedAtUtc: start.subtract(const Duration(minutes: 5)),
        ),
      ]);

      final day = _dayOf(heatmap, LocalDay(2026, 10, 5));
      expect(heatmap.trainingDays, 1);
      expect(day.minutes, 0);
      expect(day.level, 4);
    });

    test('Bereich und Datum je Kästchen', () {
      final heatmap = _build(const []);

      expect(heatmap.contains(heatmap.start), isTrue);
      expect(heatmap.contains(_today), isTrue);
      expect(heatmap.contains(LocalDay(2025, 10, 24)), isFalse);
      expect(heatmap.contains(LocalDay(2026, 10, 25)), isFalse);
      expect(heatmap.dateAt(0, 0), heatmap.firstMonday);
      expect(heatmap.dateAt(52, 5), _today);
      expect(heatmap.dayOn(_today)!.date, _today);
      expect(heatmap.dayOn(LocalDay(2026, 10, 25)), isNull);
      expect(heatmap.days, hasLength(365));
      expect(heatmap.days.first.date, heatmap.start);
      expect(heatmap.days.last.date, _today);
    });

    test('nächstgelegener Tag, auch ohne Training', () {
      final heatmap = _build([_session(LocalDay(2026, 10, 20), 45)]);

      // Mitte der Spalte 52, Zeile 1: Dienstag, 20. Oktober.
      expect(heatmap.nearestDay(52.5, 1.5)!.date, LocalDay(2026, 10, 20));
      // Knapp daneben zählt das nähere Kästchen.
      expect(heatmap.nearestDay(52.9, 2.1)!.date, LocalDay(2026, 10, 21));
      // Rechts neben dem Raster: der nächste vorhandene Tag.
      expect(heatmap.nearestDay(60, 5.5)!.date, _today);
      // Vor dem Start (Spalte 0, Montag) liegt der erste Tag am nächsten.
      expect(heatmap.nearestDay(0.5, 0.5)!.date, LocalDay(2025, 10, 27));
      expect(heatmap.nearestDay(-3, 5.5)!.date, heatmap.start);
    });

    test('ohne Tage gibt es keinen nächstgelegenen', () {
      final empty = TrainingHeatmap(
        start: _today,
        today: _today,
        weeks: const [],
        trainingDays: 0,
      );
      expect(empty.nearestDay(0, 0), isNull);
    });

    test('nächster und voriger Trainingstag', () {
      final heatmap = _build([
        _session(LocalDay(2026, 3, 2), 30),
        _session(LocalDay(2026, 10, 1), 30),
        _session(LocalDay(2026, 10, 20), 30),
      ]);

      expect(heatmap.nextTrainingDay(null)!.date, LocalDay(2026, 3, 2));
      expect(heatmap.previousTrainingDay(null)!.date, LocalDay(2026, 10, 20));
      expect(
        heatmap.nextTrainingDay(LocalDay(2026, 3, 2))!.date,
        LocalDay(2026, 10, 1),
      );
      expect(
        heatmap.previousTrainingDay(LocalDay(2026, 10, 5))!.date,
        LocalDay(2026, 10, 1),
      );
      expect(heatmap.nextTrainingDay(LocalDay(2026, 10, 20)), isNull);
      expect(heatmap.previousTrainingDay(LocalDay(2026, 3, 2)), isNull);
    });

    test('Standard nutzt die Gerätezeitzone', () {
      final local = DateTime(2026, 10, 22, 18);
      final heatmap = buildTrainingHeatmap([
        (
          startedAtUtc: local.toUtc(),
          endedAtUtc: local.add(const Duration(minutes: 50)).toUtc(),
        ),
      ], today: _today);

      expect(_dayOf(heatmap, LocalDay(2026, 10, 22)).minutes, 50);
    });
  });
}
