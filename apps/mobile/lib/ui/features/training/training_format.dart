import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/training/workout_model.dart';

const _shortMonths = [
  'Jan.',
  'Feb.',
  'März',
  'Apr.',
  'Mai',
  'Juni',
  'Juli',
  'Aug.',
  'Sept.',
  'Okt.',
  'Nov.',
  'Dez.',
];

const _months = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Datum wie im Trainingskopf: „16. Okt.“.
String formatShortDate(DateTime local) =>
    '${local.day}. ${formatMonthShort(local.month)}';

/// Kurzer Wochentag wie im Datums-Badge: „Do“.
String formatWeekdayShort(DateTime local) => _weekdays[local.weekday - 1];

String formatMonthTitle(DateTime local) =>
    '${formatMonthName(local.month)} ${local.year}';

/// Ausgeschriebener Monat: 10 → „Oktober“.
String formatMonthName(int month) => _months[month - 1];

/// Abgekürzter Monat im Datum: 10 → „Okt.“, 3 → „März“.
String formatMonthShort(int month) => _shortMonths[month - 1];

/// Monat in drei Buchstaben ohne Punkt für knappe Beschriftungen wie
/// Achsen: 10 → „Okt“, 3 → „Mär“.
String formatMonthLabel(int month) => formatMonthName(month).substring(0, 3);

String formatClockTime(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

/// Dauer auf die nächste ganze Minute gerundet: „129 min“ (80 s → „1 min“,
/// 100 s → „2 min“).
String formatDurationMinutes(Duration duration) =>
    '${(duration.inSeconds + 30) ~/ 60} min';

/// Verstrichene Zeit als „mm:ss“, ab einer Stunde als „h:mm:ss“.
String formatElapsed(Duration elapsed) {
  final total = elapsed.isNegative ? Duration.zero : elapsed;
  final hours = total.inHours;
  final minutes = (total.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (total.inSeconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String formatTrainingCount(int count) =>
    count == 1 ? '1 Training' : '$count Trainings';

/// Eintrag im Tagebuch: Krafttraining oder Cardio-Einheit.
sealed class DiaryItem {
  const DiaryItem();

  DateTime get startedAtUtc;
}

final class WorkoutDiaryItem extends DiaryItem {
  const WorkoutDiaryItem(this.workout);

  final Workout workout;

  @override
  DateTime get startedAtUtc => workout.startedAtUtc;
}

final class CardioDiaryItem extends DiaryItem {
  const CardioDiaryItem(this.session);

  final CardioSession session;

  @override
  DateTime get startedAtUtc => session.startedAtUtc;
}

/// Ein Monat im Tagebuch mit seinen Einträgen, neueste zuerst.
final class DiaryMonth {
  const DiaryMonth({
    required this.year,
    required this.month,
    required this.items,
  });

  final int year;
  final int month;
  final List<DiaryItem> items;
}

/// Führt Trainings und Cardio-Einheiten nach Startzeit zusammen, neueste zuerst.
List<DiaryItem> mergeDiaryItems(
  List<Workout> workouts,
  List<CardioSession> cardio,
) {
  final items = <DiaryItem>[
    for (final workout in workouts) WorkoutDiaryItem(workout),
    for (final session in cardio) CardioDiaryItem(session),
  ]..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
  return items;
}

/// Gruppiert nach lokalem Monat. Die Reihenfolge der Eingabe bleibt erhalten.
List<DiaryMonth> groupDiaryByMonth(List<DiaryItem> items) {
  final groups = <DiaryMonth>[];
  for (final item in items) {
    final local = item.startedAtUtc.toLocal();
    final last = groups.isEmpty ? null : groups.last;
    if (last != null && last.year == local.year && last.month == local.month) {
      last.items.add(item);
      continue;
    }
    groups.add(DiaryMonth(year: local.year, month: local.month, items: [item]));
  }
  return groups;
}
