import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition_averages.dart';

NutritionDay day(
  String date,
  double kcal, {
  double protein = 100,
  double carbs = 200,
  double fat = 60,
  double? fiber,
}) => NutritionDay(
  localDate: date,
  entries: [
    NutritionEntry(
      entryId:
          '00000000-0000-4000-8000-${date.replaceAll('-', '').padLeft(12, '0')}',
      meal: NutritionMeal.lunch,
      position: 0,
      productName: 'Essen',
      brand: null,
      amountGrams: 100,
      per100Grams: NutritionTotals(
        kilocalories: kcal,
        proteinGrams: protein,
        carbohydrateGrams: carbs,
        fatGrams: fat,
        fiberGrams: fiber,
      ),
      source: null,
    ),
  ],
);

NutritionTargetVersion target(
  String id,
  double kcal, {
  required String from,
  String? until,
}) => NutritionTargetVersion(
  targetVersionId: id,
  name: 'Ziel $id',
  category: NutritionTargetCategory.custom,
  effectiveFrom: from,
  effectiveUntil: until,
  inputMode: NutritionTargetInputMode.grams,
  kilocalories: kcal,
  proteinGrams: 150,
  carbohydrateGrams: 250,
  fatGrams: 70,
  proteinPercent: null,
  carbohydratePercent: null,
  fatPercent: null,
);

void main() {
  const today = '2026-10-19';
  final schedule = NutritionTargetSchedule(
    versions: [target('a', 2300, from: '2026-09-01')],
  );

  // Arbeitsbeispiel aus der Spezifikation: 5 von 7 Tagen erfasst.
  final week = [
    day('2026-10-13', 2000, protein: 120, carbs: 250, fat: 70),
    day('2026-10-14', 2300, protein: 150, carbs: 260, fat: 80),
    day('2026-10-15', 2530, protein: 160, carbs: 300, fat: 90),
    day('2026-10-17', 2070, protein: 140, carbs: 230, fat: 70),
    day('2026-10-19', 1900, protein: 130, carbs: 200, fat: 60),
  ];

  test('7 days: averages per logged day, counts and target comparison', () {
    final result = NutritionAverages.compute(
      days: week,
      schedule: schedule,
      today: today,
      windowDays: 7,
    );
    expect(result.days.map((d) => d.localDate).first, '2026-10-13');
    expect(result.days.last.localDate, today);
    expect(result.days, hasLength(7));
    expect(result.loggedDays, 5);
    expect(result.includesToday, isTrue);
    expect(result.averageKilocalories, 2160);
    expect(result.averageProteinGrams, 140);
    expect(result.averageCarbohydrateGrams, 248);
    expect(result.averageFatGrams, 74);
    expect(result.averageTargetKilocalories, 2300);
    // 2300 exakt, 2530 (+10 %) und 2070 (-10 %) liegen im Bereich.
    expect(result.daysWithinTarget, 3);
    expect(result.daysWithTarget, 5);
  });

  test('fiber is averaged only over logged days with fiber', () {
    final result = NutritionAverages.compute(
      days: [
        day('2026-10-13', 2000, fiber: 20),
        day('2026-10-14', 2000, fiber: 25),
        day('2026-10-15', 2000, fiber: 30),
        day('2026-10-16', 2000),
        day('2026-10-17', 2000),
        day('2026-10-18', 2000),
        day('2026-10-19', 2000),
      ],
      schedule: schedule,
      today: today,
      windowDays: 7,
    );
    expect(result.loggedDays, 7);
    expect(result.averageFiberGrams, 25);
  });

  test('unlogged days are null, not zero', () {
    final result = NutritionAverages.compute(
      days: week,
      schedule: schedule,
      today: today,
      windowDays: 7,
    );
    final byDate = {for (final d in result.days) d.localDate: d};
    expect(byDate['2026-10-16']!.kilocalories, isNull);
    expect(byDate['2026-10-16']!.isLogged, isFalse);
    expect(byDate['2026-10-16']!.isWithinTarget, isFalse);
    expect(byDate['2026-10-17']!.kilocalories, 2070);
  });

  test('30 days include older logged days that 7 days exclude', () {
    final days = [...week, day('2026-10-01', 3000), day('2026-09-20', 1000)];
    final seven = NutritionAverages.compute(
      days: days,
      schedule: schedule,
      today: today,
      windowDays: 7,
    );
    final thirty = NutritionAverages.compute(
      days: days,
      schedule: schedule,
      today: today,
      windowDays: 30,
    );
    expect(seven.loggedDays, 5);
    expect(thirty.days.first.localDate, '2026-09-20');
    expect(thirty.days, hasLength(30));
    expect(thirty.loggedDays, 7);
    expect(thirty.averageKilocalories, (10800 + 3000 + 1000) / 7);
  });

  test('today counts only when it has entries', () {
    final withoutToday = [
      for (final d in week)
        if (d.localDate != today) d,
    ];
    final result = NutritionAverages.compute(
      days: withoutToday,
      schedule: schedule,
      today: today,
      windowDays: 7,
    );
    expect(result.includesToday, isFalse);
    // Fenster endet gestern und zeigt weiter 7 volle Tage.
    expect(result.days.last.localDate, '2026-10-18');
    expect(result.days.first.localDate, '2026-10-12');
    expect(result.days, hasLength(7));
    expect(result.loggedDays, 4);
    expect(result.averageKilocalories, (2000 + 2300 + 2530 + 2070) / 4);
  });

  test('an empty stored today (all entries removed) does not count', () {
    final result = NutritionAverages.compute(
      days: [
        ...week.take(4),
        NutritionDay(localDate: today, entries: const []),
      ],
      schedule: schedule,
      today: today,
      windowDays: 7,
    );
    expect(result.includesToday, isFalse);
    expect(result.loggedDays, 4);
  });

  test('just outside the 10 percent band is not within target', () {
    final result = NutritionAverages.compute(
      days: [day('2026-10-18', 2531), day('2026-10-17', 2069)],
      schedule: schedule,
      today: today,
      windowDays: 7,
    );
    expect(result.daysWithinTarget, 0);
    expect(result.daysWithTarget, 2);
  });

  test('target change mid range uses the target valid on each day', () {
    final changed = NutritionTargetSchedule(
      versions: [
        target('a', 2000, from: '2026-09-01', until: '2026-10-15'),
        target('b', 2500, from: '2026-10-16'),
      ],
    );
    final result = NutritionAverages.compute(
      days: [day('2026-10-15', 2000), day('2026-10-16', 2000)],
      schedule: changed,
      today: today,
      windowDays: 7,
    );
    final byDate = {for (final d in result.days) d.localDate: d};
    expect(byDate['2026-10-15']!.targetKilocalories, 2000);
    expect(byDate['2026-10-16']!.targetKilocalories, 2500);
    expect(result.averageTargetKilocalories, 2250);
    // 2000 ist gegen 2000 im Ziel, gegen 2500 (-20 %) nicht.
    expect(result.daysWithinTarget, 1);
    expect(result.daysWithTarget, 2);
  });

  test('without schedule there is no target comparison', () {
    final result = NutritionAverages.compute(
      days: week,
      schedule: null,
      today: today,
      windowDays: 7,
    );
    expect(result.hasTarget, isFalse);
    expect(result.averageTargetKilocalories, isNull);
    expect(result.daysWithinTarget, 0);
    expect(result.averageKilocalories, 2160);
  });

  test('no data yields null averages and zero logged days', () {
    final result = NutritionAverages.compute(
      days: const [],
      schedule: schedule,
      today: today,
      windowDays: 30,
    );
    expect(result.hasData, isFalse);
    expect(result.loggedDays, 0);
    expect(result.averageKilocalories, isNull);
    expect(result.averageProteinGrams, isNull);
    expect(result.days, hasLength(30));
  });

  test('shiftLocalDate crosses month and year borders', () {
    expect(shiftLocalDate('2026-03-01', -1), '2026-02-28');
    expect(shiftLocalDate('2026-01-01', -1), '2025-12-31');
    expect(shiftLocalDate('2026-10-19', -29), '2026-09-20');
  });
}
