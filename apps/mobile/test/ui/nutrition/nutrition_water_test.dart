import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/water_intake_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_water_card.dart';

const _accountId = '00000000-0000-4000-8000-000000000091';
const _day = '2026-10-25';

class _Harness {
  _Harness(this.database, this.store, this.repository, this.viewModel);

  final LocalDatabase database;
  final LocalSyncStore store;
  final NutritionRepository repository;
  final NutritionViewModel viewModel;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool waterEnabled = true,
  int goalMl = 2500,
  int waterMl = 0,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final store = LocalSyncStore(database: database, accountId: _accountId);
  var next = 300;
  final repository = NutritionRepository(
    store: store,
    ids: () =>
        '00000000-0000-4000-8000-${(++next).toString().padLeft(12, '0')}',
    clock: () => DateTime.utc(2026, 10, 25, 9),
  );
  if (waterEnabled) {
    await repository.preferences.update(
      (current) => current.copyWith(waterEnabled: true, waterGoalMl: goalMl),
    );
  }
  if (waterMl > 0) await repository.water.setAmount(_day, waterMl);
  final viewModel = NutritionViewModel(repository: repository, localDate: _day);
  addTearDown(viewModel.dispose);
  await tester.pumpWidget(
    CupertinoApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: GainerDesign(child: child!),
      ),
      home: NutritionScreen(viewModel: viewModel),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(database, store, repository, viewModel);
}

Finder get _amount => find.byKey(const ValueKey('nutrition-water-amount'));

Finder _add(int ml) => find.byKey(ValueKey('nutrition-water-add-$ml'));

String _valueText(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: _amount, matching: find.byType(Text)))
    .map((text) => text.data)
    .whereType<String>()
    .firstWhere((text) => text.endsWith(' ml'));

bool _enabled(WidgetTester tester, int ml) =>
    tester
        .widget<CupertinoButton>(
          find.descendant(of: _add(ml), matching: find.byType(CupertinoButton)),
        )
        .onPressed !=
    null;

void main() {
  testWidgets('the water card is hidden by default', (tester) async {
    await _pump(tester, waterEnabled: false);

    expect(_amount, findsNothing);
    expect(find.text('Wasser'), findsNothing);
  });

  testWidgets('quick buttons add water offline as one waiting change', (
    tester,
  ) async {
    final harness = await _pump(tester, waterMl: 750);
    expect(_valueText(tester), '750 / 2.500 ml');

    await tester.tap(_add(500));
    await tester.pumpAndSettle();
    expect(_valueText(tester), '1.250 / 2.500 ml');

    await tester.tap(_add(200));
    await tester.pumpAndSettle();
    await tester.tap(_add(300));
    await tester.pumpAndSettle();
    expect(_valueText(tester), '1.750 / 2.500 ml');

    expect(
      await harness.store.readOutbox(aggregateType: waterIntakeAggregateType),
      hasLength(1),
    );
    expect(await harness.repository.water.read(_day), 1750);
  });

  testWidgets('tapping the amount corrects the day total', (tester) async {
    final harness = await _pump(tester, waterMl: 1300);

    await tester.tap(_amount);
    await tester.pumpAndSettle();
    expect(find.byType(WaterAmountSheet), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('nutrition-water-field')),
      '800',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nutrition-water-save')));
    await tester.pumpAndSettle();

    expect(find.byType(WaterAmountSheet), findsNothing);
    expect(_valueText(tester), '800 / 2.500 ml');
    expect(await harness.repository.water.read(_day), 800);
  });

  testWidgets('an invalid amount shows an error and saves nothing', (
    tester,
  ) async {
    final harness = await _pump(tester, waterMl: 500);

    await tester.tap(_amount);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('nutrition-water-field')),
      '12000',
    );
    await tester.pump();

    expect(find.text('Erlaubt sind 0 bis 10.000 ml.'), findsOneWidget);
    final save = tester.widget<CupertinoButton>(
      find.descendant(
        of: find.byKey(const ValueKey('nutrition-water-save')),
        matching: find.byType(CupertinoButton),
      ),
    );
    expect(save.onPressed, isNull);
    expect(await harness.repository.water.read(_day), 500);
  });

  testWidgets('reset sets the day to zero and is unavailable at zero', (
    tester,
  ) async {
    final harness = await _pump(tester, waterMl: 600);

    await tester.tap(_amount);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-water-reset')));
    await tester.pumpAndSettle();
    expect(_valueText(tester), '0 / 2.500 ml');
    expect(await harness.repository.water.read(_day), 0);

    await tester.tap(_amount);
    await tester.pumpAndSettle();
    expect(
      find.text('Für diesen Tag ist noch kein Wasser erfasst.'),
      findsOneWidget,
    );
    final reset = tester.widget<CupertinoButton>(
      find.descendant(
        of: find.byKey(const ValueKey('nutrition-water-reset')),
        matching: find.byType(CupertinoButton),
      ),
    );
    expect(reset.onPressed, isNull);
  });

  testWidgets('buttons that would pass the daily limit are disabled', (
    tester,
  ) async {
    await _pump(tester, waterMl: 9800);

    // 9.800 + 200 ergibt genau die Grenze von 10.000 ml.
    expect(_enabled(tester, 200), isTrue);
    expect(_enabled(tester, 300), isFalse);
    expect(_enabled(tester, 500), isFalse);

    await tester.tap(_add(200));
    await tester.pumpAndSettle();
    expect(_valueText(tester), '10.000 / 2.500 ml');
    expect(_enabled(tester, 200), isFalse);
  });

  testWidgets('a failed change shows an error above the diary', (tester) async {
    final harness = await _pump(tester, waterMl: 9900);

    final saved = await harness.viewModel.addWater(500);
    await tester.pumpAndSettle();

    expect(saved, isFalse);
    expect(
      find.text('Mehr als 10.000 ml am Tag sind nicht möglich.'),
      findsOneWidget,
    );
    expect(_valueText(tester), '9.900 / 2.500 ml');
  });

  testWidgets('the card fits at text size 2', (tester) async {
    await _pump(tester, waterMl: 1250, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(_amount, findsOneWidget);
    await tester.ensureVisible(_add(500));
    await tester.pumpAndSettle();
    await tester.tap(_add(500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_valueText(tester), '1.750 / 2.500 ml');
  });

  testWidgets('settings turn water on and set the goal', (tester) async {
    final harness = await _pump(tester, waterEnabled: false);

    await tester.tap(find.byKey(const ValueKey('nutrition-more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('nutrition-settings-water-goal')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('nutrition-settings-water')));
    await tester.pumpAndSettle();
    final goal = find.byKey(const ValueKey('nutrition-settings-water-goal'));
    await tester.enterText(goal, '100');
    await tester.pump();
    expect(find.text('Erlaubt sind 250 bis 10.000 ml.'), findsOneWidget);
    await tester.enterText(goal, '3000');
    await tester.pumpAndSettle();
    expect(find.text('Erlaubt sind 250 bis 10.000 ml.'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_valueText(tester), '0 / 3.000 ml');
    final stored = await harness.repository.preferences.read();
    expect(stored.waterEnabled, isTrue);
    expect(stored.waterGoalMl, 3000);
  });
}
