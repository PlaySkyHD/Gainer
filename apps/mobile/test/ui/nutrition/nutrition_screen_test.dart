import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000004';

void main() {
  testWidgets('manual diary entry is persisted as one local sync mutation', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final repository = NutritionRepository(
      store: store,
      ids: () => '00000000-0000-4000-8000-000000000005',
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Frühstück').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mittagessen').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).at(0),
      'Haferflocken',
    );
    await tester.enterText(find.byType(CupertinoTextField).at(2), '60');
    await tester.enterText(find.byType(CupertinoTextField).at(3), '370');
    await tester.scrollUntilVisible(
      find.text('Manuell speichern'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Manuell speichern'));
    await tester.pumpAndSettle();

    expect(viewModel.snapshot!.day.entries.single.productName, 'Haferflocken');
    expect(viewModel.snapshot!.day.entries.single.meal.name, 'lunch');
    expect(
      await store.readOutbox(aggregateType: 'nutrition-day'),
      hasLength(1),
    );
    expect(viewModel.statusMessage, contains('lokal gespeichert'));
  });

  testWidgets('day navigation and edit preserve food source provenance', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    var nextId = 15;
    final repository = NutritionRepository(
      store: store,
      ids: () =>
          '00000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}',
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    final source = NutritionSource(
      provider: 'Open Food Facts',
      barcode: '1234567890123',
      retrievedAtUtc: DateTime.utc(2026, 10, 1),
      basisGrams: 100,
    );
    await repository.saveEntry(
      '2026-10-12',
      NutritionEntry(
        entryId: '00000000-0000-4000-8000-000000000016',
        meal: NutritionMeal.breakfast,
        position: 0,
        productName: 'Joghurt',
        brand: 'Marke',
        amountGrams: 100,
        per100Grams: const NutritionTotals(kilocalories: 60),
        source: source,
      ),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.chevron_left).first);
    await tester.pumpAndSettle();
    expect(viewModel.localDate, '2026-10-11');
    expect(viewModel.snapshot!.day.localDate, '2026-10-11');
    await tester.tap(find.byIcon(CupertinoIcons.chevron_right).first);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Eintrag bearbeiten'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Eintrag bearbeiten'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(CupertinoAlertDialog),
      matching: find.byType(CupertinoTextField),
    );
    await tester.enterText(fields.at(2), '175');
    expect(
      tester.widget<CupertinoTextField>(fields.at(2)).controller!.text,
      '175',
    );
    await tester.ensureVisible(find.text('Änderungen speichern'));
    await tester.tap(find.text('Änderungen speichern'));
    await tester.pumpAndSettle();

    expect(viewModel.errorMessage, isNull, reason: viewModel.errorMessage);
    final edited = viewModel.snapshot!.day.entries.single;
    expect(edited.amountGrams, 175);
    expect(edited.source?.barcode, '1234567890123');
    expect(edited.source?.provider, 'Open Food Facts');
  });

  testWidgets(
    'manual recipe scales into immutable diary snapshots and archives',
    (tester) async {
      _usePhoneViewport(tester);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = LocalSyncStore(database: database, accountId: accountId);
      var nextId = 25;
      final repository = NutritionRepository(
        store: store,
        ids: () =>
            '00000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}',
        clock: () => DateTime.utc(2026, 10, 12, 10),
      );
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await tester.pumpWidget(
        CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Neues Gericht anlegen'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Neues Gericht anlegen'));
      await tester.tap(find.text('Neues Gericht anlegen'));
      await tester.pumpAndSettle();
      var fields = find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.byType(CupertinoTextField),
      );
      await tester.enterText(fields.at(0), 'Porridge');
      await tester.enterText(fields.at(3), 'Hafer');
      await tester.enterText(fields.at(4), 'Bio');
      await tester.enterText(fields.at(5), '50');
      await tester.enterText(fields.at(6), '380');
      await tester.ensureVisible(find.text('Bestandteil hinzufügen'));
      await tester.tap(find.text('Bestandteil hinzufügen'));
      await tester.pumpAndSettle();
      fields = find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.byType(CupertinoTextField),
      );
      await tester.enterText(fields.at(10), 'Milch');
      await tester.enterText(fields.at(12), '25');
      await tester.enterText(fields.at(13), '60');
      await tester.ensureVisible(find.text('Gericht speichern'));
      await tester.tap(find.text('Gericht speichern'));
      await tester.pumpAndSettle();
      expect(viewModel.snapshot!.meals.single.value.components, hasLength(2));
      expect(
        viewModel.snapshot!.meals.single.value.components.first.brand,
        'Bio',
      );

      await tester.ensureVisible(find.text('Übernehmen'));
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      final scaleField = find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.byType(CupertinoTextField),
      );
      await tester.enterText(scaleField, '2');
      await tester.tap(find.text('Übernehmen').last);
      await tester.pumpAndSettle();
      expect(
        viewModel.snapshot!.day.entries
            .map((entry) => entry.amountGrams)
            .toList(),
        [100, 50],
      );

      await tester.ensureVisible(find.text('Archivieren'));
      await tester.tap(find.text('Archivieren'));
      await tester.pumpAndSettle();
      expect(viewModel.snapshot!.meals.single.value.status, 'Archived');
      expect(
        viewModel.snapshot!.day.entries
            .map((entry) => entry.amountGrams)
            .toList(),
        [100, 50],
      );
    },
  );

  testWidgets('target phase form uses 4/4/9 and cancellation writes nothing', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final repository = NutritionRepository(
      store: store,
      ids: () => '00000000-0000-4000-8000-000000000035',
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Zielphase hinzufügen'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Zielphase hinzufügen'));
    await tester.tap(find.text('Zielphase hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen').last);
    await tester.pumpAndSettle();
    expect(
      await store.readOutbox(aggregateType: 'nutrition-target-schedule'),
      isEmpty,
    );

    await tester.tap(find.text('Zielphase hinzufügen'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(CupertinoAlertDialog),
      matching: find.byType(CupertinoTextField),
    );
    await tester.enterText(fields.at(0), 'Aufbau');
    await tester.enterText(fields.at(1), '2026-10-13');
    await tester.ensureVisible(find.text('Zielphase speichern'));
    await tester.tap(find.text('Zielphase speichern'));
    await tester.pumpAndSettle();
    final phase = viewModel.snapshot!.targetSchedule!.versions.single;
    expect(phase.proteinGrams, 125);
    expect(phase.carbohydrateGrams, 250);
    expect(phase.fatGrams, closeTo(55.56, .01));
  });

  testWidgets(
    'current target phase is read-only while future phase is editable',
    (tester) async {
      _usePhoneViewport(tester);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = LocalSyncStore(database: database, accountId: accountId);
      var nextId = 45;
      final repository = NutritionRepository(
        store: store,
        ids: () =>
            '00000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}',
        clock: () => DateTime.utc(2026, 10, 12, 10),
      );
      final current = _targetPhase(
        id: '00000000-0000-4000-8000-000000000046',
        name: 'Aktuelles Ziel',
        from: '2026-10-01',
        until: '2026-10-19',
      );
      final future = _targetPhase(
        id: '00000000-0000-4000-8000-000000000047',
        name: 'Künftiges Ziel',
        from: '2026-10-20',
      );
      await repository.saveTargetSchedule(
        NutritionTargetSchedule(versions: [current, future]),
      );
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await tester.pumpWidget(
        CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Aktuelles Ziel'),
        240,
        scrollable: find.byType(Scrollable).first,
      );

      final currentRow = find.byKey(
        const ValueKey('target-phase-00000000-0000-4000-8000-000000000046'),
      );
      expect(
        find.descendant(of: currentRow, matching: find.text('Bearbeiten')),
        findsNothing,
      );
      expect(
        find.descendant(of: currentRow, matching: find.text('Entfernen')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('Künftiges Ziel'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      final futureRow = find.byKey(
        const ValueKey('target-phase-00000000-0000-4000-8000-000000000047'),
      );
      expect(
        find.descendant(of: futureRow, matching: find.text('Bearbeiten')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: futureRow, matching: find.text('Entfernen')),
        findsOneWidget,
      );
      final outboxBefore = await store.readOutbox(
        aggregateType: 'nutrition-target-schedule',
      );
      expect(outboxBefore, hasLength(1));
      expect(
        await store.readOutbox(aggregateType: 'nutrition-target-schedule'),
        hasLength(1),
      );
    },
  );
}

NutritionTargetVersion _targetPhase({
  required String id,
  required String name,
  required String from,
  String? until,
}) => NutritionTargetVersion(
  targetVersionId: id,
  name: name,
  category: NutritionTargetCategory.custom,
  effectiveFrom: from,
  effectiveUntil: until,
  inputMode: NutritionTargetInputMode.grams,
  kilocalories: 2000,
  proteinGrams: 125,
  carbohydrateGrams: 250,
  fatGrams: 55,
  proteinPercent: null,
  carbohydratePercent: null,
  fatPercent: null,
);

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
