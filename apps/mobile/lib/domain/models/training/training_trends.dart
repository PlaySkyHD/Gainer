import '../body/body_tracking.dart';
import 'exercise_catalog_model.dart';
import 'training_schedule.dart';
import 'training_statistics.dart';
import 'workout_model.dart';

/// Zeitraum der Verlaufskacheln im Statistikbereich.
enum TrendPeriod {
  fourWeeks('4 W'),
  threeMonths('3 M'),
  year('1 J'),
  all('Alle');

  const TrendPeriod(this.label);

  final String label;

  /// Wochenweise Punkte für kurze Zeiträume, sonst monatsweise.
  bool get weekly => this == fourWeeks || this == threeMonths;
}

/// Kennzahl einer Verlaufskachel.
enum TrendMetric {
  workoutsPerWeek,
  averageDuration,
  totalDuration,
  volume,
  sets,
  repetitions,
  repetitionsPerSet,
  bodyweight,
}

/// Summen eines beendeten Trainings für den Verlauf.
class WorkoutTrendEntry {
  const WorkoutTrendEntry({
    required this.day,
    required this.duration,
    required this.setCount,
    required this.repetitions,
    required this.volumeKg,
  });

  /// Lokaler Starttag.
  final LocalDay day;
  final Duration duration;
  final int setCount;
  final int repetitions;
  final double volumeKg;
}

/// Summen je beendetem Training mit denselben Formeln wie Rekorde und
/// Übungsstatistik. [workouts] sind die gezählten Trainings.
List<WorkoutTrendEntry> workoutTrendEntries(
  List<Workout> workouts, {
  required List<DailyCheckIn> checkIns,
  required List<CatalogExercise> catalog,
  required bool includeWarmups,
  LocalDay Function(DateTime utc) dayOf = localDayOfUtc,
}) {
  return [
    for (final workout in workouts)
      if (workout.endedAtUtc case final ended?
          when workout.deletedAtUtc == null)
        () {
          final stats = workoutExerciseStats(
            workout,
            checkIns: checkIns,
            catalog: catalog,
            includeWarmups: includeWarmups,
          );
          final duration = ended.difference(workout.startedAtUtc);
          return WorkoutTrendEntry(
            day: dayOf(workout.startedAtUtc),
            duration: duration.isNegative ? Duration.zero : duration,
            setCount: stats.fold(0, (sum, block) => sum + block.setCount),
            repetitions: stats.fold(
              0,
              (sum, block) => sum + block.totalRepetitions,
            ),
            volumeKg: stats.fold<double>(
              0,
              (sum, block) => sum + block.volumeKg,
            ),
          );
        }(),
  ];
}

/// Kennzahlen und Punkte der Verlaufskacheln für einen Zeitraum.
///
/// Jede Kachel hat einen Wert für den ganzen Zeitraum und einen Punkt je
/// Woche (4 W, 3 M) oder Monat (1 J, Alle). `null` heißt: in diesem
/// Abschnitt keine Daten, etwa kein Check-in; das ist kein Wert 0.
class TrainingTrends {
  const TrainingTrends({
    required this.period,
    required this.start,
    required this.today,
    required this.bucketStarts,
    required this.workoutCount,
    required this.workoutsPerWeek,
    required this.averageDuration,
    required this.totalDuration,
    required this.volumeKg,
    required this.setCount,
    required this.repetitions,
    required this.repetitionsPerSet,
    required this.latestBodyweightKg,
    required this.series,
  });

  final TrendPeriod period;

  /// Erster Tag des Zeitraums (Montag bzw. Monatserster).
  final LocalDay start;
  final LocalDay today;

  /// Erster Tag jedes Abschnitts, älteste zuerst; der letzte enthält heute.
  final List<LocalDay> bucketStarts;

  final int workoutCount;
  final double workoutsPerWeek;
  final Duration? averageDuration;
  final Duration totalDuration;
  final double volumeKg;
  final int setCount;
  final int repetitions;
  final double? repetitionsPerSet;

  /// Jüngster Check-in im Zeitraum.
  final double? latestBodyweightKg;

  /// Punkte je Abschnitt; Dauer in Minuten, Gewicht und Volumen in kg.
  final Map<TrendMetric, List<double?>> series;

  /// Ohne Training und Check-in im Zeitraum zeigt keine Kachel etwas.
  bool get isEmpty => workoutCount == 0 && latestBodyweightKg == null;

  static TrainingTrends compute(
    List<WorkoutTrendEntry> entries, {
    required List<DailyCheckIn> checkIns,
    required TrendPeriod period,
    required LocalDay today,
  }) {
    final weights = <(LocalDay, double)>[
      for (final checkIn in checkIns)
        if (_tryParse(checkIn.localDate) case final day?)
          (day, checkIn.weightKg),
    ];
    final start = _periodStart(period, today, entries, weights);
    final bucketStarts = _bucketStarts(period, start, today);
    int bucketOf(LocalDay day) {
      var index = bucketStarts.length - 1;
      while (index > 0 && day.isBefore(bucketStarts[index])) {
        index--;
      }
      return index;
    }

    bool inPeriod(LocalDay day) => !day.isBefore(start) && !day.isAfter(today);

    final count = bucketStarts.length;
    final workouts = List<int>.filled(count, 0);
    final minutes = List<double>.filled(count, 0);
    final volume = List<double>.filled(count, 0);
    final sets = List<int>.filled(count, 0);
    final reps = List<int>.filled(count, 0);
    var totalDuration = Duration.zero;
    var workoutCount = 0;
    for (final entry in entries) {
      if (!inPeriod(entry.day)) continue;
      final index = bucketOf(entry.day);
      workouts[index]++;
      minutes[index] += entry.duration.inSeconds / 60;
      volume[index] += entry.volumeKg;
      sets[index] += entry.setCount;
      reps[index] += entry.repetitions;
      totalDuration += entry.duration;
      workoutCount++;
    }

    final weightSums = List<double>.filled(count, 0);
    final weightCounts = List<int>.filled(count, 0);
    (LocalDay, double)? latest;
    for (final (day, kg) in weights) {
      if (!inPeriod(day)) continue;
      final index = bucketOf(day);
      weightSums[index] += kg;
      weightCounts[index]++;
      if (latest == null || !day.isBefore(latest.$1)) latest = (day, kg);
    }

    final setCount = sets.fold(0, (sum, value) => sum + value);
    final repetitions = reps.fold(0, (sum, value) => sum + value);
    final weeks = (start.daysUntil(today) + 1) / 7;
    return TrainingTrends(
      period: period,
      start: start,
      today: today,
      bucketStarts: bucketStarts,
      workoutCount: workoutCount,
      workoutsPerWeek: workoutCount / weeks,
      averageDuration: workoutCount == 0
          ? null
          : Duration(seconds: totalDuration.inSeconds ~/ workoutCount),
      totalDuration: totalDuration,
      volumeKg: volume.fold<double>(0, (sum, value) => sum + value),
      setCount: setCount,
      repetitions: repetitions,
      repetitionsPerSet: setCount == 0 ? null : repetitions / setCount,
      latestBodyweightKg: latest?.$2,
      series: {
        TrendMetric.workoutsPerWeek: [
          for (final value in workouts) value.toDouble(),
        ],
        TrendMetric.averageDuration: [
          for (var i = 0; i < count; i++)
            workouts[i] == 0 ? null : minutes[i] / workouts[i],
        ],
        TrendMetric.totalDuration: minutes,
        TrendMetric.volume: volume,
        TrendMetric.sets: [for (final value in sets) value.toDouble()],
        TrendMetric.repetitions: [for (final value in reps) value.toDouble()],
        TrendMetric.repetitionsPerSet: [
          for (var i = 0; i < count; i++)
            sets[i] == 0 ? null : reps[i] / sets[i],
        ],
        TrendMetric.bodyweight: [
          for (var i = 0; i < count; i++)
            weightCounts[i] == 0 ? null : weightSums[i] / weightCounts[i],
        ],
      },
    );
  }

  static LocalDay? _tryParse(String value) {
    try {
      return LocalDay.parse(value);
    } on FormatException {
      return null;
    }
  }

  static LocalDay _monday(LocalDay day) => day.addDays(1 - day.weekday);

  static LocalDay _periodStart(
    TrendPeriod period,
    LocalDay today,
    List<WorkoutTrendEntry> entries,
    List<(LocalDay, double)> weights,
  ) {
    switch (period) {
      case TrendPeriod.fourWeeks:
        return _monday(today).addDays(-7 * 3);
      case TrendPeriod.threeMonths:
        return _monday(today).addDays(-7 * 12);
      case TrendPeriod.year:
        return LocalDay(today.year, today.month - 11, 1);
      case TrendPeriod.all:
        var first = today;
        for (final entry in entries) {
          if (entry.day.isBefore(first)) first = entry.day;
        }
        for (final (day, _) in weights) {
          if (day.isBefore(first)) first = day;
        }
        return LocalDay(first.year, first.month, 1);
    }
  }

  static List<LocalDay> _bucketStarts(
    TrendPeriod period,
    LocalDay start,
    LocalDay today,
  ) {
    final starts = <LocalDay>[];
    if (period.weekly) {
      for (var day = start; !day.isAfter(today); day = day.addDays(7)) {
        starts.add(day);
      }
    } else {
      for (
        var day = start;
        !day.isAfter(today);
        day = LocalDay(day.year, day.month + 1, 1)
      ) {
        starts.add(day);
      }
    }
    return starts;
  }
}
