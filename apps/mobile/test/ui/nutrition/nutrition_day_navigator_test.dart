import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const _account = '00000000-0000-4000-8000-000000000001';

/// Beide Tagespfeile bleiben bei 390 pt Breite antippbar, auch mit langem
/// Datum und großer Schrift. Früher lag der Plus-Button der Toolbar über dem
/// rechten Pfeil, weil die linke Toolbar-Aktion beliebig breit werden konnte.
void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('both day arrows are tappable at text scale $scale', (
      tester,
    ) async {
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
        // „Mi. 30. Sept.“: eines der längsten Datumsformate der Pille.
        localDate: '2026-09-30',
      );
      await tester.pumpWidget(
        CupertinoApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: NutritionScreen(viewModel: viewModel),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final previous = find.byIcon(CupertinoIcons.chevron_left);
      final next = find.byIcon(CupertinoIcons.chevron_right);
      expect(previous.hitTestable(), findsOneWidget);
      expect(next.hitTestable(), findsOneWidget);

      // Die Tap-Fläche der Pfeile (Button um das Symbol) ist mindestens 44 pt.
      for (final arrow in [previous, next]) {
        final button = find.ancestor(
          of: arrow,
          matching: find.byType(CupertinoButton),
        );
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(viewModel.localDate, '2026-10-01');

      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(viewModel.localDate, '2026-09-30');
    });
  }
}
