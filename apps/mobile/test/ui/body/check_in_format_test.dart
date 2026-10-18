import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/body/check_in_format.dart';

void main() {
  test('Schlafdauer geht über Mitternacht', () {
    expect(sleepMinutesBetween(23 * 60 + 30, 7 * 60), 450);
    expect(sleepMinutesBetween(23 * 60 + 10, 6 * 60 + 45), 455);
    expect(sleepMinutesBetween(1 * 60, 9 * 60), 480);
    expect(sleepMinutesBetween(7 * 60, 7 * 60), 0);
  });

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
