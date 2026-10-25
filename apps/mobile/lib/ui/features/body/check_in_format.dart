/// Höchste Schlafdauer eines Check-ins, wie `SleepMinutes.Maximum` im Backend.
const maxSleepMinutes = 24 * 60;

/// Schlaf als Zeitpunkte; [minutes] ist die Dauer für den Check-in.
typedef SleepWindow = ({DateTime bedtime, DateTime wake, int minutes});

/// Schlaf zwischen zwei Zeitpunkten. [SleepWindow.minutes] ist die echte
/// Dauer, höchstens [maxSleepMinutes]: Zu Bett 07:30 und Aufgestanden 07:00
/// sind in der Herbstnacht 24 h 30 min auseinander. Null, wenn Zu Bett nach
/// Aufgestanden liegt.
SleepWindow? sleepWindowBetween(DateTime bedtime, DateTime wake) {
  final minutes = wake.difference(bedtime).inMinutes;
  if (minutes < 0) return null;
  return (
    bedtime: bedtime,
    wake: wake,
    minutes: minutes > maxSleepMinutes ? maxSleepMinutes : minutes,
  );
}

/// Schlaf der Nacht zum Check-in-Tag [day] aus den lokalen Uhrzeiten „Zu Bett“
/// und „Aufgestanden“ (Minuten seit Mitternacht). Aufgestanden liegt an [day],
/// Zu Bett am selben Tag oder, wenn die Uhrzeit danach liegt, am Vortag.
///
/// Die Dauer ist der echte Abstand, nicht die Differenz der Uhrzeiten: In der
/// Nacht der Zeitumstellung ist sie eine Stunde länger (Herbst) oder kürzer
/// (Frühling). Null, wenn eine Uhrzeit in der übersprungenen Frühlingsstunde
/// liegt und Zu Bett dadurch hinter Aufgestanden fällt.
SleepWindow? sleepWindowOn(
  DateTime day,
  int bedMinuteOfDay,
  int wakeMinuteOfDay,
) => sleepWindowBetween(
  DateTime(
    day.year,
    day.month,
    bedMinuteOfDay > wakeMinuteOfDay ? day.day - 1 : day.day,
    bedMinuteOfDay ~/ 60,
    bedMinuteOfDay % 60,
  ),
  DateTime(
    day.year,
    day.month,
    day.day,
    wakeMinuteOfDay ~/ 60,
    wakeMinuteOfDay % 60,
  ),
);

/// „7 h 35 min“, „8 h“ oder „45 min“.
String formatSleepDuration(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

/// Uhrzeit „06:45“ aus Minuten seit Mitternacht.
String formatMinuteOfDay(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

/// Ganzzahl mit deutschem Tausenderpunkt: 8432 → „8.432“.
String formatStepCount(int steps) {
  final digits = steps.abs().toString();
  final buffer = StringBuffer(steps < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
