import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const _account = '00000000-0000-4000-8000-000000000001';

/// Tagesnavigation über die Zeitumstellung. „± 24 h“ blieb unter
/// TZ=Europe/Berlin am 25.10.2026 hängen (der Tag hat 25 Stunden) und sprang
/// vom 29.03.2027 zurück auf den 27. (der 28. hat 23 Stunden).
void main() {
  // Die Pfeile direkt auslösen: Je nach Datumslänge verdeckt die Toolbar den
  // rechten Pfeil im Testlayout, gemeint ist hier nur _shiftDay.
  GainerDayNavigator navigator(WidgetTester tester) =>
      tester.widget<GainerDayNavigator>(find.byType(GainerDayNavigator));

  Future<NutritionViewModel> open(WidgetTester tester, String date) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final viewModel = NutritionViewModel(
      repository: NutritionRepository(
        store: LocalSyncStore(database: database, accountId: _account),
        clock: () => DateTime.utc(2027, 6, 1, 10),
      ),
      localDate: date,
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();
    return viewModel;
  }

  testWidgets('next day leaves the autumn DST day', (tester) async {
    final viewModel = await open(tester, '2026-10-25');

    navigator(tester).onNext();
    await tester.pumpAndSettle();

    expect(viewModel.localDate, '2026-10-26');
  });

  testWidgets('previous day lands on the spring DST day', (tester) async {
    final viewModel = await open(tester, '2027-03-29');

    navigator(tester).onPrevious();
    await tester.pumpAndSettle();

    expect(viewModel.localDate, '2027-03-28');
  });
}
