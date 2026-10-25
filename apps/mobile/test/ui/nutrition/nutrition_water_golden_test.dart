import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const _accountId = '00000000-0000-4000-8000-000000000095';
const _day = '2026-10-25';

void main() {
  for (final variant in const [
    (name: 'light', brightness: Brightness.light, textScale: 1.0),
    (name: 'dark', brightness: Brightness.dark, textScale: 1.0),
    (name: 'light_scale2', brightness: Brightness.light, textScale: 2.0),
  ]) {
    testWidgets('water card ${variant.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      var next = 500;
      final repository = NutritionRepository(
        store: LocalSyncStore(database: database, accountId: _accountId),
        ids: () =>
            '00000000-0000-4000-8000-${(++next).toString().padLeft(12, '0')}',
        clock: () => DateTime.utc(2026, 10, 25, 10),
      );
      await repository.preferences.update(
        (current) => current.copyWith(waterEnabled: true),
      );
      await repository.water.add(_day, 750);
      await repository.water.add(_day, 500);
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: _day,
      );
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(
        CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: GainerTheme.forBrightness(variant.brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              platformBrightness: variant.brightness,
              textScaler: TextScaler.linear(variant.textScale),
            ),
            child: GainerDesign(child: child!),
          ),
          home: NutritionScreen(viewModel: viewModel),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (variant.textScale > 1) {
        // Bei großer Schrift steht die Karte weiter unten; sie soll ganz zu
        // sehen sein.
        await tester.ensureVisible(
          find.byKey(const ValueKey('nutrition-water-amount')),
        );
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byType(NutritionScreen),
        matchesGoldenFile('goldens/nutrition_water_${variant.name}.png'),
      );

      await tester.tap(find.byKey(const ValueKey('nutrition-water-amount')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/nutrition_water_sheet_${variant.name}.png'),
      );
    }, tags: ['golden']);
  }
}
