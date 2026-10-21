import '../../../domain/models/training/training_schedule.dart';

const _weekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _weekdayLong = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

/// „Mo“ … „So“.
String scheduleWeekdayShort(LocalDay day) => _weekdayShort[day.weekday - 1];

/// „Montag“ … „Sonntag“ für Slot [index] der festen Tage (0 = Montag).
String scheduleWeekdayLong(int index) => _weekdayLong[index];

/// „Do, 22.10.“
String scheduleDateLabel(LocalDay day) =>
    '${scheduleWeekdayShort(day)}, ${day.day}.${day.month}.';

/// Kurzer Tag für Hinweise und Aktionen: innerhalb von sechs Tagen um
/// [today] der Wochentag („Do“), sonst „Do, 5.11.“.
String scheduleDayShort(LocalDay day, LocalDay today) =>
    today.daysUntil(day).abs() < 7
    ? scheduleWeekdayShort(day)
    : scheduleDateLabel(day);

/// Kurzer Statustext eines geplanten Trainings, z. B. „Verschoben auf Di“.
String scheduledStatusLabel(ScheduledTraining training, LocalDay today) =>
    switch (training.status) {
      ScheduledTrainingStatus.planned => 'Geplant',
      ScheduledTrainingStatus.done => 'Erledigt',
      ScheduledTrainingStatus.missed => 'Verpasst',
      ScheduledTrainingStatus.insteadOf =>
        'Stattdessen: ${training.instead.map((w) => w.title).join(', ')}',
      ScheduledTrainingStatus.moved =>
        'Verschoben auf ${scheduleDayShort(training.movedToDate!, today)}',
      ScheduledTrainingStatus.skipped => 'Übersprungen',
    };
