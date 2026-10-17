import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_input.dart';

void main() {
  group('weight unit', () {
    test('225 lbs are stored as about 102.06 kg', () {
      final kg = parseWeightInput('225', WeightUnit.lbs);

      expect(kg, isNotNull);
      expect(kg!, closeTo(102.06, 0.01));
      expect(formatWeight(kg, WeightUnit.lbs), '225');
    });

    test('kilograms are shown with a decimal comma', () {
      expect(formatWeight(102.5, WeightUnit.kg), '102,5');
      expect(formatWeight(102.06, WeightUnit.kg), '102,06');
      expect(formatWeight(100, WeightUnit.kg), '100');
    });

    test('lbs are converted with the factor 2.20462', () {
      expect(WeightUnit.lbs.toKg(2.20462), closeTo(1, 1e-9));
      expect(WeightUnit.lbs.fromKg(1), closeTo(2.20462, 1e-9));
      expect(WeightUnit.kg.toKg(50), 50);
    });
  });

  group('weight input', () {
    test('accepts comma and point as decimal separator', () {
      expect(parseWeightInput('102,5', WeightUnit.kg), 102.5);
      expect(parseWeightInput('102.5', WeightUnit.kg), 102.5);
      expect(parseWeightInput(',5', WeightUnit.kg), 0.5);
    });

    test('empty input means no value instead of zero', () {
      expect(parseWeightInput('  ', WeightUnit.kg), isNull);
    });

    test('negative, malformed and too large values are rejected', () {
      expect(
        () => parseWeightInput('-5', WeightUnit.kg),
        throwsFormatException,
      );
      expect(
        () => parseWeightInput('abc', WeightUnit.kg),
        throwsFormatException,
      );
      expect(
        () => parseWeightInput('1e3', WeightUnit.kg),
        throwsFormatException,
      );
      expect(
        () => parseWeightInput('10001', WeightUnit.kg),
        throwsFormatException,
      );
    });
  });

  group('repetitions and rir input', () {
    test('repetitions must be whole non-negative numbers', () {
      expect(parseRepetitionsInput('8'), 8);
      expect(parseRepetitionsInput('0'), 0);
      expect(parseRepetitionsInput(''), isNull);
      expect(() => parseRepetitionsInput('8,5'), throwsFormatException);
      expect(() => parseRepetitionsInput('-1'), throwsFormatException);
    });

    test('rir is limited to 0 through 10', () {
      expect(parseRirInput('0'), 0);
      expect(parseRirInput('10'), 10);
      expect(() => parseRirInput('11'), throwsFormatException);
      expect(() => parseRirInput('2.5'), throwsFormatException);
    });
  });
}
