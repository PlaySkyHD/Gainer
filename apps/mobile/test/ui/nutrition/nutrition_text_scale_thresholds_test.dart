import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_water_card.dart';

const _accountId = '00000000-0000-4000-8000-000000000005';
const _date = '2026-10-12';

/// Die Wasserkarte stapelt ab `> 1.5`: 1,3 und 1,5 liegen darunter bzw. genau
/// an der Schwelle, 1,6 darüber.
const _waterScales = [1.3, 1.5, 1.6, 2.0];

/// `_PieceCountRow` stapelt ab `> 1.5`.
const _entryScales = [1.3, 1.5, 1.6, 2.0];

void main() {
  for (final scale in _waterScales) {
    testWidgets('water card at 320 pt and text scale $scale', (tester) async {
      _narrowView(tester);
      await tester.pumpWidget(
        _app(
          scale,
          SingleChildScrollView(
            child: NutritionWaterCard(
              amountMl: 1250,
              goalMl: 2500,
              onAdd: (_) {},
              onEdit: () {},
              error: 'Die Wassermenge konnte nicht gespeichert werden.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final key in [
        'nutrition-water-amount',
        'nutrition-water-add-200',
        'nutrition-water-add-300',
        'nutrition-water-add-500',
        'nutrition-water-error',
      ]) {
        final finder = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(
          finder,
          100,
          scrollable: _verticalScrollable().last,
        );
        expect(finder, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in _entryScales) {
    testWidgets('piece count row at 320 pt and text scale $scale', (
      tester,
    ) async {
      final viewModel = await _openManualEntry(tester, scale);
      addTearDown(viewModel.dispose);

      for (final key in [
        'nutrition-piece-grams',
        'piece-minus',
        'piece-count-field',
        'piece-plus',
      ]) {
        await _scrollTo(tester, key);
      }
      // Die Einheit bleibt bei der Zahl: daneben oder gestapelt in der
      // Beschriftung.
      expect(
        scale > 1.5 ? find.text('Anzahl in Stk') : find.text('Stk'),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    });
  }
}

/// Öffnet „Manuell erfassen“ im Sheet zum Hinzufügen eines Lebensmittels.
Future<NutritionViewModel> _openManualEntry(
  WidgetTester tester,
  double scale,
) async {
  final viewModel = await _pumpScreen(tester, scale);
  await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
  await tester.pumpAndSettle();
  final manual = find.text('Manuell erfassen').hitTestable();
  await tester.scrollUntilVisible(
    manual,
    100,
    scrollable: _verticalScrollable().last,
  );
  await tester.tap(manual);
  await tester.pumpAndSettle();
  return viewModel;
}

/// Die Listen bauen nur sichtbare Zeilen: erst zur Zeile scrollen.
Future<void> _scrollTo(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key)).hitTestable();
  await tester.scrollUntilVisible(
    finder,
    100,
    scrollable: _verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  expect(finder, findsOneWidget);
}

void _narrowView(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(double scale, Widget home) => CupertinoApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: GainerDesign(child: child!),
  ),
  home: CupertinoPageScaffold(child: SafeArea(child: home)),
);

Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

Future<NutritionViewModel> _pumpScreen(
  WidgetTester tester,
  double scale,
) async {
  _narrowView(tester);
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final repository = NutritionRepository(
    store: LocalSyncStore(database: database, accountId: _accountId),
    clock: () => DateTime.utc(2026, 10, 12, 10),
  );
  final viewModel = NutritionViewModel(
    repository: repository,
    localDate: _date,
  );
  await tester.pumpWidget(_app(scale, NutritionScreen(viewModel: viewModel)));
  await tester.pumpAndSettle();
  return viewModel;
}
