import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';

void main() {
  test('weight units convert through canonical kilograms', () {
    final pounds = weightForDisplay(70, BodyWeightUnit.pounds);
    expect(pounds, closeTo(154.3236, 0.001));
    expect(weightToKilograms(pounds, BodyWeightUnit.pounds), closeTo(70, 1e-9));
  });

  test('goal validation rejects impossible dates and non-positive weights', () {
    expect(
      () => validateBodyGoal(
        kind: BodyGoalKind.cut,
        startWeightKg: 80,
        targetWeightKg: 70,
        startDate: '2026-02-30',
        targetDate: '2026-02-01',
      ),
      throwsA(isA<BodyTrackingValidationException>()),
    );
    expect(
      () => validateBodyGoal(
        kind: BodyGoalKind.bulk,
        startWeightKg: 0,
        targetWeightKg: 75,
        startDate: '2026-01-01',
        targetDate: '2026-01-02',
      ),
      throwsA(isA<BodyTrackingValidationException>()),
    );
  });

  test(
    'daily check-in accepts nullable metrics and validates supplied values',
    () {
      expect(
        () => validateDailyCheckIn(
          DailyCheckInInput(
            localDate: '2026-10-12',
            weightKg: 72.5,
            caloriesKcal: null,
            proteinGrams: null,
            carbohydrateGrams: null,
            fatGrams: null,
            steps: null,
            sleepMinutes: null,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => validateDailyCheckIn(
          DailyCheckInInput(
            localDate: '2026-10-12',
            weightKg: 72.5,
            caloriesKcal: -1,
            proteinGrams: null,
            carbohydrateGrams: null,
            fatGrams: null,
            steps: -1,
            sleepMinutes: 1441,
          ),
        ),
        throwsA(isA<BodyTrackingValidationException>()),
      );
    },
  );
}
