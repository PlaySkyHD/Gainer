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
    '${local.day}. ${_shortMonths[local.month - 1]}';

/// Kurzer Wochentag wie im Datums-Badge: „Do“.
String formatWeekdayShort(DateTime local) => _weekdays[local.weekday - 1];

String formatMonthTitle(DateTime local) =>
    '${_months[local.month - 1]} ${local.year}';

String formatClockTime(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

/// Dauer in ganzen Minuten: „129 min“.
String formatDurationMinutes(Duration duration) => '${duration.inMinutes} min';

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

/// Ein Monat im Tagebuch mit seinen Trainings, neueste zuerst.
final class DiaryMonth {
  const DiaryMonth({
    required this.year,
    required this.month,
    required this.workouts,
  });

  final int year;
  final int month;
  final List<Workout> workouts;
}

/// Gruppiert nach lokalem Monat. Die Reihenfolge der Eingabe bleibt erhalten.
List<DiaryMonth> groupDiaryByMonth(List<Workout> workouts) {
  final groups = <DiaryMonth>[];
  for (final workout in workouts) {
    final local = workout.startedAtUtc.toLocal();
    final last = groups.isEmpty ? null : groups.last;
    if (last != null && last.year == local.year && last.month == local.month) {
      last.workouts.add(workout);
      continue;
    }
    groups.add(
      DiaryMonth(year: local.year, month: local.month, workouts: [workout]),
    );
  }
  return groups;
}
