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

/// Summen je gezähltem Training ([isCountedWorkout]) mit denselben Formeln
/// wie Rekorde und Übungsstatistik.
List<WorkoutTrendEntry> workoutTrendEntries(
  List<Workout> workouts, {
  required List<DailyCheckIn> checkIns,
  required List<CatalogExercise> catalog,
  required bool includeWarmups,
  LocalDay Function(DateTime utc) dayOf = localDayOfUtc,
}) {
  return [
    for (final workout in workouts)
      if (workout.endedAtUtc case final ended? when isCountedWorkout(workout))
        () {
          final stats = workoutExerciseStats(
            workout,
            checkIns: checkIns,
            catalog: catalog,
            localDayOf: (utc) => dayOf(utc).toIso(),
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
    final buckets = _Buckets(start, today, _bucketStarts(period, start, today));
    final sums = _WorkoutSums(buckets, entries);
    final body = _WeightSums(buckets, weights);
    final workoutCount = sums.workoutCount;
    final weeks = (start.daysUntil(today) + 1) / 7;
    return TrainingTrends(
      period: period,
      start: start,
      today: today,
      bucketStarts: buckets.starts,
      workoutCount: workoutCount,
      workoutsPerWeek: workoutCount / weeks,
      averageDuration: workoutCount == 0
          ? null
          : Duration(seconds: sums.totalDuration.inSeconds ~/ workoutCount),
      totalDuration: sums.totalDuration,
      volumeKg: _sum(sums.volume),
      setCount: _sum(sums.sets).toInt(),
      repetitions: _sum(sums.reps).toInt(),
      repetitionsPerSet: _ratio(_sum(sums.reps), _sum(sums.sets)),
      latestBodyweightKg: body.latestKg,
      series: {
        TrendMetric.workoutsPerWeek: sums.workouts,
        TrendMetric.averageDuration: _ratios(sums.minutes, sums.workouts),
        TrendMetric.totalDuration: sums.minutes,
        TrendMetric.volume: sums.volume,
        TrendMetric.sets: sums.sets,
        TrendMetric.repetitions: sums.reps,
        TrendMetric.repetitionsPerSet: _ratios(sums.reps, sums.sets),
        TrendMetric.bodyweight: _ratios(body.sums, body.counts),
      },
    );
  }

  static double _sum(List<double> values) =>
      values.fold<double>(0, (sum, value) => sum + value);

  /// Quotient oder `null`, wenn der Nenner 0 ist (keine Daten).
  static double? _ratio(double value, double count) =>
      count == 0 ? null : value / count;

  static List<double?> _ratios(List<double> values, List<double> counts) => [
    for (var i = 0; i < values.length; i++) _ratio(values[i], counts[i]),
  ];

  static LocalDay? _tryParse(String value) {
    try {
      return LocalDay.parse(value);
    } on FormatException {
      return null;
    }
  }

  static LocalDay _monday(LocalDay day) => day.addDays(1 - day.weekday);

  /// Erster Tag eines Zeitraums, der nicht von den Daten abhängt; `null` für
  /// [TrendPeriod.all].
  static LocalDay? fixedStart(TrendPeriod period, LocalDay today) =>
      switch (period) {
        TrendPeriod.fourWeeks => _monday(today).addDays(-7 * 3),
        TrendPeriod.threeMonths => _monday(today).addDays(-7 * 12),
        TrendPeriod.year => LocalDay(today.year, today.month - 11, 1),
        TrendPeriod.all => null,
      };

  static LocalDay _periodStart(
    TrendPeriod period,
    LocalDay today,
    List<WorkoutTrendEntry> entries,
    List<(LocalDay, double)> weights,
  ) {
    switch (period) {
      case TrendPeriod.fourWeeks:
      case TrendPeriod.threeMonths:
      case TrendPeriod.year:
        return fixedStart(period, today)!;
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

/// Abschnitte eines Zeitraums und die Zuordnung eines Tages.
class _Buckets {
  _Buckets(this.start, this.today, this.starts);

  final LocalDay start;
  final LocalDay today;
  final List<LocalDay> starts;

  int get length => starts.length;

  bool contains(LocalDay day) => !day.isBefore(start) && !day.isAfter(today);

  int indexOf(LocalDay day) {
    var index = starts.length - 1;
    while (index > 0 && day.isBefore(starts[index])) {
      index--;
    }
    return index;
  }
}

/// Trainingssummen je Abschnitt.
class _WorkoutSums {
  _WorkoutSums(_Buckets buckets, List<WorkoutTrendEntry> entries)
    : workouts = List.filled(buckets.length, 0),
      minutes = List.filled(buckets.length, 0),
      volume = List.filled(buckets.length, 0),
      sets = List.filled(buckets.length, 0),
      reps = List.filled(buckets.length, 0) {
    for (final entry in entries) {
      if (buckets.contains(entry.day)) _add(buckets.indexOf(entry.day), entry);
    }
  }

  final List<double> workouts;
  final List<double> minutes;
  final List<double> volume;
  final List<double> sets;
  final List<double> reps;
  var totalDuration = Duration.zero;
  var workoutCount = 0;

  void _add(int index, WorkoutTrendEntry entry) {
    workouts[index]++;
    minutes[index] += entry.duration.inSeconds / 60;
    volume[index] += entry.volumeKg;
    sets[index] += entry.setCount;
    reps[index] += entry.repetitions;
    totalDuration += entry.duration;
    workoutCount++;
  }
}

/// Check-in-Gewichte je Abschnitt und der jüngste im Zeitraum.
class _WeightSums {
  _WeightSums(_Buckets buckets, List<(LocalDay, double)> weights)
    : sums = List.filled(buckets.length, 0),
      counts = List.filled(buckets.length, 0) {
    for (final (day, kg) in weights) {
      if (buckets.contains(day)) _add(buckets.indexOf(day), day, kg);
    }
  }

  final List<double> sums;
  final List<double> counts;
  LocalDay? _latestDay;
  double? latestKg;

  void _add(int index, LocalDay day, double kg) {
    sums[index] += kg;
    counts[index]++;
    final latest = _latestDay;
    if (latest == null || !day.isBefore(latest)) {
      _latestDay = day;
      latestKg = kg;
    }
  }
}
