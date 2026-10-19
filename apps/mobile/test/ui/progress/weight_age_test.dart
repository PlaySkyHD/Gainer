import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/progress/weight_age.dart';

void main() {
  // Lokale Daten, absichtlich mit Uhrzeit nahe Mitternacht.
  final today = DateTime(2026, 10, 18, 23, 59);

  WeightAge ageOf(String date) => WeightAge.fromDate(date, today);

  test('classifies the day boundaries 0, 1, 2, 6 and 7', () {
    final expected = {
      '2026-10-18': (0, 'Heute', WeightAgeSeverity.fresh),
      '2026-10-17': (1, 'Gestern', WeightAgeSeverity.fresh),
      '2026-10-16': (2, 'vor 2 Tagen', WeightAgeSeverity.aging),
      '2026-10-12': (6, 'vor 6 Tagen', WeightAgeSeverity.aging),
      '2026-10-11': (7, 'vor 7 Tagen', WeightAgeSeverity.stale),
    };
    expected.forEach((date, want) {
      final age = ageOf(date);
      expect((age.days, age.label, age.severity), want, reason: date);
    });
  });

  test('counts calendar days across a daylight saving change', () {
    expect(
      WeightAge.fromDate('2026-10-24', DateTime(2026, 10, 26, 0, 5)).days,
      2,
    );
    expect(
      WeightAge.fromDate('2026-03-28', DateTime(2026, 3, 30, 0, 5)).days,
      2,
    );
  });

  test('future and invalid dates count as today', () {
    expect(ageOf('2026-10-20').days, 0);
    expect(ageOf('kaputt').days, 0);
  });
}
