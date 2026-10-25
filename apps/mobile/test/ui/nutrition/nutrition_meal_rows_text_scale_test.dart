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
const _date = '2026-10-12';

/// 1,5 ist der Grenzwert, ab dem die Zeile stapelt; 1,3 liegt darunter.
const _scales = [1.3, 1.5, 2.0];

void main() {
  for (final scale in _scales) {
    group('add rows at 320 pt and text scale $scale', () {
      testWidgets('meal rows of a day with all four meals', (tester) async {
        final viewModel = await _pump(tester, scale, withEntries: true);

        for (final meal in NutritionMeal.values) {
          await _scrollTo(tester, ValueKey('meal-add-${meal.name}'));
        }

        expect(tester.takeException(), isNull);
        viewModel.dispose();
      });

      testWidgets('day template editor rows', (tester) async {
        final viewModel = await _pump(
          tester,
          scale,
          withEntries: true,
          withTemplate: true,
        );
        await _openPlanning(tester);
        await _scrollTo(
          tester,
          ValueKey(
            'day-template-row-${viewModel.snapshot!.templates.single.templateId}',
          ),
        );
        await tester.tap(
          find.byKey(
            ValueKey(
              'day-template-row-${viewModel.snapshot!.templates.single.templateId}',
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final meal in NutritionMeal.values) {
          await _scrollTo(tester, ValueKey('day-template-add-${meal.name}'));
        }

        expect(tester.takeException(), isNull);
        viewModel.dispose();
      });

      testWidgets('meal component row in the dish editor', (tester) async {
        final viewModel = await _pump(tester, scale);
        await _openPlanning(tester);
        await tester.tap(find.text('Neues Gericht anlegen'));
        await tester.pumpAndSettle();

        await _scrollTo(tester, const ValueKey('meal-component-add'));

        expect(tester.takeException(), isNull);
        viewModel.dispose();
      });
    });
  }
}

/// Die Listen bauen nur sichtbare Zeilen: erst zur Zeile scrollen.
Future<void> _scrollTo(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: _verticalScrollable().last,
  );
  await tester.pumpAndSettle();
  expect(find.byKey(key), findsOneWidget);
}

Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

Future<void> _openPlanning(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nutrition-more-menu')));
  await tester.pumpAndSettle();
  // Bei großer Schrift liegt die Aktion unterhalb des sichtbaren Bereichs.
  final action = find.text('Gerichte und Vorlagen verwalten');
  await tester.scrollUntilVisible(
    action,
    100,
    scrollable: _verticalScrollable().last,
  );
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<NutritionViewModel> _pump(
  WidgetTester tester,
  double scale, {
  bool withEntries = false,
  bool withTemplate = false,
}) async {
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
  if (withEntries) {
    var index = 0;
    for (final meal in NutritionMeal.values) {
      final id = (500 + index++).toString().padLeft(12, '0');
      await repository.saveEntry(
        _date,
        NutritionEntry(
          entryId: '00000000-0000-4000-8000-$id',
          meal: meal,
          position: 0,
          productName: 'Haferflocken mit Joghurt',
          brand: null,
          amountGrams: 100,
          per100Grams: const NutritionTotals(kilocalories: 360),
          source: null,
        ),
      );
    }
  }
  if (withTemplate) {
    await repository.saveDayAsTemplate(
      _date,
      name: 'Trainingstag',
      dayKind: NutritionDayKind.training,
    );
  }
  final viewModel = NutritionViewModel(
    repository: repository,
    localDate: _date,
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
  return viewModel;
}
