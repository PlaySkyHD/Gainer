import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000004';

void main() {
  for (final variant in const [
    (name: 'light', brightness: Brightness.light),
    (name: 'dark', brightness: Brightness.dark),
  ]) {
    testWidgets('nutrition day with entries ${variant.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 1480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = NutritionRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
        clock: () => DateTime.utc(2026, 10, 12, 10),
      );
      await repository.saveTargetSchedule(
        NutritionTargetSchedule(
          versions: [
            NutritionTargetVersion(
              targetVersionId: '00000000-0000-4000-8000-000000000060',
              name: 'Aufbau',
              category: NutritionTargetCategory.bulk,
              effectiveFrom: '2026-10-01',
              effectiveUntil: null,
              inputMode: NutritionTargetInputMode.grams,
              kilocalories: 2000,
              proteinGrams: 150,
              carbohydrateGrams: 220,
              fatGrams: 60,
              proteinPercent: null,
              carbohydratePercent: null,
              fatPercent: null,
            ),
          ],
        ),
      );
      final entries = [
        (
          id: '101',
          meal: NutritionMeal.breakfast,
          position: 0,
          name: 'Haferflocken',
          brand: 'Bio',
          amount: 60.0,
          kcal: 370.0,
          protein: 13.0,
          carbs: 59.0,
          fat: 7.0,
        ),
        (
          id: '102',
          meal: NutritionMeal.breakfast,
          position: 1,
          name: 'Joghurt',
          brand: null,
          amount: 150.0,
          kcal: 60.0,
          protein: 5.0,
          carbs: 4.0,
          fat: 3.0,
        ),
        (
          id: '103',
          meal: NutritionMeal.lunch,
          position: 0,
          name: 'Hähnchenbrust',
          brand: null,
          amount: 200.0,
          kcal: 165.0,
          protein: 31.0,
          carbs: 0.0,
          fat: 4.0,
        ),
        (
          id: '104',
          meal: NutritionMeal.dinner,
          position: 0,
          name: 'Lachsfilet',
          brand: null,
          amount: 180.0,
          kcal: 208.0,
          protein: 20.0,
          carbs: 0.0,
          fat: 13.0,
        ),
        (
          id: '105',
          meal: NutritionMeal.dinner,
          position: 1,
          name: 'Vollkornnudeln',
          brand: null,
          amount: 400.0,
          kcal: 266.0,
          protein: 9.0,
          carbs: 53.0,
          fat: 1.5,
        ),
      ];
      for (final item in entries) {
        await repository.saveEntry(
          '2026-10-12',
          NutritionEntry(
            entryId: '00000000-0000-4000-8000-000000000${item.id}',
            meal: item.meal,
            position: item.position,
            productName: item.name,
            brand: item.brand,
            amountGrams: item.amount,
            per100Grams: NutritionTotals(
              kilocalories: item.kcal,
              proteinGrams: item.protein,
              carbohydrateGrams: item.carbs,
              fatGrams: item.fat,
            ),
            source: null,
          ),
        );
      }
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await tester.pumpWidget(
        CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: GainerTheme.forBrightness(variant.brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(platformBrightness: variant.brightness),
            child: GainerDesign(child: child!),
          ),
          home: NutritionScreen(viewModel: viewModel),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(NutritionScreen),
        matchesGoldenFile('goldens/nutrition_day_${variant.name}.png'),
      );
      viewModel.dispose();
    });
  }
}
