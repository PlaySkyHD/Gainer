import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/body/check_in_format.dart';

/// Verschiebung der lokalen Uhr zwischen zwei Zeitpunkten in Minuten. Unter
/// `TZ=Europe/Berlin` in der Herbstnacht +60, in der Frühlingsnacht -60,
/// unter `TZ=UTC` immer 0.
int _clockShift(DateTime from, DateTime to) =>
    (from.timeZoneOffset - to.timeZoneOffset).inMinutes;

void main() {
  test('Schlafdauer geht über Mitternacht', () {
    final day = DateTime(2026, 10, 12);
    int minutes(int bed, int wake) => sleepWindowOn(day, bed, wake).minutes;

    expect(minutes(23 * 60 + 30, 7 * 60), 450);
    expect(minutes(23 * 60 + 10, 6 * 60 + 45), 455);
    expect(minutes(1 * 60, 9 * 60), 480);
    expect(minutes(7 * 60, 7 * 60), 0);
  });

  test(
    'Zu Bett liegt am Vortag, wenn die Uhrzeit nach dem Aufstehen liegt',
    () {
      final night = sleepWindowOn(DateTime(2026, 10, 12), 23 * 60 + 30, 7 * 60);
      expect(night.bedtime, DateTime(2026, 10, 11, 23, 30));
      expect(night.wake, DateTime(2026, 10, 12, 7));

      final morning = sleepWindowOn(DateTime(2026, 10, 12), 60, 9 * 60);
      expect(morning.bedtime, DateTime(2026, 10, 12, 1));
      expect(morning.wake, DateTime(2026, 10, 12, 9));
    },
  );

  // Unter TZ=Europe/Berlin: Herbst 510 min, Frühling 390 min; unter UTC 450.
  for (final (name, day) in [
    ('Herbst', DateTime(2026, 10, 25)),
    ('Frühling', DateTime(2027, 3, 28)),
  ]) {
    test('Zeitumstellung ($name): Uhrzeiten bleiben, Dauer ist echt', () {
      final sleep = sleepWindowOn(day, 23 * 60 + 30, 7 * 60);
      final bedtime = DateTime(day.year, day.month, day.day - 1, 23, 30);
      final wake = DateTime(day.year, day.month, day.day, 7);

      expect(sleep.bedtime, bedtime);
      expect(sleep.bedtime.hour, 23);
      expect(sleep.bedtime.minute, 30);
      expect(sleep.wake, wake);
      expect(sleep.minutes, 450 + _clockShift(bedtime, wake));
      expect(sleep.minutes, sleep.wake.difference(sleep.bedtime).inMinutes);
    });
  }

  test('Dauer und Uhrzeit werden deutsch formatiert', () {
    expect(formatSleepDuration(455), '7 h 35 min');
    expect(formatSleepDuration(480), '8 h');
    expect(formatSleepDuration(45), '45 min');
    expect(formatMinuteOfDay(6 * 60 + 5), '06:05');
    expect(formatMinuteOfDay(23 * 60 + 10), '23:10');
  });

  test('Schritte mit Tausenderpunkt', () {
    expect(formatStepCount(0), '0');
    expect(formatStepCount(999), '999');
    expect(formatStepCount(8432), '8.432');
    expect(formatStepCount(1234567), '1.234.567');
  });
}
