import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';

ProgressViewModel _model(NutritionRepository nutrition, DateTime now) {
  final api = ApiClient(
    configuration: ApiConfiguration(
      apiOrigin: Uri.parse('http://127.0.0.1:5099'),
      allowInsecureLoopbackForDevelopment: true,
    ),
  );
  addTearDown(api.close);
  final model = ProgressViewModel(
    InsightsRepository(api),
    nutrition: nutrition,
    now: () => now,
  );
  addTearDown(model.dispose);
  return model;
}

void main() {
  test('reads totals for the local calendar day', () async {
    final nutrition = _Recording(
      const NutritionTotals(kilocalories: 333, proteinGrams: 42),
    );
    final model = _model(nutrition, DateTime(2026, 3, 5, 23, 30));

    await model.refreshToday();

    expect(nutrition.requested, ['2026-03-05']);
    expect(model.todayCaloriesKcal, 333);
    expect(model.todayProteinGrams, 42);
  });

  test(
    'an empty day is 0 kcal and a read failure keeps the last value',
    () async {
      final nutrition = _Recording(NutritionTotals.zero);
      final model = _model(nutrition, DateTime(2026, 10, 18));

      await model.refreshToday();
      expect(model.todayCaloriesKcal, 0);
      expect(model.todayProteinGrams, isNull);

      nutrition.fail = true;
      await model.refreshToday();
      expect(model.todayCaloriesKcal, 0);
    },
  );
}

class _Recording implements NutritionRepository {
  _Recording(this.totals);

  final NutritionTotals totals;
  final requested = <String>[];
  bool fail = false;

  @override
  Future<NutritionSnapshot> read(String localDate) async {
    requested.add(localDate);
    if (fail) throw StateError('offline store broken');
    return NutritionSnapshot(
      day: NutritionDay(
        localDate: localDate,
        entries: totals.kilocalories == 0
            ? const []
            : [
                NutritionEntry(
                  entryId: '00000000-0000-4000-8000-000000000001',
                  meal: NutritionMeal.breakfast,
                  position: 0,
                  productName: 'Test',
                  brand: null,
                  amountGrams: 100,
                  per100Grams: totals,
                  source: null,
                ),
              ],
      ),
      meals: const [],
      targetSchedule: null,
      recentFoods: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
