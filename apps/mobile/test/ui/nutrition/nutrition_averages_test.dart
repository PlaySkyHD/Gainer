import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_averages_view.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000004';
const today = '2026-10-19';

/// Wochenbeispiel der Spezifikation (5 von 7 Tagen, Ø 2.160 kcal).
const weekEntries = <(String, double, double, double, double)>[
  ('2026-10-13', 2000, 120, 250, 70),
  ('2026-10-14', 2300, 150, 260, 80),
  ('2026-10-15', 2530, 160, 300, 90),
  ('2026-10-17', 2070, 140, 230, 70),
  ('2026-10-19', 1900, 130, 200, 60),
];

Future<NutritionRepository> seededRepository({
  bool withTarget = true,
  bool withEntries = true,
}) async {
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final repository = NutritionRepository(
    store: LocalSyncStore(database: database, accountId: accountId),
    clock: () => DateTime(2026, 10, 19, 10),
  );
  if (withTarget) {
    await repository.saveTargetSchedule(
      NutritionTargetSchedule(
        versions: [
          NutritionTargetVersion(
            targetVersionId: '00000000-0000-4000-8000-000000000060',
            name: 'Erhalt',
            category: NutritionTargetCategory.maintenance,
            effectiveFrom: '2026-09-01',
            effectiveUntil: null,
            inputMode: NutritionTargetInputMode.grams,
            kilocalories: 2300,
            proteinGrams: 150,
            carbohydrateGrams: 250,
            fatGrams: 70,
            proteinPercent: null,
            carbohydratePercent: null,
            fatPercent: null,
          ),
        ],
      ),
    );
  }
  if (withEntries) {
    var index = 0;
    for (final (date, kcal, protein, carbs, fat) in weekEntries) {
      index++;
      await repository.saveEntry(
        date,
        NutritionEntry(
          entryId:
              '00000000-0000-4000-8000-0000000002${index.toString().padLeft(2, '0')}',
          meal: NutritionMeal.lunch,
          position: 0,
          productName: 'Essen',
          brand: null,
          amountGrams: 100,
          per100Grams: NutritionTotals(
            kilocalories: kcal,
            proteinGrams: protein,
            carbohydrateGrams: carbs,
            fatGrams: fat,
          ),
          source: null,
        ),
      );
    }
  }
  return repository;
}

Widget app(Widget home, {double textScale = 1}) => CupertinoApp(
  debugShowCheckedModeBanner: false,
  theme: GainerTheme.forBrightness(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      platformBrightness: Brightness.light,
      textScaler: TextScaler.linear(textScale),
    ),
    child: GainerDesign(child: child!),
  ),
  home: home,
);

void main() {
  testWidgets('day view shows the averages entry and opens the sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await seededRepository();
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: today,
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(app(NutritionScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.text('Durchschnitt'), findsOneWidget);
    expect(find.text('Ø 7 Tage 2.160 kcal · Protein 140 g'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nutrition-averages-entry')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ø 2.160'), findsOneWidget);
    expect(find.text('pro erfasstem Tag'), findsOneWidget);
    expect(find.text('5 von 7 Tagen erfasst'), findsOneWidget);
    expect(find.text('Ziel Ø 2.300 kcal'), findsOneWidget);
    expect(find.text('3 von 5 Tagen im Zielbereich ±10 %'), findsOneWidget);
    expect(find.text('248 g'), findsOneWidget);
    expect(find.text('2 Tage nichts erfasst'), findsOneWidget);
  });

  testWidgets('entry updates after a new entry is saved', (tester) async {
    tester.view.physicalSize = const Size(390, 1480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await seededRepository();
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: today,
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(app(NutritionScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();
    await viewModel.removeEntry(viewModel.snapshot!.day.entries.single.entryId);
    await tester.pumpAndSettle();
    // Ohne Einträge heute endet das Fenster gestern: 4 Tage, Ø 2.225 kcal.
    expect(find.text('Ø 7 Tage 2.225 kcal · Protein 143 g'), findsOneWidget);
  });

  testWidgets('empty state without any entries', (tester) async {
    final repository = await seededRepository(withEntries: false);
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: today,
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(app(NutritionScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.text('Noch keine Einträge'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nutrition-averages-entry')));
    await tester.pumpAndSettle();
    // Ohne Daten öffnet die Zeile kein Sheet (nur die Zeile selbst heißt so).
    expect(find.text('Durchschnitt'), findsOneWidget);
    expect(find.text('7 Tage'), findsNothing);
  });

  testWidgets('segmented control switches between 7 and 30 days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await seededRepository();
    final overview = await repository.readAverages(today);
    await tester.pumpWidget(
      app(
        CupertinoPageScaffold(
          child: NutritionAveragesSheet(overview: overview),
        ),
      ),
    );
    expect(find.text('5 von 7 Tagen erfasst'), findsOneWidget);

    await tester.tap(find.text('30 Tage'));
    await tester.pumpAndSettle();
    expect(find.text('5 von 30 Tagen erfasst'), findsOneWidget);
    expect(find.text('25 Tage nichts erfasst'), findsOneWidget);
    expect(find.textContaining('Ø 2.160'), findsOneWidget);

    await tester.tap(find.text('7 Tage'));
    await tester.pumpAndSettle();
    expect(find.text('5 von 7 Tagen erfasst'), findsOneWidget);
  });

  testWidgets('without target no comparison is shown', (tester) async {
    tester.view.physicalSize = const Size(390, 1480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await seededRepository(withTarget: false);
    final overview = await repository.readAverages(today);
    await tester.pumpWidget(
      app(
        CupertinoPageScaffold(
          child: NutritionAveragesSheet(overview: overview),
        ),
      ),
    );
    expect(find.textContaining('Zielbereich'), findsNothing);
    expect(find.textContaining('Ziel Ø'), findsNothing);
  });

  testWidgets('text scale 2 does not overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 1480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await seededRepository();
    final overview = await repository.readAverages(today);
    await tester.pumpWidget(
      app(
        CupertinoPageScaffold(
          child: NutritionAveragesSheet(overview: overview),
        ),
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
