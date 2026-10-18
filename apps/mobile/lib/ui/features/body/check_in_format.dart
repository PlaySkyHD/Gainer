/// Schlafdauer zwischen „Zu Bett“ und „Aufgestanden“ (Minuten seit Mitternacht);
/// liegt die Aufstehzeit davor, geht die Nacht über Mitternacht.
int sleepMinutesBetween(int bedMinuteOfDay, int wakeMinuteOfDay) =>
    (wakeMinuteOfDay - bedMinuteOfDay) % 1440;

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
