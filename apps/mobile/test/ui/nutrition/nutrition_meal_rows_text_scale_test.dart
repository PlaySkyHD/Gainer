import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const _accountId = '00000000-0000-4000-8000-000000000004';

void main() {
  testWidgets('meal rows do not overflow at 320 pt and text scale 2', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = NutritionRepository(
      store: LocalSyncStore(database: database, accountId: _accountId),
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    var index = 0;
    for (final meal in NutritionMeal.values) {
      await repository.saveEntry(
        '2026-10-12',
        NutritionEntry(
          entryId:
              '00000000-0000-4000-8000-${(500 + index).toString().padLeft(12, '0')}',
          meal: meal,
          position: 0,
          productName: 'Haferflocken mit Joghurt',
          brand: null,
          amountGrams: 100,
          per100Grams: const NutritionTotals(kilocalories: 360),
          source: null,
        ),
      );
      index++;
    }
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: NutritionScreen(viewModel: viewModel),
      ),
    );
    await tester.pumpAndSettle();

    // Die Liste baut nur sichtbare Zeilen: bis zu jeder Mahlzeit scrollen.
    for (final meal in NutritionMeal.values) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('meal-add-${meal.name}')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('meal-add-${meal.name}')), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });
}
