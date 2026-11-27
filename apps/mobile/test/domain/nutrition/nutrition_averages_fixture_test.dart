import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition_averages.dart';

import '../../support/contract_fixture.dart';

/// Die Ansicht „Durchschnitt“ rechnet wie der Server
/// (`get_nutrition_averages`). Die Tagesart ist in der Fixture an jedem
/// erfassten Tag unter einem Ruhetag-Ziel festgelegt; die automatische
/// Tagesart aus dem Rhythmus gibt es nur in der App.
void main() {
  for (final testCase in loadFixtureCases('nutrition-averages.json')) {
    test('Fall ${testCase['name']}', () => _verify(testCase));
  }
}

void _verify(Map<String, Object?> testCase) {
  final targets = [
    for (final (index, item) in fixtureList(testCase['targets']).indexed)
      _target('$index', item! as Map<String, Object?>),
  ];
  final result = NutritionAverages.compute(
    days: [
      for (final item in fixtureList(testCase['days']))
        _day(item! as Map<String, Object?>),
    ],
    schedule: targets.isEmpty
        ? null
        : NutritionTargetSchedule(versions: targets),
    today: testCase['today']! as String,
    windowDays: testCase['windowDays']! as int,
  );
  final expected = testCase['expected']! as Map<String, Object?>;

  expect(result.days.first.localDate, expected['from']);
  expect(result.days.last.localDate, expected['through']);
  expect(result.includesToday, expected['includesToday']);
  expect(result.loggedDays, expected['loggedDays']);
  final averages = {
    'averageKilocalories': result.averageKilocalories,
    'averageProteinGrams': result.averageProteinGrams,
    'averageCarbohydrateGrams': result.averageCarbohydrateGrams,
    'averageFatGrams': result.averageFatGrams,
    'averageFiberGrams': result.averageFiberGrams,
    'averageSaltGrams': result.averageSaltGrams,
    'averageTargetKilocalories': result.averageTargetKilocalories,
  };
  for (final MapEntry(:key, :value) in averages.entries) {
    expectFixtureNumber(value, expected[key], key);
  }
  expect(result.daysWithinTarget, expected['daysWithinTarget']);
  expect(result.daysWithTarget, expected['daysWithTarget']);
  final days = fixtureList(expected['days']);
  expect(result.days, hasLength(days.length));
  for (var i = 0; i < days.length; i++) {
    final want = days[i]! as Map<String, Object?>;
    final actual = result.days[i];
    final label = actual.localDate;
    expect(label, want['localDate']);
    expectFixtureNumber(actual.kilocalories, want['kilocalories'], label);
    // Ziele unerfasster Tage hängen in der App am Rhythmus (siehe oben).
    expectFixtureNumber(
      actual.isLogged ? actual.targetKilocalories : null,
      want['targetKilocalories'],
      '$label target',
    );
    expect(actual.isWithinTarget, want['withinTarget'], reason: label);
  }
}

NutritionDay _day(Map<String, Object?> json) {
  final date = json['localDate']! as String;
  final totals = json['totals'] as Map<String, Object?>?;
  return NutritionDay(
    localDate: date,
    dayKind: nutritionDayKindFromWire(switch (json['dayKind']) {
      'training' => 'Training',
      'rest' => 'Rest',
      _ => null,
    }),
    entries: [
      if (totals != null)
        NutritionEntry(
          entryId:
              '00000000-0000-4000-8000-${date.replaceAll('-', '').padLeft(12, '0')}',
          meal: NutritionMeal.lunch,
          position: 0,
          productName: 'Essen',
          brand: null,
          amountGrams: 100,
          per100Grams: NutritionTotals.fromJson(totals),
          source: null,
        ),
    ],
  );
}

NutritionTargetVersion _target(String id, Map<String, Object?> json) {
  final rest = json['restDayKilocalories'] as num?;
  return NutritionTargetVersion(
    targetVersionId: '00000000-0000-4000-8000-00000000000$id',
    name: 'Ziel $id',
    category: NutritionTargetCategory.custom,
    effectiveFrom: json['effectiveFrom']! as String,
    effectiveUntil: json['effectiveUntil'] as String?,
    inputMode: NutritionTargetInputMode.grams,
    kilocalories: (json['kilocalories']! as num).toDouble(),
    proteinGrams: 150,
    carbohydrateGrams: 250,
    fatGrams: 70,
    proteinPercent: null,
    carbohydratePercent: null,
    fatPercent: null,
    restDay: rest == null
        ? null
        : NutritionDayTarget(
            inputMode: NutritionTargetInputMode.grams,
            kilocalories: rest.toDouble(),
            proteinGrams: 140,
            carbohydrateGrams: 200,
            fatGrams: 60,
          ),
  );
}
