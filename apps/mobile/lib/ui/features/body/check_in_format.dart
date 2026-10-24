/// Schlaf der Nacht zum Check-in-Tag [day] aus den lokalen Uhrzeiten „Zu Bett“
/// und „Aufgestanden“ (Minuten seit Mitternacht). Aufgestanden liegt an [day],
/// Zu Bett am selben Tag oder, wenn die Uhrzeit danach liegt, am Vortag.
///
/// [minutes] ist die echte Dauer zwischen beiden Zeitpunkten, nicht die
/// Differenz der Uhrzeiten: In der Nacht der Zeitumstellung ist sie eine
/// Stunde länger (Herbst) oder kürzer (Frühling).
({DateTime bedtime, DateTime wake, int minutes}) sleepWindowOn(
  DateTime day,
  int bedMinuteOfDay,
  int wakeMinuteOfDay,
) {
  final wake = DateTime(
    day.year,
    day.month,
    day.day,
    wakeMinuteOfDay ~/ 60,
    wakeMinuteOfDay % 60,
  );
  final bedtime = DateTime(
    day.year,
    day.month,
    bedMinuteOfDay > wakeMinuteOfDay ? day.day - 1 : day.day,
    bedMinuteOfDay ~/ 60,
    bedMinuteOfDay % 60,
  );
  final minutes = wake.difference(bedtime).inMinutes;
  // Eine Uhrzeit, die es wegen der Umstellung nicht gibt, kann Zu Bett hinter
  // Aufgestanden schieben; dann zählt die Nacht als 0 Minuten.
  return (bedtime: bedtime, wake: wake, minutes: minutes < 0 ? 0 : minutes);
}

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
