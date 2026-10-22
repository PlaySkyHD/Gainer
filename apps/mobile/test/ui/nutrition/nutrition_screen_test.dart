import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/api_nutrition_online_provider.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000004';

void main() {
  test(
    'failed day selection keeps the previous matching snapshot and can retry',
    () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = _ControlledNutritionRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      );
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await viewModel.load();
      final oldSnapshot = viewModel.snapshot;
      final pending = Completer<NutritionSnapshot>();
      repository.pendingReads['2026-10-13'] = pending;

      final selecting = viewModel.selectDate('2026-10-13');
      pending.completeError(StateError('temporary read failure'));
      await selecting;

      expect(viewModel.snapshot, same(oldSnapshot));
      expect(viewModel.localDate, '2026-10-12');
      expect(viewModel.snapshot!.day.localDate, viewModel.localDate);
      expect(viewModel.errorOperation, NutritionErrorOperation.day);
      expect(viewModel.errorMessage, contains('temporary read failure'));

      repository.pendingReads.remove('2026-10-13');
      await viewModel.load();
      expect(viewModel.localDate, '2026-10-13');
      expect(viewModel.snapshot!.day.localDate, '2026-10-13');
      expect(viewModel.errorMessage, isNull);
      viewModel.dispose();
    },
  );

  test('overlapping day reads only publish the latest selected date', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _ControlledNutritionRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await viewModel.load();
    final earlier = Completer<NutritionSnapshot>();
    final latest = Completer<NutritionSnapshot>();
    repository.pendingReads['2026-10-13'] = earlier;
    repository.pendingReads['2026-10-14'] = latest;

    final firstSelection = viewModel.selectDate('2026-10-13');
    final secondSelection = viewModel.selectDate('2026-10-14');
    latest.complete(_snapshotFor('2026-10-14'));
    await secondSelection;
    earlier.complete(_snapshotFor('2026-10-13'));
    await firstSelection;

    expect(viewModel.localDate, '2026-10-14');
    expect(viewModel.snapshot!.day.localDate, '2026-10-14');
    expect(viewModel.isLoading, isFalse);
    viewModel.dispose();
  });

  testWidgets('failed diary removal remains visible on the day overview', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _ControlledNutritionRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    )..failRemoval = true;
    const entryId = '00000000-0000-4000-8000-000000000099';
    await repository.saveEntry(
      '2026-10-12',
      NutritionEntry(
        entryId: entryId,
        meal: NutritionMeal.breakfast,
        position: 0,
        productName: 'Joghurt',
        brand: null,
        amountGrams: 100,
        per100Grams: const NutritionTotals(kilocalories: 60),
        source: null,
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
    await tester.drag(
      find.byKey(ValueKey('nutrition-entry-$entryId')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();

    expect(viewModel.errorOperation, NutritionErrorOperation.diary);
    expect(
      find.text(viewModel.errorMessage!),
      findsOneWidget,
      reason:
          '${viewModel.errorMessage} / ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
    );
    expect(viewModel.snapshot!.day.entries.single.entryId, entryId);
    viewModel.dispose();
  });

  testWidgets(
    'failed entry save stays in editor and remains visible after cancel',
    (tester) async {
      _usePhoneViewport(tester);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = _ControlledNutritionRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      );
      const entryId = '00000000-0000-4000-8000-000000000098';
      await repository.saveEntry(
        '2026-10-12',
        NutritionEntry(
          entryId: entryId,
          meal: NutritionMeal.breakfast,
          position: 0,
          productName: 'Joghurt',
          brand: null,
          amountGrams: 100,
          per100Grams: const NutritionTotals(kilocalories: 60),
          source: null,
        ),
      );
      repository.failSave = true;
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await tester.pumpWidget(
        CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey('nutrition-entry-$entryId'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sichern'));
      await tester.pumpAndSettle();

      expect(find.text('Eintrag bearbeiten'), findsOneWidget);
      expect(
        find.text(viewModel.errorMessage!),
        findsOneWidget,
        reason:
            '${viewModel.errorMessage} / ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
      );
      expect(viewModel.snapshot!.day.entries.single.productName, 'Joghurt');
      expect(viewModel.errorOperation, NutritionErrorOperation.diary);
      await tester.tap(find.byKey(const ValueKey('nutrition-edit-close')));
      await tester.pumpAndSettle();
      expect(viewModel.errorMessage, isNotNull);
      expect(viewModel.errorOperation, NutritionErrorOperation.diary);
      expect(
        find.text(viewModel.errorMessage!),
        findsOneWidget,
        reason:
            '${viewModel.errorMessage} / ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
      );
      viewModel.dispose();
    },
  );

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
    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mittag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manuell erfassen'));
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('nutrition-entry-name'));
    final amount = find.byKey(const ValueKey('nutrition-entry-amount'));
    final kcal = find.byKey(const ValueKey('nutrition-entry-kcal'));
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Haferflocken');
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '60');
    await tester.ensureVisible(kcal);
    await tester.enterText(kcal, '370');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    // Bis ganz nach unten scrollen; das Formular ist mit Salz länger.
    await tester.scrollUntilVisible(
      find.text('Manuell speichern').hitTestable(),
      240,
      scrollable: _sheetScrollable(),
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

  testWidgets('nutrition overview keeps forms behind contextual routes', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final repository = NutritionRepository(
      store: store,
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

    expect(find.text('Heute'), findsOneWidget);
    expect(find.text('Montag, 12. Oktober'), findsNothing);
    expect(find.byKey(const ValueKey('nutrition-add-food')), findsOneWidget);
    expect(find.text('Gerichte und Ziele verwalten'), findsNothing);
    expect(find.text('Noch nichts eingetragen'), findsNothing);
    expect(find.text('Hinzufügen'), findsNWidgets(4));
    expect(find.byType(CupertinoTextField), findsNothing);
    expect(find.byKey(const ValueKey('meal-add-breakfast')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('meal-add-breakfast')));
    await tester.pumpAndSettle();
    expect(viewModel.selectedMeal, NutritionMeal.breakfast);
    expect(find.byType(CupertinoTextField), findsNothing);
    await tester.tap(find.text('Manuell erfassen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nutrition-entry-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('nutrition-entry-kcal')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nutrition-entry-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-entry-close')));
    await tester.pumpAndSettle();
    expect(viewModel.snapshot!.day.entries, isEmpty);
    expect(await store.readOutbox(aggregateType: 'nutrition-day'), isEmpty);
    expect(find.byKey(const ValueKey('nutrition-entry-name')), findsNothing);
  });

  testWidgets('opening the diary is local and action errors stay contextual', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final online = _FailingNutritionOnlineProvider();
    final repository = NutritionRepository(
      store: store,
      online: online,
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

    expect(online.searchCalls, 0);
    expect(viewModel.snapshot!.day.localDate, '2026-10-12');

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel suchen'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('nutrition-entry-search'));
    await tester.scrollUntilVisible(
      search,
      220,
      scrollable: _sheetScrollable(),
    );
    await tester.enterText(search, 'Haferdrink');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(online.searchCalls, 1);
    expect(
      find.textContaining('Fehlerkennung: nutrition_import_not_supported'),
      findsOneWidget,
    );
    expect(viewModel.errorOperation, NutritionErrorOperation.search);

    await tester.tap(find.byKey(const ValueKey('nutrition-entry-options')));
    await tester.pumpAndSettle();
    expect(find.textContaining('nutrition_import_not_supported'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nutrition-entry-close')));
    await tester.pumpAndSettle();
    expect(viewModel.snapshot!.day.localDate, '2026-10-12');
    expect(find.textContaining('nutrition_import_not_supported'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    expect(find.textContaining('nutrition_import_not_supported'), findsNothing);
    expect(viewModel.snapshot!.day.localDate, '2026-10-12');
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
      find.byKey(
        const ValueKey('nutrition-entry-00000000-0000-4000-8000-000000000016'),
      ),
      250,
      scrollable: _verticalScrollable(),
    );
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('nutrition-entry-00000000-0000-4000-8000-000000000016'),
      ),
    );
    await tester.pumpAndSettle();
    final amountField = find.byKey(const ValueKey('nutrition-edit-amount'));
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    await tester.enterText(amountField, '175');
    expect(
      tester.widget<CupertinoTextField>(amountField).controller!.text,
      '175',
    );
    await tester.ensureVisible(find.text('Sichern'));
    await tester.tap(find.text('Sichern'));
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

      await _openPlanning(tester);

      await tester.scrollUntilVisible(
        find.text('Neues Gericht anlegen'),
        260,
        scrollable: _verticalScrollable(),
      );
      await tester.ensureVisible(find.text('Neues Gericht anlegen'));
      await tester.tap(find.text('Neues Gericht anlegen'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      await tester.enterText(find.byType(CupertinoTextField).at(0), 'Porridge');
      await _addManualComponent(
        tester,
        name: 'Hafer',
        brand: 'Bio',
        amount: '50',
        kcal: '380',
      );
      await _addManualComponent(
        tester,
        name: 'Milch',
        amount: '25',
        kcal: '60',
      );
      expect(find.text('Hafer'), findsOneWidget);
      expect(find.text('Milch'), findsOneWidget);
      await tester.tap(find.text('Sichern'));
      await tester.pumpAndSettle();
      expect(viewModel.snapshot!.meals.single.value.components, hasLength(2));
      expect(
        viewModel.snapshot!.meals.single.value.components.first.brand,
        'Bio',
      );

      await tester.longPress(find.text('Porridge'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField).last, '2');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen').last);
      await tester.pumpAndSettle();
      expect(
        viewModel.snapshot!.day.entries
            .map((entry) => entry.amountGrams)
            .toList(),
        [100, 50],
      );

      await tester.longPress(find.text('Porridge'));
      await tester.pumpAndSettle();
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

    await _openPlanning(tester);

    await tester.scrollUntilVisible(
      find.text('Zielphase hinzufügen'),
      260,
      scrollable: _verticalScrollable(),
    );
    await tester.ensureVisible(find.text('Zielphase hinzufügen'));
    await tester.tap(find.text('Zielphase hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-target-close')));
    await tester.pumpAndSettle();
    expect(
      await store.readOutbox(aggregateType: 'nutrition-target-schedule'),
      isEmpty,
    );

    await tester.tap(find.text('Zielphase hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    final fields = find.byType(CupertinoTextField);
    await tester.enterText(fields.at(0), 'Aufbau');
    await tester.enterText(fields.at(1), '2026-10-13');
    await tester.ensureVisible(find.text('Sichern'));
    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();
    final phase = viewModel.snapshot!.targetSchedule!.versions.single;
    expect(phase.proteinGrams, 125);
    expect(phase.carbohydrateGrams, 250);
    expect(phase.fatGrams, closeTo(55.56, .01));
    // Der Standard von 6 g bleibt offen, statt fest gespeichert zu werden.
    expect(phase.saltGrams, isNull);
    expect(phase.effectiveSaltGrams, 6);
  });

  testWidgets('own salt is added to a meal as a zero-calorie entry', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, []);

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mittag'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('nutrition-mode-salt')),
    );
    await tester.tap(find.byKey(const ValueKey('nutrition-mode-salt')));
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('nutrition-salt-add'));
    expect(tester.widget<GainerPillButton>(add).onPressed, isNull);

    await tester.tap(find.text('Teelöffel'));
    await tester.pump();
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();

    final entry = harness.viewModel.snapshot!.day.entries.single;
    expect(entry.productName, 'Salz');
    expect(entry.meal, NutritionMeal.lunch);
    expect(entry.totals.kilocalories, 0);
    expect(entry.totals.saltGrams, 6);
    expect(harness.viewModel.snapshot!.day.totals.saltGrams, 6);

    await tester.enterText(
      find.byKey(const ValueKey('nutrition-salt-amount')),
      '0,8',
    );
    await tester.pump();
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(harness.viewModel.snapshot!.day.totals.saltGrams, 6.8);
  });

  testWidgets('target phase stores a custom salt limit', (tester) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = NutritionRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
      ids: () => '00000000-0000-4000-8000-000000000036',
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
    await _openPlanning(tester);
    await tester.scrollUntilVisible(
      find.text('Zielphase hinzufügen'),
      260,
      scrollable: _verticalScrollable(),
    );
    await tester.tap(find.text('Zielphase hinzufügen'));
    await tester.pumpAndSettle();
    final fields = find.byType(CupertinoTextField);
    await tester.enterText(fields.at(0), 'Weniger Salz');
    await tester.enterText(fields.at(1), '2026-10-13');
    final salt = find.byKey(const ValueKey('nutrition-target-salt'));
    await tester.ensureVisible(salt);
    expect(tester.widget<CupertinoTextField>(salt).controller!.text, '6');
    await tester.enterText(salt, '0');
    await tester.pump();
    expect(find.text('Sichern').hitTestable(), findsOneWidget);
    expect(
      tester
          .widget<GainerPillButton>(
            find.ancestor(
              of: find.text('Sichern'),
              matching: find.byType(GainerPillButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(salt, '5');
    await tester.pump();
    await tester.ensureVisible(find.text('Sichern'));
    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();
    final phase = viewModel.snapshot!.targetSchedule!.versions.single;
    expect(phase.saltGrams, 5);
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
      expect(find.text('0 von 2.000 kcal'), findsOneWidget);
      await _openPlanning(tester);
      await tester.scrollUntilVisible(
        find.text('Aktuelles Ziel'),
        240,
        scrollable: _verticalScrollable(),
      );

      final currentRow = find.byKey(
        const ValueKey('target-phase-00000000-0000-4000-8000-000000000046'),
      );
      expect(
        find.descendant(of: currentRow, matching: find.byType(Dismissible)),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('Künftiges Ziel'),
        180,
        scrollable: _verticalScrollable(),
      );
      final futureRow = find.byKey(
        const ValueKey('target-phase-00000000-0000-4000-8000-000000000047'),
      );
      expect(
        find.descendant(of: futureRow, matching: find.byType(Dismissible)),
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
  testWidgets('swiping an entry left deletes only after confirmation', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, ['Joghurt']);
    final key = ValueKey('nutrition-entry-${harness.entryIds.single}');

    await tester.drag(find.byKey(key), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(harness.viewModel.snapshot!.day.entries, hasLength(1));
    expect(find.byKey(key), findsOneWidget);

    await tester.drag(find.byKey(key), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();
    expect(harness.viewModel.snapshot!.day.entries, isEmpty);
    expect(find.byKey(key), findsNothing);
    expect(find.text('Noch nichts eingetragen'), findsNothing);
  });

  testWidgets('long press opens the entry sheet with a destructive remove', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, ['Joghurt', 'Haferflocken']);
    final key = ValueKey('nutrition-entry-${harness.entryIds.first}');

    await tester.longPress(find.byKey(key));
    await tester.pumpAndSettle();
    expect(find.text('Verschieben'), findsOneWidget);
    expect(find.text('Entfernen'), findsOneWidget);

    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();
    expect(harness.viewModel.snapshot!.day.entries.map((e) => e.productName), [
      'Haferflocken',
    ]);
  });

  testWidgets('moving an entry in the reorder sheet persists the new order', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, ['Joghurt', 'Haferflocken']);

    await tester.longPress(
      find.byKey(ValueKey('nutrition-entry-${harness.entryIds.first}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verschieben'));
    await tester.pumpAndSettle();
    expect(find.text('Einträge anordnen'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ReorderableDragStartListener).first),
    );
    await tester.pump();
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();

    final ordered = [...harness.viewModel.snapshot!.day.entries]
      ..sort((a, b) => a.position.compareTo(b.position));
    expect(ordered.map((e) => e.productName), ['Haferflocken', 'Joghurt']);
  });

  testWidgets('future target phase is removed by swipe after confirmation', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final repository = NutritionRepository(
      store: store,
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    const futureId = '00000000-0000-4000-8000-000000000047';
    await repository.saveTargetSchedule(
      NutritionTargetSchedule(
        versions: [
          _targetPhase(
            id: '00000000-0000-4000-8000-000000000046',
            name: 'Aktuelles Ziel',
            from: '2026-10-01',
            until: '2026-10-19',
          ),
          _targetPhase(
            id: futureId,
            name: 'Künftiges Ziel',
            from: '2026-10-20',
          ),
        ],
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
    await _openPlanning(tester);

    final row = find.byKey(const ValueKey('target-phase-$futureId'));
    await tester.scrollUntilVisible(
      row,
      180,
      scrollable: _verticalScrollable(),
    );
    await tester.drag(row, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Zielphase entfernen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(
      (await store.readOutbox(aggregateType: 'nutrition-target-schedule')),
      hasLength(1),
    );

    await tester.drag(row, const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    expect(viewModel.snapshot!.targetSchedule!.versions, hasLength(1));
    expect(
      viewModel.snapshot!.targetSchedule!.versions.single.name,
      'Aktuelles Ziel',
    );
    viewModel.dispose();
  });
  testWidgets('date pill shows relative labels and opens the date picker', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, []);

    expect(find.text('Heute'), findsOneWidget);
    expect(find.text('Tagesübersicht'), findsNothing);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_left).first);
    await tester.pumpAndSettle();
    expect(find.text('Gestern'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_left).first);
    await tester.pumpAndSettle();
    expect(find.text('Sa. 10. Okt.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nutrition-date-pill')));
    await tester.pumpAndSettle();
    expect(find.text('Tag auswählen'), findsOneWidget);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(harness.viewModel.localDate, '2026-10-10');
  });

  testWidgets('day card without targets shows actuals and a targets action', (
    tester,
  ) async {
    await _pumpDiary(tester, ['Joghurt']);

    expect(find.text('Tagesziele festlegen'), findsOneWidget);
    expect(find.textContaining('trotzdem angezeigt'), findsNothing);
    expect(find.text('Protein'), findsOneWidget);
    // Protein, Kohlenhydrate, Fett und Salz ohne Angabe.
    expect(find.text('– g'), findsNWidgets(4));
  });

  testWidgets('day card with targets shows progress and remaining kcal', (
    tester,
  ) async {
    final harness = await _pumpDiary(
      tester,
      ['Joghurt'],
      schedule: NutritionTargetSchedule(
        versions: [
          _targetPhase(
            id: '00000000-0000-4000-8000-000000000046',
            name: 'Aktuelles Ziel',
            from: '2026-10-01',
          ),
        ],
      ),
    );

    expect(find.text('60 von 2.000 kcal'), findsOneWidget);
    expect(find.text('1.940 übrig'), findsOneWidget);
    expect(find.text('Tagesziele festlegen'), findsNothing);
    expect(harness.viewModel.snapshot!.targetSchedule, isNotNull);
  });

  testWidgets('add sheet offers the meal segment and capture paths', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, []);

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    final segment = find.byType(GainerSegmentedControl<NutritionMeal>);
    for (final label in ['Frühstück', 'Mittag', 'Abend', 'Snacks']) {
      expect(
        find.descendant(of: segment, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(find.text('Abbrechen'), findsNothing);
    expect(find.text('Zuletzt verwendet'), findsOneWidget);
    expect(find.text('Gespeicherte Gerichte'), findsOneWidget);
    expect(find.text('Manuell erfassen'), findsOneWidget);

    await tester.tap(find.text('Abend'));
    await tester.pumpAndSettle();
    expect(harness.viewModel.selectedMeal, NutritionMeal.dinner);
    await tester.tap(find.byKey(const ValueKey('nutrition-entry-close')));
    await tester.pumpAndSettle();
    expect(find.text('Zuletzt verwendet'), findsNothing);
  });

  testWidgets(
    'meal component is added through the shared dialog without touching a day',
    (tester) async {
      final harness = await _pumpDiary(tester, []);

      await _openPlanning(tester);
      await tester.tap(find.text('Neues Gericht anlegen'));
      await tester.pumpAndSettle();
      expect(find.text('Neues Gericht'), findsOneWidget);
      expect(find.text('Abbrechen'), findsNothing);
      await tester.enterText(find.byType(CupertinoTextField).at(0), 'Bowl');
      expect(
        tester
            .widget<GainerPillButton>(find.byType(GainerPillButton))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('meal-component-add')));
      await tester.pumpAndSettle();
      expect(find.text('Bestandteil hinzufügen'), findsWidgets);
      expect(find.text('Mittag'), findsNothing);
      expect(find.text('Gespeicherte Gerichte'), findsNothing);
      expect(find.text('Mahlzeit schätzen'), findsNothing);
      await tester.tap(find.text('Manuell erfassen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-entry-name')),
        'Reis',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-entry-amount')),
        '200',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-entry-kcal')),
        '130',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      expect(find.text('Reis'), findsOneWidget);
      expect(find.text('200 g · 260 kcal'), findsOneWidget);
      expect(harness.viewModel.snapshot!.day.entries, isEmpty);
      expect(
        await harness.store.readOutbox(aggregateType: 'nutrition-day'),
        isEmpty,
      );

      await tester.tap(find.text('Sichern'));
      await tester.pumpAndSettle();
      final meal = harness.viewModel.snapshot!.meals.single.value;
      expect(meal.name, 'Bowl');
      expect(meal.components.single.name, 'Reis');
      expect(harness.viewModel.snapshot!.day.entries, isEmpty);
      expect(
        await harness.store.readOutbox(aggregateType: 'nutrition-day'),
        isEmpty,
      );
    },
  );

  testWidgets('cancelling or failing the component dialog keeps the draft', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, []);

    await _openPlanning(tester);
    await tester.tap(find.text('Neues Gericht anlegen'));
    await tester.pumpAndSettle();
    await _addManualComponent(tester, name: 'Hafer', amount: '50', kcal: '380');

    // Abbrechen über das X lässt die Liste unverändert.
    await tester.tap(find.byKey(const ValueKey('meal-component-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-entry-close')));
    await tester.pumpAndSettle();
    expect(find.text('Hafer'), findsOneWidget);

    // Ungültige Werte lassen den Dialog offen und den Entwurf unverändert.
    await tester.tap(find.byKey(const ValueKey('meal-component-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manuell erfassen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('nutrition-entry-name')),
      'Fehler',
    );
    await tester.enterText(
      find.byKey(const ValueKey('nutrition-entry-kcal')),
      '-5',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    // 0 kcal ist erlaubt (z. B. Salz), negative Werte nicht.
    expect(
      find.text('Die Kalorien dürfen nicht negativ sein.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('nutrition-entry-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-entry-close')));
    await tester.pumpAndSettle();
    expect(find.text('Fehler'), findsNothing);
    expect(find.text('Hafer'), findsOneWidget);
    expect(harness.viewModel.snapshot!.day.entries, isEmpty);
  });

  testWidgets('meal components can be edited, moved and removed by swipe', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, []);

    await _openPlanning(tester);
    await tester.tap(find.text('Neues Gericht anlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(0), 'Bowl');
    await _addManualComponent(tester, name: 'Reis', amount: '200', kcal: '130');
    await _addManualComponent(tester, name: 'Huhn', amount: '150', kcal: '165');

    // Antippen bearbeitet die Menge.
    await tester.tap(find.text('Reis'));
    await tester.pumpAndSettle();
    expect(find.text('Bestandteil bearbeiten'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('meal-component-amount')),
      '100',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sichern').last);
    await tester.pumpAndSettle();
    expect(find.text('100 g · 130 kcal'), findsOneWidget);

    // Langes Drücken: Verschieben.
    await tester.longPress(find.text('Reis'));
    await tester.pumpAndSettle();
    expect(find.text('Verschieben'), findsOneWidget);
    await tester.tap(find.text('Verschieben'));
    await tester.pumpAndSettle();
    expect(find.text('Bestandteile anordnen'), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ReorderableDragStartListener).first),
    );
    await tester.pump();
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Huhn')).dy,
      lessThan(tester.getTopLeft(find.text('Reis')).dy),
    );

    // Wischen entfernt nach Bestätigung.
    final row = find.byWidgetPredicate(
      (widget) =>
          widget is Dismissible &&
          widget.key.toString().contains('meal-component-swipe'),
    );
    await tester.drag(row.first, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Bestandteil entfernen?'), findsOneWidget);
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    expect(find.text('Huhn'), findsNothing);
    expect(find.text('Reis'), findsOneWidget);
    expect(harness.viewModel.snapshot!.day.entries, isEmpty);
  });
  testWidgets('label review shows converted values per 100 g in German', (
    tester,
  ) async {
    await _pumpDiary(
      tester,
      [],
      inTab: true,
      capture: _FakeCapture(),
      online: _LabelOnline(
        NutritionLabelScanDraft(
          basis: 'PerServing',
          servingMassGrams: 30,
          kilocalories: const NutritionLabelFieldDraft(
            originalValue: 120,
            per100Grams: 400,
            status: 'Converted',
            evidence: '120 kcal',
          ),
          proteinGrams: const NutritionLabelFieldDraft(
            originalValue: 3.75,
            per100Grams: 12.5,
            status: 'Converted',
            evidence: null,
          ),
          carbohydrateGrams: const NutritionLabelFieldDraft(
            originalValue: null,
            per100Grams: null,
            status: 'Missing',
            evidence: null,
          ),
          fatGrams: const NutritionLabelFieldDraft(
            originalValue: 400,
            per100Grams: null,
            status: 'Implausible',
            evidence: null,
          ),
          saltGrams: const NutritionLabelFieldDraft(
            originalValue: 0.36,
            per100Grams: 1.2,
            status: 'Converted',
            evidence: 'Salz 0,36 g',
          ),
          canConfirm: true,
          provider: 'OpenAI',
          providerModelVersion: 'model',
          parserVersion: 'nutrition-label-v1',
          scannedAtUtc: DateTime.utc(2026, 10, 12, 10),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('nutrition-mode-label')),
    );
    await tester.tap(find.byKey(const ValueKey('nutrition-mode-label')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Etikett fotografieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fortfahren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fotomediathek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einmalig hochladen'));
    await tester.pumpAndSettle();

    expect(find.text('pro Portion'), findsOneWidget);
    expect(find.text('400 kcal'), findsOneWidget);
    expect(find.text('12,5 g'), findsOneWidget);
    expect(find.text('1,2 g'), findsOneWidget);
    expect(find.text('nicht erkannt'), findsOneWidget);
    expect(find.text('unplausibel'), findsOneWidget);
    expect(find.textContaining('30 g pro Portion'), findsOneWidget);
    // Die Prüfseite liegt über dem Hinzufügen-Sheet und ist bedienbar.
    expect(
      find.byKey(const ValueKey('nutrition-label-close')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('dictation writes into the meal description and stops', (
    tester,
  ) async {
    final dictation = _FakeDictation();
    await _pumpDiary(tester, [], dictation: dictation);

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-mode-estimate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-dictation')));
    await tester.pump();
    expect(find.byIcon(CupertinoIcons.stop_fill), findsOneWidget);
    expect(find.textContaining('Ich höre zu.'), findsOneWidget);

    dictation.transcript = 'Zwei Eier und ein Toast';
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Zwei Eier und ein Toast'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nutrition-dictation')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(dictation.stopped, isTrue);
    expect(find.byIcon(CupertinoIcons.mic_fill), findsOneWidget);
    expect(find.text('Zwei Eier und ein Toast'), findsOneWidget);
  });

  testWidgets('closing the sheet clears the description and stops dictation', (
    tester,
  ) async {
    final dictation = _FakeDictation();
    await _pumpDiary(tester, [], dictation: dictation);

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-mode-estimate')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('nutrition-estimate-text')),
      'Pizza',
    );
    await tester.tap(find.byKey(const ValueKey('nutrition-dictation')));
    await tester.pump();
    expect(dictation.status, DictationStatus.listening);

    Navigator.of(
      tester.element(find.byKey(const ValueKey('nutrition-estimate-text'))),
    ).pop();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(dictation.status, DictationStatus.idle);

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-mode-estimate')));
    await tester.pumpAndSettle();
    expect(find.text('Pizza'), findsNothing);
  });

  testWidgets('dictation is hidden without a platform', (tester) async {
    await _pumpDiary(tester, []);
    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-mode-estimate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nutrition-dictation')), findsNothing);
  });
}

class _FakeCapture implements CapturePlatform {
  @override
  Future<CapturedImage?> capturePhoto() => chooseImage();

  @override
  Future<CapturedImage?> chooseImage() async => CapturedImage(
    bytes: Uint8List.fromList([1, 2, 3]),
    mimeType: 'image/jpeg',
  );

  @override
  Future<String?> scanBarcode() async => null;
}

class _LabelOnline implements NutritionOnlineProvider {
  _LabelOnline(this.draft);

  final NutritionLabelScanDraft draft;

  @override
  Future<NutritionLabelScanDraft> scanLabel({
    required Uint8List image,
    required String mimeType,
  }) async => draft;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeDictation implements DictationPlatform {
  String transcript = '';
  bool stopped = false;
  DictationStatus status = DictationStatus.idle;

  @override
  Future<DictationState> startDictation({required String localeId}) async {
    status = DictationStatus.listening;
    return _state;
  }

  @override
  Future<DictationState> readDictation() async => _state;

  @override
  Future<void> stopDictation() async {
    stopped = true;
    status = DictationStatus.finished;
  }

  @override
  Future<void> cancelDictation() async => status = DictationStatus.idle;

  DictationState get _state =>
      DictationState(status: status, transcript: transcript);
}

class _DiaryHarness {
  const _DiaryHarness({
    required this.viewModel,
    required this.entryIds,
    required this.store,
  });

  final NutritionViewModel viewModel;
  final List<String> entryIds;
  final LocalSyncStore store;
}

/// Zeigt das Tagebuch des 12. Oktober mit einem Breakfast-Eintrag je Name.
Future<_DiaryHarness> _pumpDiary(
  WidgetTester tester,
  List<String> names, {
  NutritionTargetSchedule? schedule,
  CapturePlatform? capture,
  NutritionOnlineProvider? online,
  DictationPlatform? dictation,
  bool inTab = false,
}) async {
  _usePhoneViewport(tester);
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final store = LocalSyncStore(database: database, accountId: accountId);
  var nextId = 300;
  final repository = NutritionRepository(
    store: store,
    ids: () =>
        '00000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}',
    clock: () => DateTime.utc(2026, 10, 12, 10),
    capture: capture,
    online: online,
  );
  if (schedule != null) await repository.saveTargetSchedule(schedule);
  final entryIds = <String>[];
  for (var index = 0; index < names.length; index++) {
    final entryId =
        '00000000-0000-4000-8000-${(200 + index).toString().padLeft(12, '0')}';
    entryIds.add(entryId);
    await repository.saveEntry(
      '2026-10-12',
      NutritionEntry(
        entryId: entryId,
        meal: NutritionMeal.breakfast,
        position: index,
        productName: names[index],
        brand: null,
        amountGrams: 100,
        per100Grams: const NutritionTotals(kilocalories: 60),
        source: null,
      ),
    );
  }
  final viewModel = NutritionViewModel(
    repository: repository,
    localDate: '2026-10-12',
    dictation: dictation,
  );
  await tester.pumpWidget(
    CupertinoApp(
      // Wie in der App: eigener Navigator je Tab, Sheets auf dem Root-Navigator.
      home: inTab
          ? CupertinoTabView(
              builder: (_) => NutritionScreen(viewModel: viewModel),
            )
          : NutritionScreen(viewModel: viewModel),
    ),
  );
  await tester.pumpAndSettle();
  return _DiaryHarness(viewModel: viewModel, entryIds: entryIds, store: store);
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

NutritionSnapshot _snapshotFor(String date) => NutritionSnapshot(
  day: NutritionDay(localDate: date, entries: const []),
  meals: const [],
  targetSchedule: null,
  recentFoods: const [],
);

class _ControlledNutritionRepository extends NutritionRepository {
  _ControlledNutritionRepository({required super.store});

  final Map<String, Completer<NutritionSnapshot>> pendingReads = {};
  bool failRemoval = false;
  bool failSave = false;

  @override
  Future<NutritionSnapshot> read(String localDate) {
    final pending = pendingReads[localDate];
    return pending?.future ?? super.read(localDate);
  }

  @override
  Future<void> removeEntry(String localDate, String entryId) {
    if (failRemoval) throw StateError('remove failed');
    return super.removeEntry(localDate, entryId);
  }

  @override
  Future<void> saveEntry(String localDate, NutritionEntry entry) {
    if (failSave) throw StateError('save failed');
    return super.saveEntry(localDate, entry);
  }
}

class _FailingNutritionOnlineProvider implements NutritionOnlineProvider {
  int searchCalls = 0;

  @override
  Future<List<NutritionFood>> searchFoods(String query) async {
    searchCalls++;
    throw const NutritionOnlineException(
      'Suche',
      422,
      'nutrition_import_not_supported',
      'Der Dienst hat die Anfrage abgelehnt. Prüfe die Eingabe oder verwende '
          'die manuelle Eingabe.',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _openPlanning(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nutrition-more-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Gerichte und Ziele verwalten'));
  await tester.pumpAndSettle();
}

/// Scrollbare Liste im obersten Sheet.
Finder _sheetScrollable() => find.descendant(
  of: find.byType(GainerSheetFrame),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

/// Fügt im Gerichtseditor über den gemeinsamen Dialog („Manuell erfassen“)
/// einen Bestandteil hinzu.
Future<void> _addManualComponent(
  WidgetTester tester, {
  required String name,
  String? brand,
  required String amount,
  required String kcal,
}) async {
  await tester.tap(find.byKey(const ValueKey('meal-component-add')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Manuell erfassen'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('nutrition-entry-name')),
    name,
  );
  if (brand != null) {
    await tester.enterText(
      find.byKey(const ValueKey('nutrition-entry-brand')),
      brand,
    );
  }
  await tester.enterText(
    find.byKey(const ValueKey('nutrition-entry-amount')),
    amount,
  );
  await tester.enterText(
    find.byKey(const ValueKey('nutrition-entry-kcal')),
    kcal,
  );
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await tester.tap(find.text('Übernehmen'));
  await tester.pumpAndSettle();
}
