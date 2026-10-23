import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/bls_food_catalog.dart';
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
    testWidgets('add food sheet ${variant.name}', (tester) async {
      final harness = await _pump(tester, variant.brightness);
      await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/nutrition_add_sheet_${variant.name}.png'),
      );
      harness.dispose();
    }, tags: ['golden']);

    testWidgets('food search ${variant.name}', (tester) async {
      final harness = await _pump(
        tester,
        variant.brightness,
        localFoods: BlsFoodCatalog.fromIndex(
          parseBlsCatalog(File(BlsFoodCatalog.asset).readAsStringSync()),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lebensmittel suchen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-entry-search')),
        'Haferflocken',
      );
      tester.testTextInput.hide();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/nutrition_food_search_${variant.name}.png'),
      );
      harness.dispose();
    }, tags: ['golden']);

    testWidgets('manual food form ${variant.name}', (tester) async {
      final harness = await _pump(tester, variant.brightness);
      await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manuell erfassen'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/nutrition_manual_${variant.name}.png'),
      );
      harness.dispose();
    }, tags: ['golden']);

    testWidgets('meal editor ${variant.name}', (tester) async {
      final harness = await _pump(tester, variant.brightness);
      await harness.repository.saveReusableMeal(
        ReusableMeal(
          name: 'Reisbowl',
          description: null,
          standardPortion: 1,
          components: [
            ReusableMealComponent(
              componentId: '00000000-0000-4000-8000-000000000071',
              position: 0,
              name: 'Reis',
              brand: null,
              amountGrams: 200,
              per100Grams: const NutritionTotals(kilocalories: 130),
              source: null,
            ),
            ReusableMealComponent(
              componentId: '00000000-0000-4000-8000-000000000072',
              position: 1,
              name: 'Hähnchenbrust',
              brand: null,
              amountGrams: 150,
              per100Grams: const NutritionTotals(kilocalories: 165),
              source: null,
            ),
          ],
        ),
      );
      await harness.viewModel.load();
      await tester.tap(find.byKey(const ValueKey('nutrition-more-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gerichte und Vorlagen verwalten'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reusable-meal-Reisbowl')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/nutrition_meal_editor_${variant.name}.png'),
      );
      harness.dispose();
    }, tags: ['golden']);
  }
}

class _Harness {
  _Harness(this.repository, this.viewModel);

  final NutritionRepository repository;
  final NutritionViewModel viewModel;

  void dispose() => viewModel.dispose();
}

Future<_Harness> _pump(
  WidgetTester tester,
  Brightness brightness, {
  LocalFoodCatalog? localFoods,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final repository = NutritionRepository(
    store: LocalSyncStore(database: database, accountId: accountId),
    clock: () => DateTime.utc(2026, 10, 12, 10),
    localFoods: localFoods,
  );
  final viewModel = NutritionViewModel(
    repository: repository,
    localDate: '2026-10-12',
  );
  await tester.pumpWidget(
    CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: GainerTheme.forBrightness(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
        child: GainerDesign(child: child!),
      ),
      home: NutritionScreen(viewModel: viewModel),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(repository, viewModel);
}
