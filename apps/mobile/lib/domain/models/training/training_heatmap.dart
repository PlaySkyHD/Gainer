import 'training_schedule.dart';

/// Eine Einheit (Krafttraining oder Cardio) mit Start und Ende in UTC.
typedef TrainingInterval = ({DateTime startedAtUtc, DateTime endedAtUtc});

/// Ein Tag der Heatmap mit Trainingsminuten und Stufe 0–4.
final class TrainingHeatmapDay {
  const TrainingHeatmapDay({
    required this.date,
    required this.minutes,
    required this.level,
  });

  final LocalDay date;
  final int minutes;

  /// 0 = kein Training, 1–4 nach den Quartilen der Tage mit Training.
  final int level;

  bool get hasTraining => level > 0;
}

/// Trainingstage der letzten 12 Monate bis einschließlich [today], in Wochen
/// von Montag bis Sonntag. Tage vor [start] oder nach [today] sind `null`.
final class TrainingHeatmap {
  const TrainingHeatmap({
    required this.start,
    required this.today,
    required this.weeks,
    required this.trainingDays,
  });

  /// Leerer Zeitraum der zwölf Monate bis [today]; Grundlage für
  /// [buildTrainingHeatmap], damit Start, Spalten und Bereich nur hier
  /// berechnet werden.
  TrainingHeatmap._span(this.today)
    : start = LocalDay(today.year - 1, today.month, today.day + 1),
      weeks = const [],
      trainingDays = 0;

  /// Erster Tag des Zeitraums: heute vor einem Jahr plus ein Tag.
  final LocalDay start;
  final LocalDay today;

  /// Spalten mit je sieben Tagen (Index 0 = Montag).
  final List<List<TrainingHeatmapDay?>> weeks;

  /// Anzahl der Tage mit mindestens einer Einheit.
  final int trainingDays;

  /// Montag der ersten Spalte.
  LocalDay get firstMonday => start.addDays(1 - start.weekday);

  /// Ob [date] im Zeitraum von [start] bis [today] liegt.
  bool contains(LocalDay date) => !date.isBefore(start) && !date.isAfter(today);

  /// Kalendertag an Spalte [week] und Zeile [weekday], auch außerhalb des
  /// Zeitraums.
  LocalDay dateAt(int week, int weekday) =>
      firstMonday.addDays(week * 7 + weekday);

  /// Tag an Spalte [week] und Zeile [weekday] (0 = Montag); `null` außerhalb.
  TrainingHeatmapDay? dayAt(int week, int weekday) {
    if (week < 0 || week >= weeks.length) return null;
    if (weekday < 0 || weekday > 6) return null;
    return weeks[week][weekday];
  }

  /// Spalte und Zeile von [date]; `null` außerhalb des Zeitraums.
  ({int week, int weekday})? cellOf(LocalDay date) {
    if (!contains(date)) return null;
    final offset = firstMonday.daysUntil(date);
    return (week: offset ~/ 7, weekday: offset % 7);
  }

  /// Tag zu [date]; `null` außerhalb des Zeitraums.
  TrainingHeatmapDay? dayOn(LocalDay date) {
    final cell = cellOf(date);
    return cell == null ? null : dayAt(cell.week, cell.weekday);
  }

  /// Alle Tage des Zeitraums in zeitlicher Reihenfolge.
  Iterable<TrainingHeatmapDay> get days =>
      weeks.expand((week) => week).nonNulls;

  /// Tag, dessen Kästchen dem Punkt am nächsten liegt. [week] und [weekday]
  /// sind Kästchenkoordinaten (Spalte 2,5 ist die Mitte der dritten Spalte).
  /// Auch Tage ohne Training kommen in Frage; `null` nur ohne Tage.
  TrainingHeatmapDay? nearestDay(double week, double weekday) {
    TrainingHeatmapDay? nearest;
    var best = double.infinity;
    for (var column = 0; column < weeks.length; column++) {
      for (var row = 0; row < 7; row++) {
        final day = weeks[column][row];
        if (day == null) continue;
        final dx = column + 0.5 - week;
        final dy = row + 0.5 - weekday;
        final distance = dx * dx + dy * dy;
        if (distance < best) {
          best = distance;
          nearest = day;
        }
      }
    }
    return nearest;
  }

  /// Erster Trainingstag nach [date]. Ohne [date] (keine Auswahl) der
  /// jüngste, damit beide Richtungen beim neuesten Training beginnen.
  TrainingHeatmapDay? nextTrainingDay(LocalDay? date) => date == null
      ? previousTrainingDay(null)
      : days
            .where((day) => day.hasTraining && day.date.isAfter(date))
            .firstOrNull;

  /// Letzter Trainingstag vor [date]; ohne [date] der jüngste.
  TrainingHeatmapDay? previousTrainingDay(LocalDay? date) => days
      .where(
        (day) => day.hasTraining && (date == null || day.date.isBefore(date)),
      )
      .lastOrNull;
}

/// Baut die Heatmap aus Kraft- und Cardio-Einheiten. Die Minuten einer
/// Einheit zählen ganz für ihren lokalen Starttag, wie im Kalender; auch über
/// Mitternacht. [dayOf] bestimmt den lokalen Tag eines UTC-Zeitpunkts.
TrainingHeatmap buildTrainingHeatmap(
  Iterable<TrainingInterval> sessions, {
  required LocalDay today,
  LocalDay Function(DateTime utc) dayOf = localDayOfUtc,
}) {
  final span = TrainingHeatmap._span(today);
  final seconds = <LocalDay, int>{};
  for (final session in sessions) {
    final day = dayOf(session.startedAtUtc);
    if (!span.contains(day)) continue;
    final duration = session.endedAtUtc.difference(session.startedAtUtc);
    seconds[day] =
        (seconds[day] ?? 0) + (duration.isNegative ? 0 : duration.inSeconds);
  }
  final minutes = {
    for (final entry in seconds.entries) entry.key: (entry.value / 60).round(),
  };
  final bounds = heatmapBounds(minutes.values);

  final weekCount = span.cellOf(today)!.week + 1;
  final weeks = [
    for (var week = 0; week < weekCount; week++)
      [
        for (var weekday = 0; weekday < 7; weekday++)
          _day(span, span.dateAt(week, weekday), minutes, bounds),
      ],
  ];
  return TrainingHeatmap(
    start: span.start,
    today: today,
    weeks: List.unmodifiable(weeks),
    trainingDays: minutes.length,
  );
}

TrainingHeatmapDay? _day(
  TrainingHeatmap span,
  LocalDay date,
  Map<LocalDay, int> minutes,
  List<double> bounds,
) {
  if (!span.contains(date)) return null;
  final value = minutes[date];
  return TrainingHeatmapDay(
    date: date,
    minutes: value ?? 0,
    level: value == null ? 0 : heatmapLevel(value, bounds),
  );
}

/// Erstes, zweites und drittes Quartil mit linearer Interpolation; leer ohne
/// Werte.
List<double> quartiles(Iterable<num> values) {
  final sorted = [for (final value in values) value.toDouble()]..sort();
  if (sorted.isEmpty) return const [];
  double at(double p) {
    final position = p * (sorted.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }

  return [at(0.25), at(0.5), at(0.75)];
}

/// Grenzen für [heatmapLevel]: die Quartile der Minuten aller Tage mit
/// Training. Sind alle Tage gleich lang, gibt es keinen Unterschied zu zeigen;
/// dann bleibt die Liste leer und jeder Trainingstag erhält Stufe 4.
List<double> heatmapBounds(Iterable<int> minutes) {
  return minutes.toSet().length <= 1 ? const [] : quartiles(minutes);
}

/// Stufe 1–4 eines Trainingstags: 1 plus die Zahl der Quartile, die [minutes]
/// übertrifft. Ohne Grenzen (alle Tage gleich lang) volle Stufe 4.
int heatmapLevel(int minutes, List<double> bounds) {
  if (bounds.isEmpty) return 4;
  return 1 + bounds.where((bound) => minutes > bound).length;
}
