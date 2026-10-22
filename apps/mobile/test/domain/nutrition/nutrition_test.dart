import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';

NutritionEntry entry({
  int position = 0,
  NutritionMeal meal = NutritionMeal.breakfast,
  String id = 'entry-a',
}) => NutritionEntry(
  entryId: id,
  meal: meal,
  position: position,
  productName: 'Haferflocken',
  brand: null,
  amountGrams: 50,
  per100Grams: const NutritionTotals(
    kilocalories: 370.5,
    proteinGrams: 13.2,
    carbohydrateGrams: 58.7,
    fatGrams: 7.1,
  ),
  source: null,
);

void main() {
  test('scales per-100g values with two decimal rounding and preserves unknown macros', () {
    final value = entry();
    expect(value.totals.kilocalories, 185.25);
    expect(value.totals.proteinGrams, 6.6);
    expect(value.totals.carbohydrateGrams, 29.35);
    expect(
      const NutritionTotals(kilocalories: 12).scaled(2).proteinGrams,
      isNull,
    );
  });

  test('salt is scaled, summed only over entries with salt and validated', () {
    NutritionEntry food(String id, double? salt) => NutritionEntry(
      entryId: id,
      meal: NutritionMeal.breakfast,
      position: id.length,
      productName: id,
      brand: null,
      amountGrams: 50,
      per100Grams: NutritionTotals(kilocalories: 250, saltGrams: salt),
      source: null,
    );
    final day = NutritionDay(
      localDate: '2026-10-12',
      entries: [food('brot', 1.25), food('apfel', null)],
    );
    expect(day.entries.first.totals.saltGrams, 0.63);
    expect(day.totals.saltGrams, 0.63);
    expect(
      NutritionDay(
        localDate: '2026-10-12',
        entries: [food('apfel', null)],
      ).totals.saltGrams,
      isNull,
    );
    expect(
      NutritionTotals.fromJson({'kilocalories': 10, 'saltGrams': 0.5})
          .saltGrams,
      0.5,
    );
    expect(
      const NutritionTotals(kilocalories: 10).toJson().containsKey('saltGrams'),
      isFalse,
    );
  });

  test('target phases fall back to 6 g salt and reject invalid limits', () {
    NutritionTargetVersion phase(double? salt) => NutritionTargetVersion(
      targetVersionId: 'phase',
      name: 'Ziel',
      category: NutritionTargetCategory.custom,
      effectiveFrom: '2026-10-01',
      effectiveUntil: null,
      inputMode: NutritionTargetInputMode.grams,
      kilocalories: 2000,
      proteinGrams: 150,
      carbohydrateGrams: 200,
      fatGrams: 60,
      proteinPercent: null,
      carbohydratePercent: null,
      fatPercent: null,
      saltGrams: salt,
    );
    expect(phase(null).effectiveSaltGrams, 6);
    expect(phase(5).effectiveSaltGrams, 5);
    expect(phase(5).toJson()['saltGrams'], 5);
    expect(phase(null).toJson().containsKey('saltGrams'), isFalse);
    for (final invalid in [0.0, -1.0, 101.0]) {
      expect(
        () => NutritionTargetSchedule(versions: [phase(invalid)]),
        throwsA(isA<NutritionValidationException>()),
      );
    }
  });

  test('day totals stay nullable when no entries contain macro values', () {
    final day = NutritionDay(
      localDate: '2026-10-12',
      entries: [
        NutritionEntry(
          entryId: 'a',
          meal: NutritionMeal.lunch,
          position: 0,
          productName: 'Suppe',
          brand: null,
          amountGrams: 200,
          per100Grams: const NutritionTotals(kilocalories: 50),
          source: null,
        ),
      ],
    );
    expect(day.totals.kilocalories, 100);
    expect(day.totals.proteinGrams, isNull);
  });

  test('moving entries between meals reindexes both meal sequences', () {
    final day = NutritionDay(
      localDate: '2026-10-12',
      entries: [
        entry(position: 0, id: 'a'),
        entry(position: 1, id: 'b'),
        entry(position: 0, meal: NutritionMeal.lunch, id: 'c'),
      ],
    );
    final moved = day.move('b', NutritionMeal.lunch, 0);
    expect(
      moved.entries
          .where((e) => e.meal == NutritionMeal.breakfast)
          .map((e) => e.position),
      [0],
    );
    expect(
      moved.entries
          .where((e) => e.meal == NutritionMeal.lunch)
          .map((e) => (e.entryId, e.position)),
      [('b', 0), ('c', 1)],
    );
  });

  test(
    'rejects invalid nutrition values, duplicate positions and malformed dates',
    () {
      expect(
        () => entry().copyWith(amountGrams: 0),
        throwsA(isA<NutritionValidationException>()),
      );
      expect(
        () => NutritionDay(localDate: '2026-02-30', entries: const []),
        throwsA(isA<NutritionValidationException>()),
      );
      expect(
        () => NutritionDay(
          localDate: '2026-10-12',
          entries: [
            entry(id: 'a'),
            entry(id: 'b'),
          ],
        ),
        throwsA(isA<NutritionValidationException>()),
      );
    },
  );

  test('target phases require valid nonoverlapping dates and four-four-nine percentages', () {
    final phase = NutritionTargetVersion(
      targetVersionId: 'phase-1',
      name: 'Cut',
      category: NutritionTargetCategory.cut,
      effectiveFrom: '2026-10-01',
      effectiveUntil: null,
      inputMode: NutritionTargetInputMode.percent,
      kilocalories: 2000,
      proteinGrams: 150,
      carbohydrateGrams: 200,
      fatGrams: 66.67,
      proteinPercent: 30,
      carbohydratePercent: 40,
      fatPercent: 30,
    );
    expect(() => NutritionTargetSchedule(versions: [phase]), returnsNormally);
    final invalid = NutritionTargetVersion(
      targetVersionId: 'phase-2',
      name: 'Bulk',
      category: NutritionTargetCategory.bulk,
      effectiveFrom: '2026-10-02',
      effectiveUntil: null,
      inputMode: NutritionTargetInputMode.percent,
      kilocalories: 2500,
      proteinGrams: 150,
      carbohydrateGrams: 300,
      fatGrams: 80,
      proteinPercent: 25,
      carbohydratePercent: 40,
      fatPercent: 30,
    );
    expect(
      () => NutritionTargetSchedule(versions: [phase, invalid]),
      throwsA(isA<NutritionValidationException>()),
    );
  });
}
